// PanoramaCaptureManager.swift
// Sistema de captura, costura y persistencia de panoramas para navegación walkthrough.
//
// Ciclo de uso:
//   startCapture()           → arranca ARSession interna + activa recepción de frames
//   stopCapture()            → pausa ARSession, finaliza la lista de nodos
//   exportPanorama()         → cose todos los frames capturados en una tira horizontal
//                              y guarda panorama_stitched.jpg en la carpeta del proyecto
//   loadPanorama()           → carga panorama_stitched.jpg desde disco → UIImage?
//
// Compatibilidad simulador:
//   ARSession y ARFrame están guardados tras #if !targetEnvironment(simulator).
//   En simulador: startCapture/stopCapture son no-op; exportPanorama devuelve
//   un placeholder generado programáticamente; loadPanorama devuelve el mismo.
//
// Estructura de archivos por proyecto:
//   Documents/Projects/<id>/panoramaNodes.json      — metadatos de nodos
//   Documents/Projects/<id>/panoramas/              — frames individuales
//     panorama_001.jpg, panorama_002.jpg …
//   Documents/Projects/<id>/panorama_stitched.jpg   — costura final

import ARKit
import UIKit
import simd

// MARK: - PanoramaNode

struct PanoramaNode: Identifiable, Hashable {
    let id:        UUID
    let position:  SIMD3<Float>
    let transform: simd_float4x4
    let imageURL:  URL
    let timestamp: Date
    let index:     Int

    /// Dirección de mirada: -Z del transform de cámara ARKit.
    var forward: SIMD3<Float> {
        let col = transform.columns.2
        return SIMD3<Float>(-col.x, -col.y, -col.z)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PanoramaNode, rhs: PanoramaNode) -> Bool { lhs.id == rhs.id }
}

// MARK: - PanoramaNode: Codable (manual — SIMD no es Codable nativo)

extension PanoramaNode: Codable {

    enum CodingKeys: String, CodingKey {
        case id, imageURL, timestamp, index
        case px, py, pz
        case t00, t01, t02, t03
        case t10, t11, t12, t13
        case t20, t21, t22, t23
        case t30, t31, t32, t33
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,        forKey: .id)
        try c.encode(imageURL,  forKey: .imageURL)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(index,     forKey: .index)
        try c.encode(position.x, forKey: .px)
        try c.encode(position.y, forKey: .py)
        try c.encode(position.z, forKey: .pz)
        let m = transform
        try c.encode(m.columns.0.x, forKey: .t00); try c.encode(m.columns.0.y, forKey: .t01)
        try c.encode(m.columns.0.z, forKey: .t02); try c.encode(m.columns.0.w, forKey: .t03)
        try c.encode(m.columns.1.x, forKey: .t10); try c.encode(m.columns.1.y, forKey: .t11)
        try c.encode(m.columns.1.z, forKey: .t12); try c.encode(m.columns.1.w, forKey: .t13)
        try c.encode(m.columns.2.x, forKey: .t20); try c.encode(m.columns.2.y, forKey: .t21)
        try c.encode(m.columns.2.z, forKey: .t22); try c.encode(m.columns.2.w, forKey: .t23)
        try c.encode(m.columns.3.x, forKey: .t30); try c.encode(m.columns.3.y, forKey: .t31)
        try c.encode(m.columns.3.z, forKey: .t32); try c.encode(m.columns.3.w, forKey: .t33)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,  forKey: .id)
        imageURL  = try c.decode(URL.self,   forKey: .imageURL)
        timestamp = try c.decode(Date.self,  forKey: .timestamp)
        index     = try c.decode(Int.self,   forKey: .index)
        position = SIMD3<Float>(
            try c.decode(Float.self, forKey: .px),
            try c.decode(Float.self, forKey: .py),
            try c.decode(Float.self, forKey: .pz)
        )
        transform = simd_float4x4(columns: (
            SIMD4<Float>(
                try c.decode(Float.self, forKey: .t00), try c.decode(Float.self, forKey: .t01),
                try c.decode(Float.self, forKey: .t02), try c.decode(Float.self, forKey: .t03)
            ),
            SIMD4<Float>(
                try c.decode(Float.self, forKey: .t10), try c.decode(Float.self, forKey: .t11),
                try c.decode(Float.self, forKey: .t12), try c.decode(Float.self, forKey: .t13)
            ),
            SIMD4<Float>(
                try c.decode(Float.self, forKey: .t20), try c.decode(Float.self, forKey: .t21),
                try c.decode(Float.self, forKey: .t22), try c.decode(Float.self, forKey: .t23)
            ),
            SIMD4<Float>(
                try c.decode(Float.self, forKey: .t30), try c.decode(Float.self, forKey: .t31),
                try c.decode(Float.self, forKey: .t32), try c.decode(Float.self, forKey: .t33)
            )
        ))
    }
}

