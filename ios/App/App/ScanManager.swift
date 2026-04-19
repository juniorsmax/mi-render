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
            MeshManager.shared.update(anchor: $0)
            renderMesh($0)
        }
        onMeshAnchorsUpdated?(MeshManager.shared.meshAnchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
        meshAnchors.forEach {
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
    func renderMesh(_ anchor: ARMeshAnchor) {
        guard let arView = arView else { return }

        let classification = dominantClassification(of: anchor)
        let anchorId       = anchor.identifier

        // Construir el descriptor (solo datos, sin Metal) en background
        DispatchQueue.global(qos: .userInitiated).async {
            guard let desc = Self.buildDescriptor(from: anchor) else { return }

            // MeshResource.generate y toda la escena RealityKit → MAIN THREAD
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let arView = self.arView else { return }

                guard let meshResource = try? MeshResource.generate(from: [desc]) else {
                    print("[ScanManager] renderMesh: MeshResource.generate falló para \(anchorId)")
                    return
                }

                let material    = MeshRenderer.shared.material(for: classification)
                let modelEntity = ModelEntity(mesh: meshResource, materials: [material])

                if let existing = self.meshEntities[anchorId] {
                    existing.children.forEach { $0.removeFromParent() }
                    existing.addChild(modelEntity)
                } else {
                    // AnchorEntity(world:) con la transform actual del anchor —
                    // más compatible que AnchorEntity(anchor:) en sesiones compartidas
                    let anchorEntity = AnchorEntity(world: anchor.transform)
                    anchorEntity.name = "mesh_\(anchorId.uuidString.prefix(8))"
                    anchorEntity.addChild(modelEntity)
                    arView.scene.addAnchor(anchorEntity)
                    self.meshEntities[anchorId] = anchorEntity
                }
            }
        }
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
        DispatchQueue.main.async {
            self.meshEntities[anchor.identifier]?.removeFromParent()
            self.meshEntities.removeValue(forKey: anchor.identifier)
        }
    }

    /// Limpia todas las entidades de mesh de la escena.
    func clearMeshEntities() {
        DispatchQueue.main.async {
            self.meshEntities.values.forEach { $0.removeFromParent() }
            self.meshEntities.removeAll()
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
