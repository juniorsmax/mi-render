// PanoramaCaptureManager.swift
// Sistema de captura espacial, costura y persistencia de panoramas.
//
// Ciclo de uso:
//   startCapture()              → arranca ARSession + activa recepción de frames
//   stopCapture()               → pausa ARSession, finaliza la captura
//   saveSession()               → persiste CaptureSession + nodos + frames en disco
//   loadSession()               → restaura sesión completa desde disco
//   exportPanoramaTexture()     → cose todos los frames → TextureResource (RealityKit)
//
// Estructuras de datos clave:
//   CaptureSession   — metadatos de sesión (fechas, instrínsecos, deviceModel)
//   CapturedFrame    — frame individual: transform, timestamp, intrínsecos, URL imagen
//   PanoramaNode     — nodo de navegación derivado de CapturedFrame
//
// Preparado para reconstrucción de malla futura:
//   CapturedFrame almacena fx/fy/cx/cy (intrínsecos de cámara) y
//   resolución del sensor — suficiente para SfM / NeRF pipelines.
//
// Compatibilidad simulador:
//   ARSession y ARFrame detrás de #if !targetEnvironment(simulator).
//   Simulador: startCapture/stopCapture son seguros; exportPanoramaTexture
//   devuelve TextureResource generada desde placeholder programático.
//
// Estructura de archivos por proyecto:
//   Documents/Projects/<id>/session.json           — CaptureSession
//   Documents/Projects/<id>/panoramaNodes.json     — PanoramaNode[]
//   Documents/Projects/<id>/panoramas/             — frames JPEG
//     panorama_001.jpg …
//   Documents/Projects/<id>/panorama_stitched.jpg  — costura final

import ARKit
import UIKit
import RealityKit
import simd

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: CapturedFrame

/// Representa un único frame capturado con todos los datos necesarios para
/// reconstrucción futura (SfM, NeRF, photogrammetry).
struct CapturedFrame: Codable {
    let id:        UUID
    let index:     Int
    let timestamp: Date
    let imageURL:  URL

    // Posición de cámara
    let px: Float; let py: Float; let pz: Float

    // Transform columna-mayor (16 floats)
    let t00: Float; let t01: Float; let t02: Float; let t03: Float
    let t10: Float; let t11: Float; let t12: Float; let t13: Float
    let t20: Float; let t21: Float; let t22: Float; let t23: Float
    let t30: Float; let t31: Float; let t32: Float; let t33: Float

    // Intrínsecos de cámara — para reconstrucción futura
    let focalLengthX:  Float   // fx
    let focalLengthY:  Float   // fy
    let principalX:    Float   // cx
    let principalY:    Float   // cy
    let imageWidth:    Int
    let imageHeight:   Int

    // Referencia de alineación de profundidad
    let depthConfidence: Float?      // 0–1 promedio del depth map (nil si no disponible)
    let hasDepthData:    Bool        // true si el frame tenía sceneDepth

    // Helpers computados (no persistidos)
    var position: SIMD3<Float> { SIMD3(px, py, pz) }