// MARK: - PanoramaCaptureManager

final class PanoramaCaptureManager: NSObject {

    static let shared = PanoramaCaptureManager()

    // MARK: - Estado público

    /// Nodos capturados en la sesión activa o restaurados desde disco.
    private(set) var nodes: [PanoramaNode] = []

    /// true entre startCapture() y stopCapture().
    private(set) var isCapturing: Bool = false

    /// Distancia mínima entre nodos consecutivos (metros).
    var minNodeDistance: Float = 0.5

    /// Intervalo mínimo entre capturas de frame (segundos).
    var minCaptureInterval: TimeInterval = 1.0

    // MARK: - Estado privado

    private var lastCaptureTime: Date = .distantPast
    private var nodeCounter: Int = 0
    private let fm = FileManager.default

    private static let metadataFileName = "panoramaNodes.json"
    private static let imagesFolderName  = "panoramas"
    private static let stitchedFileName  = "panorama_stitched.jpg"

#if !targetEnvironment(simulator)
    private var arSession: ARSession?
#endif

    private override init() {}

    // MARK: - Carpetas de proyecto

    private var activeProjectFolder: URL? {
        guard let projectID = SceneLayerManager.shared.currentProjectID else { return nil }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects/\(projectID.uuidString)")
    }

    private var activePanoramasFolder: URL? {
        activeProjectFolder?.appendingPathComponent(Self.imagesFolderName)
    }

    private var stitchedPanoramaURL: URL? {
        activeProjectFolder?.appendingPathComponent(Self.stitchedFileName)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: startCapture()

    /// Inicia la captura de panorama.
    /// En dispositivo real: arranca una ARSession de world tracking.
    /// En simulador: solo activa el flag `isCapturing`.
    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        reset()

#if targetEnvironment(simulator)
        print("[PanoramaCapture] Simulador — AR desactivado, modo placeholder activo")
#else
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = []
        arSession = ARSession()
        arSession?.delegate = self
        arSession?.run(config, options: [.resetTracking, .removeExistingAnchors])
        print("[PanoramaCapture] ARSession iniciada")
#endif
        NotificationCenter.default.post(name: .panoramaCaptureDidStart, object: nil)
    }

    // MARK: stopCapture()

    /// Detiene la captura y persiste los nodos automáticamente si hay proyecto activo.
    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false

#if !targetEnvironment(simulator)
        arSession?.pause()
        arSession = nil
#endif

        saveNodes()
        print("[PanoramaCapture] Captura detenida — \(nodes.count) nodos")
        NotificationCenter.default.post(name: .panoramaCaptureDidStop, object: nodes)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: exportPanorama()

    /// Cose todos los frames capturados en una tira horizontal y la guarda en disco.
    /// - Returns: URL del archivo panorama_stitched.jpg, o nil si falla.
    @discardableResult
    func exportPanorama() -> URL? {
#if targetEnvironment(simulator)
        return exportSimulatorPlaceholder()
#else
        return stitchAndSave()
#endif
    }

    // MARK: loadPanorama()

