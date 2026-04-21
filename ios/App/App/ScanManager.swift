// ScanManager.swift
// Motor base del escaneo universal.
// Punto de entrada único para la sesión ARKit.
// Activa: sceneReconstruction(.mesh), sceneDepth, clasificación, detección de planos.
// Propaga ARMeshAnchor a MeshManager en tiempo real.
// Soporta: pause/resume sin resetTracking, ARCoachingOverlay, occlusion, WorldMap restore.

import ARKit
import RealityKit
import RoomPlan
import ModelIO
import MetalKit
import UIKit
import simd

class ScanManager: NSObject {

    static let shared = ScanManager()

    weak var session: ARSession?
    weak var arView:  ARView?

    /// Modo de escaneo activo (habitación LiDAR u objeto fotogrametría).
    private(set) var currentScanMode: ScanMode = .roomScan

    /// Última configuración activa — permite resumeScan sin resetTracking.
    private var lastConfig: ARWorldTrackingConfiguration?

    /// Timestamp del último frame procesado — throttle a 1 fps para onFrameCaptured.
    private var lastFrameTimestamp: TimeInterval = 0

    /// Mapa UUID→AnchorEntity para actualizar entidades de mesh sin recrearlas.
    private(set) var meshEntities: [UUID: AnchorEntity] = [:]

    /// Throttle: última vez que se reconstruyó el wireframe de cada anchor.
    private var meshLastBuilt: [UUID: TimeInterval] = [:]

    /// Contador de actualizaciones por anchor.
    private var meshUpdateCounts: [UUID: Int] = [:]

    /// Feedback háptico para sectores recién escaneados.
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

    /// Entidades de superficies CapturedRoom (un solo color, reemplazadas en cada update).
    private var surfaceEntities: [UUID: AnchorEntity] = [:]

    /// IDs de superficies conocidas (para detectar nuevas y disparar pulso+haptic).
    private var knownSurfaceIDs: Set<UUID> = []

    /// Haptic más suave para pulsos de superficie.
    private let hapticSoft = UIImpactFeedbackGenerator(style: .soft)

    /// Contador de mesh anchors previo para detectar crecimiento.
    private var prevMeshAnchorCount: Int = 0

    /// Callback adicional para que LiDARPlugin reciba los anchors directamente.
    var onMeshAnchorsUpdated: (([ARMeshAnchor]) -> Void)?

    /// Callback de frame capturado — throttled a 1 fps. Útil para thumbnails.
    var onFrameCaptured: ((ARFrame) -> Void)?

    /// Callback de frame sin throttle — para point cloud en tiempo real.
    var onEveryFrame: ((ARFrame) -> Void)?

    // MARK: - Escaneo completo (modo profesional)
    // Activa sceneReconstruction + sceneDepth + clasificación + planos + occlusion.

    func startFullScan(arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()

        // 1. sceneReconstruction — malla navegable real
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // 2. frameSemantics — depth + segmentación de personas
        var semantics: ARConfiguration.FrameSemantics = []
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            semantics.insert(.sceneDepth)
            semantics.insert(.smoothedSceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            semantics.insert(.personSegmentationWithDepth)
        }
        if !semantics.isEmpty { config.frameSemantics = semantics }

        config.planeDetection       = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        lastConfig = config
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // 3. sceneUnderstanding — occlusion, physics, lighting
        arView.environment.sceneUnderstanding.options = [.occlusion, .physics, .receivesLighting]

        // 4. RoomPlanManager: el callback de onRoomUpdated lo gestiona ARViewContainer
        //    (que llama renderCapturedRoomSurfaces). No sobrescribir aquí.
    }

    // MARK: - Modo rápido (solo planos, sin mesh pesado)

    func startFastScan(arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.planeDetection       = [.horizontal, .vertical]
        config.environmentTexturing = .none

        lastConfig = config
        arView.session.run(config)
    }

    // MARK: - Modo depth map únicamente

    func startDepthOnlyScan(arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }

        lastConfig = config
        arView.session.run(config)
    }

    // MARK: - Pause / Resume sin resetTracking

    func pauseScan() {
        session?.pause()
    }

    func resumeScan() {
        guard let arView = arView,
              let config = lastConfig else { return }
        arView.session.run(config, options: [])
    }

    // MARK: - Parar sesión y clasificar mesh

    func stopScan() {
        session?.pause()
        let anchors = MeshManager.shared.meshAnchors
        if !anchors.isEmpty {
            DispatchQueue.global(qos: .utility).async {
                SemanticMeshClassifier.shared.classifyAndSave(anchors: anchors)
            }
        }
    }

    // MARK: - Restaurar desde ARWorldMap (sin resetTracking)

    func restoreFromWorldMap(_ worldMap: ARWorldMap, arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.initialWorldMap = worldMap
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.planeDetection = [.horizontal, .vertical]

        lastConfig = config
        arView.session.run(config, options: [])   // sin resetTracking para preservar anchors
    }

    // MARK: - ARCoachingOverlayView

    func addCoachingOverlay(to view: ARView) {
        #if !targetEnvironment(simulator)
        let overlay = ARCoachingOverlayView()
        overlay.session = view.session
        overlay.goal    = .anyPlane
        overlay.activatesAutomatically = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        #endif
    }

    // MARK: - Object Capture (iOS 17+)

    func startObjectCapture() {
        currentScanMode = .objectScan
        ObjectCaptureManager.shared.startCapture()
    }

    func switchToRoomScan(arView: ARView) {
        ObjectCaptureManager.shared.cancelCapture()
        currentScanMode = .roomScan
        startFullScan(arView: arView)
    }

    // MARK: - Reiniciar sesión limpiando anchors

    func resetScan(arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        lastConfig = config
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        MeshManager.shared.clearAll(session: arView.session)
    }

    // MARK: - Fallback para dispositivos sin LiDAR

    func startFallbackScan(arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]

        lastConfig = config
        arView.session.run(config)
    }

    // MARK: - Fusionar ARMeshAnchor → MDLAsset (para exportación)

    func mergedMDLAsset(from anchors: [ARMeshAnchor]) -> MDLAsset {
        let asset = MDLAsset()
        guard let device = MTLCreateSystemDefaultDevice() else { return asset }
        let allocator = MTKMeshBufferAllocator(device: device)

        for anchor in anchors {
            let geo       = anchor.geometry
            let transform = anchor.transform
            let vBuf      = geo.vertices
            let fBuf      = geo.faces

            let vPtr    = vBuf.buffer.contents().advanced(by: vBuf.offset).assumingMemoryBound(to: Float.self)
            let vStride = vBuf.stride / MemoryLayout<Float>.stride
            let iPtr    = fBuf.buffer.contents().assumingMemoryBound(to: UInt32.self)
            let iCount  = fBuf.indexCountPerPrimitive

            var worldVerts = [Float]()
            worldVerts.reserveCapacity(vBuf.count * 3)
            for i in 0..<vBuf.count {
                let local = SIMD3<Float>(vPtr[i*vStride], vPtr[i*vStride+1], vPtr[i*vStride+2])
                let world = transform * SIMD4<Float>(local, 1)
                worldVerts.append(world.x); worldVerts.append(world.y); worldVerts.append(world.z)
            }

            var indices = [UInt32]()
            indices.reserveCapacity(fBuf.count * iCount)
            for f in 0..<fBuf.count { for k in 0..<iCount { indices.append(iPtr[f*iCount+k]) } }

            guard !worldVerts.isEmpty, !indices.isEmpty else { continue }

            let vData   = Data(bytes: worldVerts, count: worldVerts.count * MemoryLayout<Float>.size)
            let iData   = Data(bytes: indices,    count: indices.count    * MemoryLayout<UInt32>.size)
            let vBufMDL = allocator.newBuffer(with: vData, type: .vertex)
            let iBufMDL = allocator.newBuffer(with: iData, type: .index)

            let desc = MDLVertexDescriptor()
            desc.attributes[0] = MDLVertexAttribute(
                name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
            desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

            let sub  = MDLSubmesh(indexBuffer: iBufMDL, indexCount: indices.count,
                                  indexType: .uInt32, geometryType: .triangles, material: nil)
            let mesh = MDLMesh(vertexBuffer: vBufMDL,
                               vertexCount: vBuf.count,
                               descriptor: desc,
                               submeshes: [sub])
            asset.add(mesh)
        }
        return asset
    }
}

// MARK: - ARSessionDelegate — propaga ARMeshAnchor + renderiza en ARView