    var transform: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(t00, t01, t02, t03),
            SIMD4(t10, t11, t12, t13),
            SIMD4(t20, t21, t22, t23),
            SIMD4(t30, t31, t32, t33)
        ))
    }

    var forward: SIMD3<Float> {
        let m = transform
        return SIMD3<Float>(-m.columns.2.x, -m.columns.2.y, -m.columns.2.z)
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: CaptureSession

/// Metadatos de una sesión de captura completa.
/// Preparado para pipelines de reconstrucción: guarda deviceModel, SO,
/// número de frames y bounding box del recorrido.
struct CaptureSession: Codable {
    let id:          UUID
    let startDate:   Date
    var endDate:     Date?
    var frameCount:  Int
    var pathLength:  Float      // metros totales recorridos
    let deviceModel: String
    let osVersion:   String

    // Bounding box del recorrido — útil para alinear con la malla
    var minX: Float; var minY: Float; var minZ: Float
    var maxX: Float; var maxY: Float; var maxZ: Float

    // Instrínsecos del primer frame (referencia para reconstrucción)
    var focalLengthX: Float
    var focalLengthY: Float
    var principalX:   Float
    var principalY:   Float
    var imageWidth:   Int
    var imageHeight:  Int

    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>) {
        (SIMD3(minX, minY, minZ), SIMD3(maxX, maxY, maxZ))
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: PanoramaNode

/// Nodo de navegación derivado de un CapturedFrame.
/// Usado por NavigationPlaybackController y SceneViewer.
struct PanoramaNode: Identifiable, Hashable {
    let id:        UUID
    let position:  SIMD3<Float>
    let transform: simd_float4x4
    let imageURL:  URL
    let timestamp: Date
    let index:     Int

    var forward: SIMD3<Float> {
        let col = transform.columns.2
        return SIMD3<Float>(-col.x, -col.y, -col.z)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: PanoramaNode, rhs: PanoramaNode) -> Bool { lhs.id == rhs.id }
}

// MARK: PanoramaNode: Codable (manual — SIMD no es Codable nativo)

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
        try c.encode(id, forKey: .id); try c.encode(imageURL, forKey: .imageURL)
        try c.encode(timestamp, forKey: .timestamp); try c.encode(index, forKey: .index)
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
        position  = SIMD3<Float>(
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

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: PanoramaCaptureManager

final class PanoramaCaptureManager: NSObject {

    static let shared = PanoramaCaptureManager()

    // MARK: Estado público

    private(set) var nodes:           [PanoramaNode]   = []
    private(set) var capturedFrames:  [CapturedFrame]  = []
    private(set) var currentSession:  CaptureSession?
    private(set) var isCapturing:     Bool = false

    var minNodeDistance:    Float         = 0.5
    var minCaptureInterval: TimeInterval  = 1.0

    // MARK: Estado privado

    private var lastCaptureTime: Date  = .distantPast
    private var nodeCounter:     Int   = 0
    private let fm = FileManager.default

    private static let sessionFileName   = "session.json"
    private static let metadataFileName  = "panoramaNodes.json"
    private static let framesFileName    = "capturedFrames.json"
    private static let imagesFolderName  = "panoramas"
    private static let stitchedFileName  = "panorama_stitched.jpg"

#if !targetEnvironment(simulator)
    private var arSession: ARSession?
#endif

    private override init() {}

    // MARK: ─── Carpetas ───────────────────────────────────────────────────

    private var activeProjectFolder: URL? {
        guard let id = SceneLayerManager.shared.currentProjectID else { return nil }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("projects/\(id.uuidString)")
    }

    private var panoramasFolder: URL? {
        activeProjectFolder?.appendingPathComponent(Self.imagesFolderName)
    }

    private var stitchedURL: URL? {
        activeProjectFolder?.appendingPathComponent(Self.stitchedFileName)
    }

    // MARK: ═══════════════════════════════════════════════════════════════
    // MARK: startCapture()

    /// Inicia la sesión de captura espacial.
    /// Dispositivo: arranca ARWorldTrackingConfiguration + ARSessionDelegate.
    /// Simulador: activa flag y usa modo placeholder sin ARKit.
    func startCapture() {
        guard !isCapturing else { return }
        reset()
        isCapturing = true

        let session = buildNewSession()
        currentSession = session

#if targetEnvironment(simulator)
        print("[PanoramaCapture] Simulador — modo placeholder activo")
#else
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = []
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        arSession = ARSession()
        arSession?.delegate = self
        arSession?.run(config, options: [.resetTracking, .removeExistingAnchors])
        print("[PanoramaCapture] ARSession iniciada — id: \(session.id)")
#endif
        NotificationCenter.default.post(name: .panoramaCaptureDidStart, object: session)
    }

    // MARK: stopCapture()

    /// Detiene la captura, actualiza los metadatos de sesión y los persiste.
    func stopCapture() {
        guard isCapturing else { return }
        isCapturing = false

#if !targetEnvironment(simulator)
        arSession?.pause()
        arSession = nil
#endif

        finalizeSession()
        saveSession()
        print("[PanoramaCapture] Captura detenida — \(nodes.count) nodos, \(capturedFrames.count) frames")
        NotificationCenter.default.post(name: .panoramaCaptureDidStop, object: currentSession)
    }

    // MARK: ═══════════════════════════════════════════════════════════════
    // MARK: saveSession()

    /// Persiste en disco: session.json, panoramaNodes.json, capturedFrames.json.
    func saveSession() {
        guard let folder = activeProjectFolder else {
            print("[PanoramaCapture] saveSession: sin proyecto activo")
            return
        }
        saveSession(toFolder: folder)
    }

    func saveSession(toFolder folder: URL) {
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601

        if let session = currentSession,
           let data = try? enc.encode(session) {
            try? data.write(to: folder.appendingPathComponent(Self.sessionFileName), options: .atomic)
        }
        if let data = try? enc.encode(nodes) {
            try? data.write(to: folder.appendingPathComponent(Self.metadataFileName), options: .atomic)
        }
        if let data = try? enc.encode(capturedFrames) {
            try? data.write(to: folder.appendingPathComponent(Self.framesFileName), options: .atomic)
        }
        print("[PanoramaCapture] Sesión guardada → \(folder.lastPathComponent)")
    }

    // MARK: loadSession()

    /// Restaura la sesión completa desde el proyecto activo.
    func loadSession() {
        guard let folder = activeProjectFolder else { return }
        loadSession(fromFolder: folder)
    }

    func loadSession(fromFolder folder: URL) {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: folder.appendingPathComponent(Self.sessionFileName)),
           let session = try? dec.decode(CaptureSession.self, from: data) {
            currentSession = session
        }
        if let data   = try? Data(contentsOf: folder.appendingPathComponent(Self.metadataFileName)),
           let loaded = try? dec.decode([PanoramaNode].self, from: data) {
            nodes        = loaded
            nodeCounter  = (loaded.last?.index ?? -1) + 1
        }
        if let data   = try? Data(contentsOf: folder.appendingPathComponent(Self.framesFileName)),
           let frames = try? dec.decode([CapturedFrame].self, from: data) {
            capturedFrames = frames
        }
        lastCaptureTime = .distantPast
        print("[PanoramaCapture] Sesión restaurada — \(nodes.count) nodos, \(capturedFrames.count) frames")
        NotificationCenter.default.post(name: .panoramaNodesLoaded, object: nodes)
    }

    // MARK: ═══════════════════════════════════════════════════════════════
    // MARK: exportPanoramaTexture()

    /// Cose los frames capturados en una tira horizontal y devuelve un
    /// TextureResource listo para RealityKit (UnlitMaterial / PhysicallyBasedMaterial).
    /// - Returns: TextureResource o nil si no hay frames.
    @discardableResult
    func exportPanoramaTexture() -> TextureResource? {
#if targetEnvironment(simulator)
        return exportSimulatorTexture()
#else
        return stitchAndExport()
#endif
    }

    // MARK: ═══════════════════════════════════════════════════════════════
    // MARK: capturePanorama(from:)  — API pública + ARSessionDelegate interno

    /// Procesa un ARFrame (externo o de la sesión interna).
    /// Crea un CapturedFrame completo + PanoramaNode si se cumplen los umbrales.
    @discardableResult
    func capturePanorama(from frame: ARFrame) -> PanoramaNode? {
        let now = Date()
        guard now.timeIntervalSince(lastCaptureTime) >= minCaptureInterval else { return nil }

        let t        = frame.camera.transform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        if let last = nodes.last,
           simd_distance(position, last.position) < minNodeDistance { return nil }

        guard let imagesFolder = panoramasFolder else { return nil }
        try? fm.createDirectory(at: imagesFolder, withIntermediateDirectories: true)

        let filename = String(format: "panorama_%03d.jpg", nodeCounter + 1)
        let imageURL = imagesFolder.appendingPathComponent(filename)
        if let jpeg = jpegData(from: frame.capturedImage) {
            try? jpeg.write(to: imageURL, options: .atomic)
        }

        // Intrínsecos del sensor
        let intr = frame.camera.intrinsics
        let imgSize = frame.camera.imageResolution

        // Profundidad — disponible solo en dispositivos con LiDAR
        let depthConf: Float?
        let hasDepth: Bool
#if !targetEnvironment(simulator)
        if let depthMap = frame.sceneDepth?.confidenceMap {
            let width  = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(depthMap) {
                let ptr   = base.assumingMemoryBound(to: UInt8.self)
                let count = width * height
                var sum: Int = 0
                for i in 0..<count { sum += Int(ptr[i]) }
                let avg = Float(sum) / Float(count * 2)   // ARConfidenceLevel max = 2
                depthConf = avg
            } else { depthConf = nil }
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            hasDepth = true
        } else {
            depthConf = nil
            hasDepth  = false
        }
#else
        depthConf = nil
        hasDepth  = false
#endif

        let cf = CapturedFrame(
            id:           UUID(),
            index:        nodeCounter,
            timestamp:    now,
            imageURL:     imageURL,
            px:  position.x, py: position.y, pz: position.z,
            t00: t.columns.0.x, t01: t.columns.0.y, t02: t.columns.0.z, t03: t.columns.0.w,
            t10: t.columns.1.x, t11: t.columns.1.y, t12: t.columns.1.z, t13: t.columns.1.w,
            t20: t.columns.2.x, t21: t.columns.2.y, t22: t.columns.2.z, t23: t.columns.2.w,
            t30: t.columns.3.x, t31: t.columns.3.y, t32: t.columns.3.z, t33: t.columns.3.w,
            focalLengthX: intr[0][0], focalLengthY: intr[1][1],
            principalX:   intr[2][0], principalY:   intr[2][1],
            imageWidth:   Int(imgSize.width),
            imageHeight:  Int(imgSize.height),
            depthConfidence: depthConf,
            hasDepthData:    hasDepth
        )
        capturedFrames.append(cf)

        let node = PanoramaNode(
            id:        cf.id,
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

    // MARK: ═══════════════════════════════════════════════════════════════
    // MARK: API de compatibilidad (SceneProjectManager, MultiRoomMergeManager)

    func saveNodes()                        { saveSession() }
    func saveNodes(toFolder f: URL)         { saveSession(toFolder: f) }
    func loadNodes()                        { loadSession() }
    func loadNodes(fromFolder f: URL)       { loadSession(fromFolder: f) }

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
        return (1..<nodes.count).reduce(0) {
            $0 + simd_distance(nodes[$1].position, nodes[$1-1].position)
        }
    }

    // MARK: ═══════════════════════════════════════════════════════════════
    // MARK: capturePanoramaNode(from:projectId:)

    /// Captura un nodo de panorama para un proyecto específico.
    /// Guarda la imagen directamente en `Documents/projects/{projectId}/panoramas/`.
    /// - Returns: PanoramaNode creado, o nil si no se cumplen los umbrales.
    @discardableResult
    func capturePanoramaNode(from frame: ARFrame, projectId: UUID) -> PanoramaNode? {
        let now = Date()
        guard now.timeIntervalSince(lastCaptureTime) >= minCaptureInterval else { return nil }

        let t        = frame.camera.transform
        let position = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        if let last = nodes.last,
           simd_distance(position, last.position) < minNodeDistance { return nil }

        let docs        = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectDir  = docs.appendingPathComponent("projects/\(projectId.uuidString)")
        let imagesDir   = projectDir.appendingPathComponent(Self.imagesFolderName)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let filename = String(format: "panorama_%03d.jpg", nodeCounter + 1)
        let imageURL = imagesDir.appendingPathComponent(filename)
        if let jpeg = jpegData(from: frame.capturedImage) {
            try? jpeg.write(to: imageURL, options: .atomic)
        }

        let intr    = frame.camera.intrinsics
        let imgSize = frame.camera.imageResolution

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

    // MARK: savePanorama(projectId:completion:)

    /// Guarda la sesión completa de panoramas para el proyecto indicado.
    /// Escribe: session.json, panoramaNodes.json, capturedFrames.json.
    func savePanorama(projectId: UUID, completion: ((Bool) -> Void)? = nil) {
        let docs       = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectDir = docs.appendingPathComponent("projects/\(projectId.uuidString)")

        let sessionCopy = currentSession
        let nodesCopy   = nodes
        let framesCopy  = capturedFrames

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { completion?(false); return }
            do {
                try self.fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601

                if let session = sessionCopy {
                    let data = try enc.encode(session)
                    try data.write(to: projectDir.appendingPathComponent(Self.sessionFileName),
                                   options: .atomic)
                }
                let nodesData  = try enc.encode(nodesCopy)
                let framesData = try enc.encode(framesCopy)
                try nodesData.write(to: projectDir.appendingPathComponent(Self.metadataFileName),
                                    options: .atomic)
                try framesData.write(to: projectDir.appendingPathComponent(Self.framesFileName),
                                     options: .atomic)

                print("[PanoramaCapture] savePanorama → projects/\(projectId.uuidString) "
                      + "(\(nodesCopy.count) nodos)")
                DispatchQueue.main.async { completion?(true) }
            } catch {
                print("[PanoramaCapture] savePanorama error: \(error)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    // MARK: loadPanoramaNodes(projectId:completion:)

    /// Carga nodos de panorama desde `Documents/projects/{projectId}/`.
    /// Restaura `nodes`, `capturedFrames` y `currentSession`.
    func loadPanoramaNodes(projectId: UUID, completion: ((Bool) -> Void)? = nil) {
        let docs       = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectDir = docs.appendingPathComponent("projects/\(projectId.uuidString)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion?(false); return }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601

            var loadedNodes:  [PanoramaNode]  = []
            var loadedFrames: [CapturedFrame] = []
            var loadedSession: CaptureSession?

            if let data = try? Data(contentsOf: projectDir.appendingPathComponent(Self.metadataFileName)),
               let parsed = try? dec.decode([PanoramaNode].self, from: data) {
                loadedNodes = parsed
            }
            if let data = try? Data(contentsOf: projectDir.appendingPathComponent(Self.framesFileName)),
               let parsed = try? dec.decode([CapturedFrame].self, from: data) {
                loadedFrames = parsed
            }
            if let data = try? Data(contentsOf: projectDir.appendingPathComponent(Self.sessionFileName)),
               let parsed = try? dec.decode(CaptureSession.self, from: data) {
                loadedSession = parsed
            }

            let success = !loadedNodes.isEmpty

            DispatchQueue.main.async {
                self.nodes          = loadedNodes
                self.capturedFrames = loadedFrames
                self.currentSession = loadedSession
                self.nodeCounter    = (loadedNodes.last?.index ?? -1) + 1
                self.lastCaptureTime = .distantPast
                print("[PanoramaCapture] loadPanoramaNodes ← projects/\(projectId.uuidString) "
                      + "(\(loadedNodes.count) nodos)")
                NotificationCenter.default.post(name: .panoramaNodesLoaded, object: loadedNodes)
                completion?(success)
            }
        }
    }

    // MARK: ═══════════════════════════════════════════════════════════════
    // MARK: Reset

    func reset() {
        nodes          = []
        capturedFrames = []
        currentSession = nil
        nodeCounter    = 0
        lastCaptureTime = .distantPast
    }

    // MARK: ─── Privado — costura ─────────────────────────────────────────

    private func stitchAndExport() -> TextureResource? {
        let images: [UIImage] = nodes.compactMap { n in
            guard fm.fileExists(atPath: n.imageURL.path) else { return nil }
            return UIImage(contentsOfFile: n.imageURL.path)
        }
        guard !images.isEmpty,
              let first = images.first else { return nil }

        let fw = first.size.width
        let fh = first.size.height
        let totalSize = CGSize(width: fw * CGFloat(images.count), height: fh)

        UIGraphicsBeginImageContextWithOptions(totalSize, true, 1.0)
        for (i, img) in images.enumerated() {
            img.draw(in: CGRect(x: fw * CGFloat(i), y: 0, width: fw, height: fh))
        }
        let stitched = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let output = stitched,
              let jpeg   = output.jpegData(compressionQuality: 0.82),
              let outURL = stitchedURL,
              let cgImg  = output.cgImage
        else { return nil }

        try? jpeg.write(to: outURL, options: .atomic)
        print("[PanoramaCapture] Panorama cosido — \(images.count) frames → \(outURL.lastPathComponent)")

        let tex = try? TextureResource.generate(
            from: cgImg,
            withName: "panorama_stitched",
            options: .init(semantic: .color)
        )
        NotificationCenter.default.post(name: .panoramaExportDidFinish, object: outURL)
        return tex
    }

    private func exportSimulatorTexture() -> TextureResource? {
        guard let img   = makeSimulatorPlaceholder(),
              let cgImg = img.cgImage else { return nil }

        if let folder = activeProjectFolder,
           let jpeg = img.jpegData(compressionQuality: 0.82) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if let url = stitchedURL {
                try? jpeg.write(to: url, options: .atomic)
                NotificationCenter.default.post(name: .panoramaExportDidFinish, object: url)
            }
        }
        return try? TextureResource.generate(
            from: cgImg,
            withName: "panorama_placeholder",
            options: .init(semantic: .color)
        )
    }

    private func makeSimulatorPlaceholder() -> UIImage? {
        let size = CGSize(width: 800, height: 400)
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            let colors: [CGColor] = [
                UIColor(red: 0.12, green: 0.18, blue: 0.28, alpha: 1).cgColor,
                UIColor(red: 0.22, green: 0.32, blue: 0.45, alpha: 1).cgColor,
            ]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(grad, start: .zero,
                                              end: CGPoint(x: size.width, y: size.height), options: [])
            let attrs: [NSAttributedString.Key: Any] = [
                .font:            UIFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.70),
            ]
            let text = "Panorama — Simulator Placeholder"
            let ts   = text.size(withAttributes: attrs)
            text.draw(in: CGRect(x: (size.width - ts.width) / 2,
                                 y: (size.height - ts.height) / 2,
                                 width: ts.width, height: ts.height),
                      withAttributes: attrs)
        }
    }

    // MARK: ─── Privado — helpers ─────────────────────────────────────────

    private func buildNewSession() -> CaptureSession {
        let device = UIDevice.current
        return CaptureSession(
            id:          UUID(),
            startDate:   Date(),
            endDate:     nil,
            frameCount:  0,
            pathLength:  0,
            deviceModel: device.model,
            osVersion:   device.systemVersion,
            minX: 0, minY: 0, minZ: 0,
            maxX: 0, maxY: 0, maxZ: 0,
            focalLengthX: 0, focalLengthY: 0,
            principalX: 0, principalY: 0,
            imageWidth: 0, imageHeight: 0
        )
    }

    private func finalizeSession() {
        guard !nodes.isEmpty else { return }
        var s = currentSession ?? buildNewSession()
        s.endDate    = Date()
        s.frameCount = capturedFrames.count
        s.pathLength = totalPathLength

        // Bounding box
        let positions = nodes.map { $0.position }
        s.minX = positions.map { $0.x }.min() ?? 0
        s.minY = positions.map { $0.y }.min() ?? 0
        s.minZ = positions.map { $0.z }.min() ?? 0
        s.maxX = positions.map { $0.x }.max() ?? 0
        s.maxY = positions.map { $0.y }.max() ?? 0
        s.maxZ = positions.map { $0.z }.max() ?? 0

        // Intrínsecos del primer frame
        if let first = capturedFrames.first {
            s.focalLengthX = first.focalLengthX; s.focalLengthY = first.focalLengthY
            s.principalX   = first.principalX;   s.principalY   = first.principalY
            s.imageWidth   = first.imageWidth;    s.imageHeight  = first.imageHeight
        }
        currentSession = s
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer, quality: CGFloat = 0.75) -> Data? {
        let ci  = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: ARSessionDelegate — solo dispositivo real

#if !targetEnvironment(simulator)
extension PanoramaCaptureManager: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        capturePanorama(from: frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[PanoramaCapture] Error ARSession: \(error.localizedDescription)")
        isCapturing = false
        NotificationCenter.default.post(name: .panoramaCaptureDidStop, object: nil)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("[PanoramaCapture] ARSession interrumpida")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("[PanoramaCapture] ARSession reanudada")
    }
}
#endif

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Notification.Name

extension Notification.Name {
    static let panoramaCaptureDidStart  = Notification.Name("mi_render_panoramaCaptureDidStart")
    static let panoramaCaptureDidStop   = Notification.Name("mi_render_panoramaCaptureDidStop")
    static let panoramaNodeAdded        = Notification.Name("mi_render_panoramaNodeAdded")
    static let panoramaNodesLoaded      = Notification.Name("mi_render_panoramaNodesLoaded")
    static let panoramaExportDidFinish  = Notification.Name("mi_render_panoramaExportDidFinish")
}