    /// Carga la costura guardada como UIImage.
    /// En simulador devuelve el placeholder generado.
    /// - Returns: UIImage del panorama, o nil si no existe.
    func loadPanorama() -> UIImage? {
#if targetEnvironment(simulator)
        return makeSimulatorPlaceholder()
#else
        guard let url = stitchedPanoramaURL,
              fm.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
#endif
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: capturePanorama(from:)  — alimentado externamente o por ARSessionDelegate

    /// Captura un nodo desde un ARFrame externo (frame del escáner principal).
    /// Solo registra si se cumplen los umbrales de distancia e intervalo.
    @discardableResult
    func capturePanorama(from frame: ARFrame) -> PanoramaNode? {
        guard isCapturing || true else { return nil }   // acepta frames externos siempre

        let now = Date()
        guard now.timeIntervalSince(lastCaptureTime) >= minCaptureInterval else { return nil }

        let t        = frame.camera.transform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        if let last = nodes.last {
            guard simd_distance(position, last.position) >= minNodeDistance else { return nil }
        }

        guard let imagesFolder = activePanoramasFolder else { return nil }
        try? fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        let filename = String(format: "panorama_%03d.jpg", nodeCounter + 1)
        let imageURL = imagesFolder.appendingPathComponent(filename)
        if let jpeg = jpegData(from: frame.capturedImage) {
            try? jpeg.write(to: imageURL, options: .atomic)
        }

        let node = PanoramaNode(
            id:        UUID(),
            position:  position,
            transform: t,
            imageURL:  imageURL,
            timestamp: now,
            index:     nodeCounter
        )

        nodes.append(node)
        nodeCounter    += 1
        lastCaptureTime = now

        NotificationCenter.default.post(name: .panoramaNodeAdded, object: node)
        return node
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: Persistencia de nodos

    func saveNodes() {
        guard let folder = activeProjectFolder else { return }
        saveNodes(toFolder: folder)
    }

    func saveNodes(toFolder folder: URL) {
        let url = folder.appendingPathComponent(Self.metadataFileName)
        guard let data = try? JSONEncoder().encode(nodes) else { return }
        try? data.write(to: url, options: .atomic)
        print("[PanoramaCapture] \(nodes.count) nodos guardados")
    }

    func loadNodes() {
        guard let folder = activeProjectFolder else { return }
        loadNodes(fromFolder: folder)
    }

    func loadNodes(fromFolder folder: URL) {
        let url = folder.appendingPathComponent(Self.metadataFileName)
        guard let data   = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([PanoramaNode].self, from: data)
        else { return }
        nodes           = loaded
        nodeCounter     = (loaded.last?.index ?? -1) + 1
        lastCaptureTime = .distantPast
        print("[PanoramaCapture] \(loaded.count) nodos restaurados")
        NotificationCenter.default.post(name: .panoramaNodesLoaded, object: nodes)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: Consultas

    func nearestNode(to position: SIMD3<Float>) -> PanoramaNode? {
        nodes.min { simd_distance($0.position, position) < simd_distance($1.position, position) }
    }

    func snapNode(near position: SIMD3<Float>, radius: Float = 0.4) -> PanoramaNode? {
        guard let n = nearestNode(to: position) else { return nil }
        return simd_distance(n.position, position) <= radius ? n : nil
    }

    func asCameraNodes() -> [NavigationManager.CameraNode] {
        nodes.enumerated().map { i, n in
            NavigationManager.CameraNode(index: i, position: n.position,
                                         forward: n.forward, transform: n.transform)
        }
    }

    func getTrajectory() -> [SIMD3<Float>] { nodes.map { $0.position } }

    var totalPathLength: Float {
        guard nodes.count > 1 else { return 0 }
        return (1..<nodes.count).reduce(0) { $0 + simd_distance(nodes[$1].position, nodes[$1-1].position) }
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: Reset

    func reset() {
        nodes           = []
        nodeCounter     = 0
        lastCaptureTime = .distantPast
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: Privado — costura de frames

    /// Cose los JPEGs de todos los nodos en una tira horizontal.
    private func stitchAndSave() -> URL? {
        let images: [UIImage] = nodes.compactMap { node in
            guard fm.fileExists(atPath: node.imageURL.path) else { return nil }
            return UIImage(contentsOfFile: node.imageURL.path)
        }
        guard !images.isEmpty else { return nil }

        let frameW = images[0].size.width
        let frameH = images[0].size.height
        let totalW = frameW * CGFloat(images.count)
        let size   = CGSize(width: totalW, height: frameH)

        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        for (i, img) in images.enumerated() {
            img.draw(in: CGRect(x: frameW * CGFloat(i), y: 0, width: frameW, height: frameH))
        }

        guard let stitched   = UIGraphicsGetImageFromCurrentImageContext(),
              let jpegData   = stitched.jpegData(compressionQuality: 0.80),
              let outputURL  = stitchedPanoramaURL
        else { return nil }

        try? jpegData.write(to: outputURL, options: .atomic)
        print("[PanoramaCapture] Panorama guardado → \(outputURL.lastPathComponent) (\(images.count) frames)")
        NotificationCenter.default.post(name: .panoramaExportDidFinish, object: outputURL)
        return outputURL
    }

    // MARK: Simulador — placeholder

    private func exportSimulatorPlaceholder() -> URL? {
        guard let folder = activeProjectFolder,
              let jpeg   = makeSimulatorPlaceholder()?.jpegData(compressionQuality: 0.80)
        else { return nil }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(Self.stitchedFileName)
        try? jpeg.write(to: url, options: .atomic)
        NotificationCenter.default.post(name: .panoramaExportDidFinish, object: url)
        return url
    }

    private func makeSimulatorPlaceholder() -> UIImage? {
        let size = CGSize(width: 800, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // Fondo degradado azul-gris
            let colors = [UIColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 1).cgColor,
                          UIColor(red: 0.22, green: 0.30, blue: 0.42, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray,
                                      locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient,
                                             start: .zero,
                                             end: CGPoint(x: size.width, y: size.height),
                                             options: [])
            // Texto central
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.75),
            ]
            let label = "Panorama — Simulator Placeholder"
            let textSize = label.size(withAttributes: attrs)
            let textRect = CGRect(x: (size.width  - textSize.width)  / 2,
                                  y: (size.height - textSize.height) / 2,
                                  width: textSize.width, height: textSize.height)
            label.draw(in: textRect, withAttributes: attrs)
        }
    }

    // MARK: Privado — JPEG desde CVPixelBuffer

    private func jpegData(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.75) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}

// MARK: - ARSessionDelegate (solo dispositivo real)

#if !targetEnvironment(simulator)
extension PanoramaCaptureManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        capturePanorama(from: frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[PanoramaCapture] ARSession error: \(error.localizedDescription)")
        isCapturing = false
        NotificationCenter.default.post(name: .panoramaCaptureDidStop, object: nil)
    }
}
#endif

// MARK: - Notification.Name

extension Notification.Name {
    /// Emitida al iniciar captura.
    static let panoramaCaptureDidStart  = Notification.Name("mi_render_panoramaCaptureDidStart")
    /// Emitida al detener captura (object: [PanoramaNode]).
    static let panoramaCaptureDidStop   = Notification.Name("mi_render_panoramaCaptureDidStop")
    /// Emitida al capturar un nodo (object: PanoramaNode).
    static let panoramaNodeAdded        = Notification.Name("mi_render_panoramaNodeAdded")
    /// Emitida al cargar nodos desde disco (object: [PanoramaNode]).
    static let panoramaNodesLoaded      = Notification.Name("mi_render_panoramaNodesLoaded")
    /// Emitida al terminar exportPanorama() (object: URL del archivo .jpg).
    static let panoramaExportDidFinish  = Notification.Name("mi_render_panoramaExportDidFinish")
}
