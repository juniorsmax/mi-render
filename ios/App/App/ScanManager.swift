// ScanManager.swift
// Motor base del escaneo universal.
// Punto de entrada único para la sesión ARKit.
// Activa: sceneReconstruction(.mesh), sceneDepth, clasificación, detección de planos.
// Propaga ARMeshAnchor a MeshManager en tiempo real.

import ARKit
import RealityKit

class ScanManager: NSObject {

    static let shared = ScanManager()

    weak var session: ARSession?
    weak var arView: ARView?

    // Callback adicional para que LiDARPlugin reciba los anchors directamente
    var onMeshAnchorsUpdated: (([ARMeshAnchor]) -> Void)?

    // MARK: - Escaneo completo (modo profesional)
    // Activa sceneReconstruction + sceneDepth + clasificación + planos.

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

        // 2. frameSemantics — depth + semántica de escena
        var semantics: ARConfiguration.FrameSemantics = []
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            semantics.insert(.sceneDepth)
            semantics.insert(.smoothedSceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            semantics.insert(.personSegmentationWithDepth)
        }
        if !semantics.isEmpty { config.frameSemantics = semantics }

        config.planeDetection      = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Modo rápido (solo planos, sin mesh pesado)

    func startFastScan(arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.planeDetection       = [.horizontal, .vertical]
        config.environmentTexturing = .none
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
        arView.session.run(config)
    }

    // MARK: - Parar sesión

    func stopScan() {
        session?.pause()
    }

    // MARK: - Reiniciar sesión limpiando anchors

    func resetScan(arView: ARView) {
        self.arView  = arView
        self.session = arView.session
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
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
        arView.session.run(config)
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
        meshAnchors.forEach { MeshManager.shared.remove(anchor: $0) }
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
    func renderMesh(_ anchor: ARMeshAnchor) {
        guard let arView = arView else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let meshResource = Self.buildMeshResource(from: anchor) else { return }

            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.6))
            material.roughness = .init(floatLiteral: 0.8)
            material.metallic  = .init(floatLiteral: 0.0)

            let modelEntity = ModelEntity(mesh: meshResource, materials: [material])

            DispatchQueue.main.async {
                // Buscar AnchorEntity existente para este anchor o crear uno nuevo
                let anchorId = anchor.identifier.uuidString
                if let existing = arView.scene.anchors.first(
                    where: { $0.name == anchorId }) as? AnchorEntity {
                    existing.children.forEach { $0.removeFromParent() }
                    existing.addChild(modelEntity)
                } else {
                    let anchorEntity = AnchorEntity(anchor: anchor)
                    anchorEntity.name = anchorId
                    anchorEntity.addChild(modelEntity)
                    arView.scene.addAnchor(anchorEntity)
                }
            }
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

        var desc = MeshDescriptor(name: anchor.identifier.uuidString)
        desc.positions  = MeshBuffer(positions)
        desc.primitives = .triangles(indices)
        return desc
    }

    /// Construye un MeshResource desde la geometría del ARMeshAnchor.
    private static func buildMeshResource(from anchor: ARMeshAnchor) -> MeshResource? {
        let geo = anchor.geometry

        // Vértices
        let vertexCount = geo.vertices.count
        var positions = [SIMD3<Float>]()
        positions.reserveCapacity(vertexCount)
        let vPtr = geo.vertices.buffer.contents()
            .advanced(by: geo.vertices.offset)
            .assumingMemoryBound(to: Float.self)
        let vStride = geo.vertices.stride / MemoryLayout<Float>.stride
        for i in 0..<vertexCount {
            positions.append(SIMD3<Float>(
                vPtr[i * vStride],
                vPtr[i * vStride + 1],
                vPtr[i * vStride + 2]
            ))
        }

        // Índices de caras
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

        var descriptor = MeshDescriptor(name: anchor.identifier.uuidString)
        descriptor.positions = MeshBuffer(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