extension ScanManager: ARSessionDelegate {

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
        meshAnchors.forEach {
            meshUpdateCounts[$0.identifier] = 1
            MeshManager.shared.update(anchor: $0)
            renderMesh($0)
        }
        // Vibración al detectar nuevo sector de geometría
        let newCount = MeshManager.shared.meshAnchors.count
        if newCount > prevMeshAnchorCount {
            prevMeshAnchorCount = newCount
            DispatchQueue.main.async {
                self.hapticLight.prepare()
                self.hapticLight.impactOccurred(intensity: 0.6)
            }
        }
        onMeshAnchorsUpdated?(MeshManager.shared.meshAnchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
        meshAnchors.forEach {
            meshUpdateCounts[$0.identifier, default: 1] += 1
            MeshManager.shared.update(anchor: $0)
            renderMesh($0)
        }
        // Vibración suave cada vez que la geometría existente se densifica (cada 5 updates)
        let totalUpdates = meshUpdateCounts.values.reduce(0, +)
        if totalUpdates % 5 == 0 {
            DispatchQueue.main.async {
                self.hapticSoft.prepare()
                self.hapticSoft.impactOccurred(intensity: 0.3)
            }
        }
        onMeshAnchorsUpdated?(MeshManager.shared.meshAnchors)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
        meshAnchors.forEach {
            MeshManager.shared.remove(anchor: $0)
            removeMeshEntity(for: $0)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onEveryFrame?(frame)
        // Throttle: un frame por segundo para thumbnail/preview
        let now = frame.timestamp
        guard now - lastFrameTimestamp >= 1.0 else { return }
        lastFrameTimestamp = now
        onFrameCaptured?(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("[ScanManager] session error: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("[ScanManager] session interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("[ScanManager] session resumed")
    }
}

// MARK: - Parámetros visuales del mesh (ajuste fino)
// ┌──────────────────────────────────────────────────────────────────────────┐
// │  MESH STYLE  —  Pide cambiar cualquiera de estos valores para afinar    │
// │  fillOpacity : opacidad del relleno de triángulos  0.0–1.0              │
// │  edgeOpacity : opacidad de las aristas blancas     0.0–1.0              │
// │  edgeWidth   : grosor de arista en metros                               │
// │  fill RGB    : color del relleno (0.0–1.0 por canal)                    │
// └──────────────────────────────────────────────────────────────────────────┘
private enum MeshStyle {
    static let fillOpacity: Float = 0.12          // relleno 12% — casi invisible
    static let edgeOpacity: Float = 0.42          // aristas 42%
    static let edgeWidth:   Float = 0.0014        // 1.4 mm
    static let fillR: Float = 0.88, fillG: Float = 0.96, fillB: Float = 1.00
    static let edgeR: Float = 1.00, edgeG: Float = 1.00, edgeB: Float = 1.00
}

// MARK: - Renderizado de malla en tiempo real

extension ScanManager {

    /// Triángulos translúcidos (relleno) + aristas blancas (wireframe) sobre el ARView.
    /// AnchorEntity(anchor:) → RealityKit sigue el tracking automáticamente.
    func renderMesh(_ anchor: ARMeshAnchor) {
        guard let arView = arView else { return }
        let anchorId = anchor.identifier
        let now      = Date().timeIntervalSinceReferenceDate

        if meshEntities[anchorId] != nil,
           let last = meshLastBuilt[anchorId], now - last < 2.5 { return }
        meshLastBuilt[anchorId] = now

        DispatchQueue.global(qos: .userInitiated).async {
            let fillDesc = Self.buildDescriptor(from: anchor)
            let edgeDesc = Self.buildWireframeEdgeDescriptor(from: anchor)

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let arView = self.arView else { return }

                var fillMat = UnlitMaterial()
                fillMat.color = .init(tint: UIColor(
                    red: CGFloat(MeshStyle.fillR), green: CGFloat(MeshStyle.fillG),
                    blue: CGFloat(MeshStyle.fillB), alpha: 1.0))
                fillMat.blending = .transparent(opacity: .init(floatLiteral: MeshStyle.fillOpacity))

                var edgeMat = UnlitMaterial()
                edgeMat.color = .init(tint: UIColor(
                    red: CGFloat(MeshStyle.edgeR), green: CGFloat(MeshStyle.edgeG),
                    blue: CGFloat(MeshStyle.edgeB), alpha: 1.0))
                edgeMat.blending = .transparent(opacity: .init(floatLiteral: MeshStyle.edgeOpacity))

                let fillModel = fillDesc
                    .flatMap { try? MeshResource.generate(from: [$0]) }
                    .map    { ModelEntity(mesh: $0, materials: [fillMat]) }
                let edgeModel = edgeDesc
                    .flatMap { try? MeshResource.generate(from: [$0]) }
                    .map    { ModelEntity(mesh: $0, materials: [edgeMat]) }

                if let existing = self.meshEntities[anchorId] {
                    existing.children.forEach { $0.removeFromParent() }
                    fillModel.map { existing.addChild($0) }
                    edgeModel.map { existing.addChild($0) }
                } else {
                    let ae = AnchorEntity(anchor: anchor)
                    ae.name = "mesh_\(anchorId.uuidString.prefix(8))"
                    fillModel.map { ae.addChild($0) }
                    edgeModel.map { ae.addChild($0) }
                    arView.scene.addAnchor(ae)
                    self.meshEntities[anchorId] = ae
                }
            }
        }
    }

    /// Construye ribbons delgados (2 triángulos por arista) para visualizar el wireframe.
    /// Cada triángulo (A,B,C) genera 3 aristas; cada arista → quad de 2mm de ancho
    /// alineado con la normal de cara → visible desde el ángulo de la cámara.
    static func buildWireframeEdgeDescriptor(from anchor: ARMeshAnchor) -> MeshDescriptor? {
        let geo = anchor.geometry
        guard geo.vertices.count > 0, geo.faces.count > 0 else { return nil }

        let vPtr    = geo.vertices.buffer.contents()
            .advanced(by: geo.vertices.offset)
            .assumingMemoryBound(to: Float.self)
        let vStride = geo.vertices.stride / MemoryLayout<Float>.stride

        func vert(_ i: UInt32) -> SIMD3<Float> {
            let n = Int(i)
            return SIMD3(vPtr[n*vStride], vPtr[n*vStride+1], vPtr[n*vStride+2])
        }

        let iCount   = geo.faces.indexCountPerPrimitive
        let iPtr     = geo.faces.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)
        let halfW:   Float = 0.0014   // 1.4mm → línea de ~2.8mm
        let maxEdge: Float = 0.35     // descarta aristas > 35cm

        // Recolectar triángulos originales y subdividirlos 1 nivel (→ 4x más pequeños)
        typealias Tri = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
        var triangles = [Tri]()
        triangles.reserveCapacity(geo.faces.count * 4)

        for f in 0..<geo.faces.count {
            let A = vert(iPtr[f*iCount]), B = vert(iPtr[f*iCount+1]), C = vert(iPtr[f*iCount+2])
            guard simd_length(B-A) < maxEdge,
                  simd_length(C-B) < maxEdge,
                  simd_length(A-C) < maxEdge else { continue }
            // Subdivisión midpoint: 1 triángulo → 4
            let mAB = (A+B)*0.5, mBC = (B+C)*0.5, mCA = (C+A)*0.5
            triangles.append((A, mAB, mCA))
            triangles.append((mAB, B, mBC))
            triangles.append((mCA, mBC, C))
            triangles.append((mAB, mBC, mCA))
        }

        var positions = [SIMD3<Float>]()
        var indices   = [UInt32]()
        positions.reserveCapacity(triangles.count * 12)
        indices.reserveCapacity(triangles.count * 18)

        for (A, B, C) in triangles {
            let e1  = B - A, e2 = C - A
            let len = simd_length(simd_cross(e1, e2))
            guard len > 1e-8 else { continue }
            let N = simd_normalize(simd_cross(e1, e2))

            for (P0, P1) in [(A,B), (B,C), (C,A)] {
                let dir  = P1 - P0
                let dlen = simd_length(dir)
                guard dlen > 1e-6 else { continue }
                let perp = simd_normalize(simd_cross(dir/dlen, N)) * halfW

                let base = UInt32(positions.count)
                positions.append(P0+perp); positions.append(P0-perp)
                positions.append(P1+perp); positions.append(P1-perp)
                indices.append(contentsOf: [base, base+1, base+2,
                                            base+1, base+3, base+2])
            }
        }
        guard !positions.isEmpty else { return nil }

        var desc = MeshDescriptor()
        desc.name       = "wedge_\(anchor.identifier.uuidString.prefix(8))"
        desc.positions  = .init(positions)
        desc.primitives = .triangles(indices)
        return desc
    }

    /// Infiere la clasificación ARMeshClassification dominante de un anchor.
    private func dominantClassification(of anchor: ARMeshAnchor) -> ARMeshClassification {
        let geo = anchor.geometry
        guard geo.faces.count > 0 else { return .none }
        var counts: [ARMeshClassification: Int] = [:]
        for f in 0..<min(geo.faces.count, 200) {   // muestreo de hasta 200 caras
            counts[geo.faceClassification(at: f), default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .none
    }

    /// Elimina la AnchorEntity de un anchor del diccionario y de la escena.
    func removeMeshEntity(for anchor: ARMeshAnchor) {
        let id = anchor.identifier
        DispatchQueue.main.async {
            self.meshEntities[id]?.removeFromParent()
            self.meshEntities.removeValue(forKey: id)
            self.meshUpdateCounts.removeValue(forKey: id)
        }
    }

    /// Limpia todas las entidades de mesh de la escena.
    func clearMeshEntities() {
        DispatchQueue.main.async {
            self.meshEntities.values.forEach { $0.removeFromParent() }
            self.meshEntities.removeAll()
            self.meshUpdateCounts.removeAll()
            self.meshLastBuilt.removeAll()
        }
    }

    // MARK: - Superficies CapturedRoom (solo haptics — sin cajas de color)

    /// Solo vibración cuando se detectan nuevas superficies.
    /// El mesh visual lo gestiona renderMesh() con triangulos translúcidos + aristas blancas.
    @available(iOS 16.0, *)
    func renderCapturedRoomSurfaces(_ room: CapturedRoom, in arView: ARView) {
        var allIDs = Set<UUID>()
        allIDs.formUnion(room.walls.map   { $0.identifier })
        allIDs.formUnion(room.doors.map   { $0.identifier })
        allIDs.formUnion(room.windows.map { $0.identifier })
        allIDs.formUnion(room.objects.map { $0.identifier })
        if #available(iOS 17.0, *) { allIDs.formUnion(room.floors.map { $0.identifier }) }

        let hasNew = !allIDs.subtracting(knownSurfaceIDs).isEmpty
        knownSurfaceIDs = allIDs

        // Limpiar overlays semánticos previos si quedaron de alguna sesión anterior
        if !surfaceEntities.isEmpty {
            surfaceEntities.values.forEach { $0.removeFromParent() }
            surfaceEntities.removeAll()
        }

        if hasNew {
            hapticSoft.impactOccurred(intensity: 0.45)
        }
    }

    func clearSurfaceEntities() {
        DispatchQueue.main.async {
            self.surfaceEntities.values.forEach { $0.removeFromParent() }
            self.surfaceEntities.removeAll()
        }
    }

    private func surfaceMaterial(r: Float, g: Float, b: Float, opacity: Float) -> UnlitMaterial {
        var mat = UnlitMaterial()
        mat.color    = .init(tint: UIColor(red: CGFloat(r), green: CGFloat(g),
                                          blue: CGFloat(b), alpha: 1.0))
        mat.blending = .transparent(opacity: .init(floatLiteral: opacity))
        return mat
    }

    /// Construye un MeshDescriptor desde la geometría del ARMeshAnchor.
    static func buildDescriptor(from anchor: ARMeshAnchor) -> MeshDescriptor? {
        let geo = anchor.geometry

        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(geo.vertices.count)
        let vPtr = geo.vertices.buffer.contents()
            .advanced(by: geo.vertices.offset)
            .assumingMemoryBound(to: Float.self)
        let vStride = geo.vertices.stride / MemoryLayout<Float>.stride
        for i in 0..<geo.vertices.count {
            positions.append(SIMD3<Float>(
                vPtr[i * vStride],
                vPtr[i * vStride + 1],
                vPtr[i * vStride + 2]
            ))
        }

        let faceCount = geo.faces.count
        let iCount    = geo.faces.indexCountPerPrimitive
        var indices   = [UInt32]()
        indices.reserveCapacity(faceCount * iCount)
        let iPtr = geo.faces.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)
        for f in 0..<faceCount {
            for k in 0..<iCount {
                indices.append(iPtr[f * iCount + k])
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else { return nil }

        var desc = MeshDescriptor()
        desc.name       = anchor.identifier.uuidString
        desc.positions  = .init(positions)
        desc.primitives = .triangles(indices)
        return desc
    }

    /// Genera MeshResource en tiempo real desde ARMeshAnchor.
    static func buildMeshResource(from anchor: ARMeshAnchor) -> MeshResource? {
        guard let desc = buildDescriptor(from: anchor) else { return nil }
        return try? MeshResource.generate(from: [desc])
    }
}
