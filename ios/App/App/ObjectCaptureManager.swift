// ObjectCaptureManager.swift
// Gestor de captura de objetos 3D.
// Captura frames ARKit multi-ángulo y gestiona directorios de escaneo.
// API: startCapture / stopCapture / exportUSDZ / exportOBJ
// Para integrar ObjectCaptureSession (iOS 17+ LiDAR) añadir
// en Xcode con target mínimo iOS 17 y import RealityKit.

import Foundation
import ARKit
import RealityKit
import ModelIO
import UIKit
import simd

// MARK: - ScanMode

/// Modo de operación del pipeline de escaneo.
enum ScanMode: String, CaseIterable {
    case roomScan   = "roomScan"    // ARKit LiDAR mesh
    case objectScan = "objectScan"  // ObjectCapture fotogrametría
}

// MARK: - ObjectCaptureState

enum ObjectCaptureState: Equatable {
    case idle
    case capturing(imageCount: Int)
    case processing(progress: Double)
    case completed(usdzURL: URL)
    case failed(String)
}

// MARK: - ObjectCaptureManager

class ObjectCaptureManager: NSObject, ObservableObject {

    static let shared = ObjectCaptureManager()

    // MARK: - Estado público

    @Published var captureState: ObjectCaptureState = .idle
    @Published var currentScanMode: ScanMode = .roomScan
    @Published var imageCount: Int = 0

    // MARK: - Privado

    private var scanDirectory: URL?
    private var imagesDirectory: URL?
    private var captureActive: Bool = false

    // Poses de cámara guardadas durante la captura
    private var capturedPoses: [simd_float4x4] = []

    // MARK: - Directorios

