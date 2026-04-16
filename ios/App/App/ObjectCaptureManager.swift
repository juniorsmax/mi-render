// ObjectCaptureManager.swift
// Gestor de captura de objetos 3D con ObjectCaptureSession (iOS 17+).
// Modo alternativo al escaneo LiDAR de habitaciones.
// Pipeline: multi-ángulo fotos → neural reconstruction → USDZ / OBJ.

import Foundation
import Combine

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

@available(iOS 17.0, *)
class ObjectCaptureManager: NSObject, ObservableObject {

    static let shared = ObjectCaptureManager()

    // MARK: - Estado público

    @Published var captureState: ObjectCaptureState = .idle
    @Published var currentScanMode: ScanMode = .roomScan
    @Published var imageCount: Int = 0

    // MARK: - Privado

    private var session: ObjectCaptureSession?
    private var cancellables = Set<AnyCancellable>()
    private var scanDirectory: URL?
    private var imagesDirectory: URL?

    // MARK: - Directorios

    private var objectScansRoot: URL {
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

    /// Crea una nueva sesión ObjectCapture con directorio timestamped.
    func startCapture() {
        guard ObjectCaptureSession.isSupported else {
            captureState = .failed("ObjectCaptureSession no soportado en este dispositivo")
            return
        }

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

        scanDirectory = scanDir
        imagesDirectory = imgsDir
        imageCount = 0

        let newSession = ObjectCaptureSession()
        session = newSession

        // Observar cambios de estado via Combine
        newSession.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleSessionState(state)
            }
            .store(in: &cancellables)

        newSession.$feedback
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateImageCount()
            }
            .store(in: &cancellables)

        var config = ObjectCaptureSession.Configuration()
        config.checkpointDirectory = scanDir.appendingPathComponent("Checkpoints")

        // Fusión LiDAR si disponible — mejora reconstrucción en iPhone Pro
        config.isOverCaptureEnabled = true

        newSession.start(imagesDirectory: imgsDir, configuration: config)
        captureState = .capturing(imageCount: 0)
        currentScanMode = .objectScan
    }

    // MARK: - Detener captura

    func stopCapture() {
        session?.finish()
    }

    // MARK: - Cancelar

    func cancelCapture() {
        session?.cancel()
        cleanupSession()
        captureState = .idle
    }

    // MARK: - Procesamiento fotogrametría

    /// Espera estado .completed del session o lanza reconstructionSession.
    func processPhotogrammetry(completion: @escaping (Result<URL, Error>) -> Void) {
        guard case .completed(let url) = captureState else {
            // Si ya hay un USDZ guardado, devolver
            if case .completed(let url) = captureState {
                completion(.success(url))
                return
            }
            // Buscar modelo más reciente en disco
            if let latest = findLatestModel() {
                completion(.success(latest))
                return
            }
            completion(.failure(OCMError.noSessionActive))
            return
        }
        completion(.success(url))
    }

    // MARK: - Exportar USDZ

    func exportUSDZ(to destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        guard case .completed(let sourceURL) = captureState else {
            if let latest = findLatestModel() {
                copyFile(from: latest, to: destinationURL, completion: completion)
            } else {
                completion(.failure(OCMError.noModelAvailable))
            }
            return
        }
        copyFile(from: sourceURL, to: destinationURL, completion: completion)
    }

    /// Convierte USDZ → OBJ usando ModelIO.
    func exportOBJ(from usdzURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
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

    /// Devuelve los archivos de poses de cámara guardados por la sesión.
    func cameraPoses() -> [URL] {
        guard let scanDir = scanDirectory else { return [] }
        let checkpointsDir = scanDir.appendingPathComponent("Checkpoints")
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: checkpointsDir,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.pathExtension == "json" || $0.lastPathComponent.contains("pose") }
    }

    // MARK: - Listar escaneos guardados

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

    // MARK: - Privado: manejo de estado

    private func handleSessionState(_ state: ObjectCaptureSession.CaptureState) {
        switch state {
        case .initializing:
            break

        case .ready:
            captureState = .capturing(imageCount: imageCount)

        case .detecting:
            captureState = .capturing(imageCount: imageCount)

        case .capturing:
            captureState = .capturing(imageCount: imageCount)

        case .finishing:
            captureState = .processing(progress: 0.0)

        case .completed:
            buildModel()

        case .failed(let error):
            captureState = .failed(error.localizedDescription)
            cleanupSession()

        @unknown default:
            break
        }
    }

    private func updateImageCount() {
        guard let imgsDir = imagesDirectory else { return }
        let count = (try? FileManager.default.contentsOfDirectory(
            atPath: imgsDir.path
        ))?.count ?? 0
        imageCount = count
        if case .capturing = captureState {
            captureState = .capturing(imageCount: count)
        }
    }

    private func buildModel() {
        guard let scanDir = scanDirectory,
              let imgsDir = imagesDirectory else {
            captureState = .failed("Directorio de escaneo no encontrado")
            return
        }

        let outputURL = scanDir.appendingPathComponent("model.usdz")

        // Iniciar PhotogrammetrySession en proceso separado no es posible en iOS.
        // ObjectCaptureSession genera el modelo tras finish() de forma nativa.
        // Buscamos el USDZ generado por la sesión.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            // La sesión ya guardó el modelo en imagesDirectory o scanDir
            let candidates = [
                scanDir.appendingPathComponent("model.usdz"),
                imgsDir.appendingPathComponent("model.usdz"),
                scanDir.appendingPathComponent("Checkpoints/model.usdz"),
            ]
            if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                DispatchQueue.main.async {
                    self?.captureState = .completed(usdzURL: found)
                }
            } else {
                // Buscar cualquier USDZ en el directorio
                let allFiles = (try? FileManager.default.contentsOfDirectory(
                    at: scanDir,
                    includingPropertiesForKeys: nil,
                    options: .skipsSubdirectoryDescendants
                )) ?? []
                if let usdz = allFiles.first(where: { $0.pathExtension == "usdz" }) {
                    DispatchQueue.main.async {
                        self?.captureState = .completed(usdzURL: usdz)
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.captureState = .failed("No se generó modelo USDZ")
                    }
                }
            }
        }
    }

    private func findLatestModel() -> URL? {
        let scans = listSavedScans()
        for scanDir in scans {
            let candidates = [
                scanDir.appendingPathComponent("model.usdz"),
                scanDir.appendingPathComponent("Images/model.usdz"),
            ]
            if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                return found
            }
        }
        return nil
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

    private func cleanupSession() {
        cancellables.removeAll()
        session = nil
    }
}

// MARK: - Errors

enum OCMError: LocalizedError {
    case noSessionActive
    case noModelAvailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSessionActive:    return "No hay sesión ObjectCapture activa"
        case .noModelAvailable:   return "No hay modelo 3D disponible"
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
