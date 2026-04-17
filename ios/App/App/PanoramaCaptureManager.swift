// PanoramaCaptureManager.swift
// Sistema de captura de panoramas para nodos de navegación walkthrough.
// Cada nodo almacena posición, transform de ARKit y una imagen JPEG del frame.
//
// Estructura de archivos por proyecto:
//   Documents/Projects/<id>/panoramaNodes.json  — metadatos de todos los nodos
//   Documents/Projects/<id>/panoramas/           — carpeta de imágenes
//     panorama_001.jpg, panorama_002.jpg …

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

    // Dirección de mirada: -Z del transform de cámara ARKit
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

class PanoramaCaptureManager {

    static let shared = PanoramaCaptureManager()

    // MARK: Estado público

    /// Todos los nodos capturados en la sesión activa o cargados desde disco.
    private(set) var nodes: [PanoramaNode] = []

    /// Distancia mínima entre nodos consecutivos (metros).
    var minNodeDistance: Float = 0.5

    /// Intervalo mínimo entre capturas (segundos).
    var minCaptureInterval: TimeInterval = 1.0

    // MARK: Estado privado

    private var lastCaptureTime: Date = .distantPast
    private var nodeCounter: Int = 0
    private let fm = FileManager.default

    // Nombre de archivo de metadatos
    private static let metadataFileName = "panoramaNodes.json"
    // Subcarpeta de imágenes
    private static let imagesFolderName  = "panoramas"

    private init() {}

    // MARK: - Carpeta de proyecto activo

    /// Carpeta raíz del proyecto actual (nil si no hay proyecto activo).
    private var activeProjectFolder: URL? {
        guard let projectID = SceneLayerManager.shared.currentProjectID else { return nil }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects/\(projectID.uuidString)")
    }

    /// Subcarpeta de imágenes del proyecto activo.
    private var activePanoramasFolder: URL? {
        activeProjectFolder?.appendingPathComponent(Self.imagesFolderName)
    }

    // MARK: - capturePanorama(from:)

    /// Captura un nodo panorama desde el ARFrame actual.
    /// Solo registra si han pasado `minCaptureInterval` segundos
    /// y la cámara se movió más de `minNodeDistance` metros.
    /// - Returns: el `PanoramaNode` creado, o nil si se omitió.
    @discardableResult
    func capturePanorama(from frame: ARFrame) -> PanoramaNode? {
        let now = Date()
        guard now.timeIntervalSince(lastCaptureTime) >= minCaptureInterval else { return nil }

        let t        = frame.camera.transform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        if let last = nodes.last {
            guard simd_distance(position, last.position) >= minNodeDistance else { return nil }
        }

        // Necesitamos carpeta de proyecto activa
        guard let imagesFolder = activePanoramasFolder else { return nil }
        try? fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        // Guardar imagen JPEG
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

    // MARK: - saveNodes()

    /// Persiste el array de nodos en `<projectFolder>/panoramaNodes.json`.
    func saveNodes() {
        guard let folder = activeProjectFolder else {
            print("[PanoramaCapture] saveNodes: sin proyecto activo")
            return
        }
        saveNodes(toFolder: folder)
    }

    /// Versión interna usada por SceneProjectManager.
    func saveNodes(toFolder folder: URL) {
        let url = folder.appendingPathComponent(Self.metadataFileName)
        guard let data = try? JSONEncoder().encode(nodes) else { return }
        try? data.write(to: url, options: .atomic)
        print("[PanoramaCapture] \(nodes.count) nodos guardados → \(url.lastPathComponent)")
    }

    // MARK: - loadNodes()

    /// Carga los nodos del proyecto activo.
    func loadNodes() {
        guard let folder = activeProjectFolder else { return }
        loadNodes(fromFolder: folder)
    }

    /// Carga nodos desde una carpeta de proyecto explícita.
    /// Llamado por SceneProjectManager al restaurar un proyecto.
    func loadNodes(fromFolder folder: URL) {
        let url = folder.appendingPathComponent(Self.metadataFileName)
        guard let data   = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([PanoramaNode].self, from: data)
        else { return }

        nodes        = loaded
        nodeCounter  = (loaded.last?.index ?? -1) + 1
        lastCaptureTime = .distantPast

        print("[PanoramaCapture] \(loaded.count) nodos cargados")
        NotificationCenter.default.post(name: .panoramaNodesLoaded, object: nodes)
    }

    // MARK: - nearestNode(to:)

    /// Devuelve el nodo más cercano a una posición en espacio mundo.
    func nearestNode(to position: SIMD3<Float>) -> PanoramaNode? {
        nodes.min { simd_distance($0.position, position) < simd_distance($1.position, position) }
    }

    // MARK: - Snapping automático

    /// Indica si `position` está dentro del radio de snap de algún nodo.
    func snapNode(near position: SIMD3<Float>, radius: Float = 0.4) -> PanoramaNode? {
        guard let nearest = nearestNode(to: position) else { return nil }
        return simd_distance(nearest.position, position) <= radius ? nearest : nil
    }

    // MARK: - Conversión a NavigationManager.CameraNode (para NavigationPlaybackController)

    func asCameraNodes() -> [NavigationManager.CameraNode] {
        nodes.enumerated().map { i, n in
            NavigationManager.CameraNode(
                index:     i,
                position:  n.position,
                forward:   n.forward,
                transform: n.transform
            )
        }
    }

    // MARK: - Trayectoria (compatibilidad legacy)

    func getTrajectory() -> [SIMD3<Float>] {
        nodes.map { $0.position }
    }

    var totalPathLength: Float {
        guard nodes.count > 1 else { return 0 }
        var total: Float = 0
        for i in 1..<nodes.count {
            total += simd_distance(nodes[i].position, nodes[i-1].position)
        }
        return total
    }

    // MARK: - Reset

    func reset() {
        nodes           = []
        nodeCounter     = 0
        lastCaptureTime = .distantPast
    }

    // MARK: - JPEG desde CVPixelBuffer

    private func jpegData(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.75) -> Data? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    /// Emitida al capturar un nuevo nodo (object: PanoramaNode).
    static let panoramaNodeAdded   = Notification.Name("mi_render_panoramaNodeAdded")

    /// Emitida al cargar nodos desde disco (object: [PanoramaNode]).
    static let panoramaNodesLoaded = Notification.Name("mi_render_panoramaNodesLoaded")
}
