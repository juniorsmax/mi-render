// ScanManager.swift
// Motor base del escaneo universal.
// Punto de entrada único para la sesión ARKit.
// Activa: sceneReconstruction(.mesh), sceneDepth, clasificación, detección de planos.
// Propaga ARMeshAnchor a MeshManager en tiempo real.
// Soporta: pause/resume sin resetTracking, ARCoachingOverlay, occlusion, WorldMap restore.

import ARKit
import RealityKit
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

    /// Contador de actualizaciones por anchor — cuantas más, más escaneada la zona.
    private var meshUpdateCounts: [UUID: Int] = [:]

    /// Feedback háptico para sectores recién escaneados.
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

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

        // 4. Conectar RoomPlanManager si está disponible (iOS 16+)
        if #available(iOS 16.0, *) {
            RoomPlanManager.shared.onRoomUpdated = { [weak self] room in
                guard let self = self, let arView = self.arView else { return }
                let anchors = MeshManager.shared.meshAnchors
                anchors.forEach { self.renderMesh($0) }
                self.onMeshAnchorsUpdated?(anchors)
            }
        }
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
        // Vibración háptica: nuevo sector detectado
        DispatchQueue.main.async { self.hapticLight.impactOccurred() }
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

// MARK: - Renderizado de malla en tiempo real

extension ScanManager {

    /// Construye un ModelEntity desde ARMeshAnchor y lo añade/actualiza en ARView.scene.
    /// MeshDescriptor se construye en background; MeshResource.generate y addAnchor
    /// se ejecutan en main thread (requieren contexto Metal del hilo principal).
    /// Renderiza el mesh LiDAR como wireframe blanco.
    /// Cada arista se convierte en un ribbon delgado (2 triángulos) usando .triangles —
    /// compatible con todas las versiones de RealityKit (no usa .lines que no existe).
    func renderMesh(_ anchor: ARMeshAnchor) {
        guard let arView = arView else { return }
        let anchorId = anchor.identifier

        DispatchQueue.global(qos: .userInitiated).async {
            guard let desc = Self.buildWireframeEdgeDescriptor(from: anchor) else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let arView = self.arView else { return }
                guard let mesh = try? MeshResource.generate(from: [desc]) else { return }

                var mat = UnlitMaterial()
                mat.color    = .init(tint: UIColor(white: 1.0, alpha: 1.0))
                mat.blending = .transparent(opacity: .init(floatLiteral: 0.60))
                let model = ModelEntity(mesh: mesh, materials: [mat])

                if let existing = self.meshEntities[anchorId] {
                    existing.children.forEach { $0.removeFromParent() }
                    existing.addChild(model)
                } else {
                    let anchorEntity = AnchorEntity(world: anchor.transform)
                    anchorEntity.name = "wire_\(anchorId.uuidString.prefix(8))"
                    anchorEntity.addChild(model)
                    arView.scene.addAnchor(anchorEntity)
                    self.meshEntities[anchorId] = anchorEntity
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

        let iCount = geo.faces.indexCountPerPrimitive
        let iPtr   = geo.faces.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)
        let halfW:  Float = 0.0018   // 1.8mm mitad de ancho → línea de ~3.6mm

        var positions = [SIMD3<Float>]()
        var indices   = [UInt32]()
        positions.reserveCapacity(geo.faces.count * 12)
        indices.reserveCapacity(geo.faces.count * 18)

        for f in 0..<geo.faces.count {
            let ia = iPtr[f*iCount], ib = iPtr[f*iCount+1], ic = iPtr[f*iCount+2]
            let A = vert(ia), B = vert(ib), C = vert(ic)

            // Normal de cara (cross product de dos aristas)
            let e1  = B - A, e2 = C - A
            let len = simd_length(simd_cross(e1, e2))
            guard len > 1e-8 else { continue }
            let N = simd_normalize(simd_cross(e1, e2))

            // Genera ribbon para cada arista
            for (P0, P1) in [(A,B), (B,C), (C,A)] {
                let dir   = P1 - P0
                let dlen  = simd_length(dir)
                guard dlen > 1e-6 else { continue }
                let dNorm = dir / dlen
                let perp  = simd_normalize(simd_cross(dNorm, N)) * halfW

                let base = UInt32(positions.count)
                positions.append(P0 + perp); positions.append(P0 - perp)
                positions.append(P1 + perp); positions.append(P1 - perp)
                // Dos triángulos que forman el quad
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
        }
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