    var objectScansRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ObjectScans", isDirectory: true)
    }

    // MARK: - Init

    override private init() {
        super.init()
        createRootDirectoryIfNeeded()
    }

    private func createRootDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: objectScansRoot,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Iniciar captura

    /// Prepara directorio de escaneo y activa el modo objectScan.
    /// Los frames se añaden vía captureFrame(from:transform:).
    func startCapture() {
        let ts = Int(Date().timeIntervalSince1970)
        let scanDir = objectScansRoot.appendingPathComponent("scan_\(ts)", isDirectory: true)
        let imgsDir = scanDir.appendingPathComponent("Images", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: scanDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imgsDir, withIntermediateDirectories: true)
        } catch {
            captureState = .failed("No se pudo crear directorio: \(error.localizedDescription)")
            return
        }

        scanDirectory    = scanDir
        imagesDirectory  = imgsDir
        imageCount       = 0
        capturedPoses    = []
        captureActive    = true
        captureState     = .capturing(imageCount: 0)
        currentScanMode  = .objectScan
    }

    // MARK: - Captura de frames ARKit

    /// Recibe un frame de ARSession (desde LiDARPlugin / ScanManager) y lo guarda como JPEG.
    /// Llamar en cada frame relevante (p.ej. cada ~10 frames) mientras captureActive.
    func captureFrame(pixelBuffer: CVPixelBuffer, transform: simd_float4x4) {
        guard captureActive, let imgsDir = imagesDirectory else { return }
        let idx = imageCount
        capturedPoses.append(transform)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            // Convertir CVPixelBuffer → UIImage → JPEG
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            let uiImage = UIImage(cgImage: cgImage)
            guard let jpegData = uiImage.jpegData(compressionQuality: 0.85) else { return }

            let imgURL = imgsDir.appendingPathComponent(String(format: "frame_%04d.jpg", idx))
            try? jpegData.write(to: imgURL, options: .atomic)

            DispatchQueue.main.async {
                self.imageCount += 1
                self.captureState = .capturing(imageCount: self.imageCount)
            }
        }
    }

    // MARK: - Detener captura

    func stopCapture() {
        captureActive = false
        savePoses()
        captureState = .processing(progress: 0.0)
        // La reconstrucción requiere ObjectCaptureSession (iOS 17+).
        // Si hay un USDZ previo en el directorio, se marca como completado.
        if let usdz = findUsdzInCurrentScan() {
            captureState = .completed(usdzURL: usdz)
        } else {
            // Sin ObjectCaptureSession no se genera USDZ automáticamente.
            // El usuario puede importar un USDZ externo con importUSDZ(at:).
            captureState = .idle
        }
    }

    // MARK: - Cancelar

    func cancelCapture() {
        captureActive = false
        capturedPoses = []
        captureState  = .idle
    }

    // MARK: - Importar USDZ externo

    /// Asocia un USDZ generado externamente (ej. ObjectCapture en macOS) al escaneo actual.
    func importUSDZ(at sourceURL: URL) {
        guard let scanDir = scanDirectory else {
            captureState = .failed("No hay escaneo activo")
            return
        }
        let dest = scanDir.appendingPathComponent("model.usdz")
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            captureState = .completed(usdzURL: dest)
        } catch {
            captureState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Exportar USDZ

    func exportUSDZ(to destinationURL: URL,
                    completion: @escaping (Result<URL, Error>) -> Void) {
        let source: URL?
        if case .completed(let url) = captureState {
            source = url
        } else {
            source = findLatestModel()
        }
        guard let src = source else {
            completion(.failure(OCMError.noModelAvailable))
            return
        }
        copyFile(from: src, to: destinationURL, completion: completion)
    }

    // MARK: - Exportar OBJ via ModelIO

    func exportOBJ(from usdzURL: URL,
                   completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let objURL = usdzURL.deletingPathExtension().appendingPathExtension("obj")
            do {
                let asset = MDLAsset(url: usdzURL)
                try asset.export(to: objURL)
                DispatchQueue.main.async { completion(.success(objURL)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: - Camera poses

    /// Devuelve las matrices de transform guardadas durante la captura.
    func cameraPoses() -> [simd_float4x4] { capturedPoses }

    /// Devuelve el archivo poses.json del directorio de escaneo actual.
    func cameraPosesURL() -> URL? {
        scanDirectory?.appendingPathComponent("poses.json")
    }

    // MARK: - Listar escaneos

    func listSavedScans() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: objectScansRoot,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return contents
            .filter { $0.hasDirectoryPath }
            .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
    }

    func deleteScan(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - Privado

    private func savePoses() {
        guard let scanDir = scanDirectory, !capturedPoses.isEmpty else { return }
        // Serializar matrices 4x4 como array de [Float] (16 valores cada una)
        let flat: [[Float]] = capturedPoses.map { m in
            [m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.0.w,
             m.columns.1.x, m.columns.1.y, m.columns.1.z, m.columns.1.w,
             m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.2.w,
             m.columns.3.x, m.columns.3.y, m.columns.3.z, m.columns.3.w]
        }
        if let data = try? JSONEncoder().encode(flat) {
            let posesURL = scanDir.appendingPathComponent("poses.json")
            try? data.write(to: posesURL, options: .atomic)
        }
    }

    private func findUsdzInCurrentScan() -> URL? {
        guard let scanDir = scanDirectory else { return nil }
        return findUsdz(in: scanDir)
    }

    private func findLatestModel() -> URL? {
        for scanDir in listSavedScans() {
            if let usdz = findUsdz(in: scanDir) { return usdz }
        }
        return nil
    }

    private func findUsdz(in directory: URL) -> URL? {
        let candidates = [
            directory.appendingPathComponent("model.usdz"),
            directory.appendingPathComponent("Images/model.usdz"),
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return found
        }
        // Búsqueda en el directorio raíz
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsSubdirectoryDescendants
        )) ?? []
        return contents.first(where: { $0.pathExtension == "usdz" })
    }

    private func copyFile(from source: URL, to destination: URL,
                          completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: source, to: destination)
                DispatchQueue.main.async { completion(.success(destination)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}

// MARK: - Errors

enum OCMError: LocalizedError {
    case noSessionActive
    case noModelAvailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSessionActive:     return "No hay sesión de captura activa"
        case .noModelAvailable:    return "No hay modelo 3D disponible"
        case .exportFailed(let m): return "Error de exportación: \(m)"
        }
    }
}

// MARK: - URL extension

private extension URL {
    var creationDate: Date? {
        (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}
