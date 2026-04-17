// ARViewContainer.swift
// Contenedor SwiftUI del ARView de RealityKit.
// Pipeline de visualización en tiempo real:
//   - Mesh semántico desde ARMeshAnchor (coloreado por clasificación)
//   - Overlay del SceneGraph en debug
//   - Point cloud desde sceneDepth si LiDAR disponible

import SwiftUI
import ARKit
import RealityKit
import Combine

struct ARViewContainer: UIViewRepresentable {

    var onTap:           ((CGPoint) -> Void)?
    var showSceneGraph:  Bool = false
    var showPointCloud:  Bool = false

    func makeUIView(context: Context) -> ARView {

        let arView = ARView(frame: .zero)

        // Scene understanding — oclusión + física + mesh clasificado
        arView.environment.sceneUnderstanding.options = [
            .occlusion,
            .physics,
            .receivesLighting,
            .collision
        ]

        // Debug: wireframe + estadísticas si SceneGraph overlay activo
        #if DEBUG
        if showSceneGraph {
            arView.debugOptions = [.showSceneUnderstanding, .showAnchorGeometry]
        }
        #endif

        // Gesto tap
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // Iniciar escaneo
        ScanManager.shared.startFullScan(arView: arView)

        // Conectar delegate de sesión ARKit para recibir mesh updates
        context.coordinator.arView = arView
        context.coordinator.startObservingMesh()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Actualizar opciones debug si cambia showSceneGraph
        #if DEBUG
        if showSceneGraph {
            uiView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            uiView.debugOptions.remove(.showSceneUnderstanding)
        }
        #endif
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, showPointCloud: showPointCloud)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSessionDelegate {

        var onTap: ((CGPoint) -> Void)?
        var showPointCloud: Bool

        weak var arView: ARView?

        /// Anclas vivas: anchor.identifier → AnchorEntity en escena
        private var meshAnchors: [UUID: AnchorEntity] = [:]

        /// Entidad raíz del point cloud
        private var pointCloudAnchor: AnchorEntity?

        init(onTap: ((CGPoint) -> Void)?, showPointCloud: Bool) {
            self.onTap        = onTap
            self.showPointCloud = showPointCloud
        }

        // MARK: - Observar updates de mesh

        func startObservingMesh() {
            arView?.session.delegate = self
        }

        // MARK: - ARSessionDelegate — mesh anchors

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            processAnchors(anchors, session: session)
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            processAnchors(anchors, session: session)
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for anchor in anchors {
                    if let entity = self.meshAnchors.removeValue(forKey: anchor.identifier) {
                        entity.removeFromParent()
                    }
                }
            }
        }

        // MARK: - ARSessionDelegate — frame (point cloud)

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard showPointCloud else { return }
            updatePointCloud(frame: frame)
        }

        // MARK: - Procesar ARMeshAnchor

        private func processAnchors(_ anchors: [ARAnchor], session: ARSession) {
            let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
            guard !meshes.isEmpty else { return }

            // Actualizar MeshManager
            meshes.forEach { MeshManager.shared.addAnchor($0) }

            // Reconstruir SceneGraph con nuevos anchors
            SceneGraphManager.shared.buildGraph(from: MeshManager.shared.meshAnchors)

            // Renderizar en pantalla
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let arView = self.arView else { return }
                for meshAnchor in meshes {
                    self.renderMeshAnchor(meshAnchor, in: arView)
                }
            }
        }

        // MARK: - Renderizar un ARMeshAnchor como ModelEntity

        private func renderMeshAnchor(_ anchor: ARMeshAnchor, in arView: ARView) {
            guard let meshResource = try? MeshResource.generate(from: anchor.geometry) else {
                return
            }

            // Material coloreado por clasificación semántica de la primera cara
            let classification: ARMeshClassification = anchor.geometry.faces.count > 0
                ? anchor.geometry.faceClassification(at: 0)
                : .none

            let material = MeshRenderer.shared.material(for: classification)
            let modelEntity = ModelEntity(mesh: meshResource, materials: [material])

            if let existing = meshAnchors[anchor.identifier] {
                // Actualizar entidad existente
                existing.children.forEach { $0.removeFromParent() }
                existing.addChild(modelEntity)
                existing.transform = Transform(matrix: anchor.transform)
            } else {
                // Crear nueva AnchorEntity anclada al transform del anchor
                let anchorEntity = AnchorEntity(world: anchor.transform)
                anchorEntity.name = "mesh_\(anchor.identifier.uuidString.prefix(8))"
                anchorEntity.addChild(modelEntity)
                arView.scene.addAnchor(anchorEntity)
                meshAnchors[anchor.identifier] = anchorEntity
            }
        }

        // MARK: - Point cloud desde sceneDepth (LiDAR)

        private func updatePointCloud(frame: ARFrame) {
            guard let depthMap = frame.sceneDepth?.depthMap else { return }

            // Construir posiciones 3D muestreadas (cada 8 píxeles para no saturar)
            let width  = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let step   = 8

            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return }
            let floatPtr = base.assumingMemoryBound(to: Float32.self)

            let intrinsics = frame.camera.intrinsics
            let fx = intrinsics[0][0]
            let fy = intrinsics[1][1]
            let cx = intrinsics[2][0]
            let cy = intrinsics[2][1]

            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity((width / step) * (height / step))

            for row in stride(from: 0, to: height, by: step) {
                for col in stride(from: 0, to: width, by: step) {
                    let depth = floatPtr[row * width + col]
                    guard depth > 0.1 && depth < 5.0 else { continue }
                    let x = (Float(col) - cx) / fx * depth
                    let y = (Float(row) - cy) / fy * depth
                    positions.append(SIMD3(x, -y, -depth))
                }
            }

            guard !positions.isEmpty else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let arView = self.arView else { return }
                self.renderPointCloud(positions: positions,
                                      transform: frame.camera.transform,
                                      in: arView)
            }
        }

        private func renderPointCloud(positions: [SIMD3<Float>],
                                      transform: simd_float4x4,
                                      in arView: ARView) {
            // Eliminar cloud anterior
            pointCloudAnchor?.removeFromParent()

            var meshDescriptor = MeshDescriptor(name: "pointCloud")
            meshDescriptor.positions = MeshBuffer(positions)
            meshDescriptor.primitives = .points(Array(UInt32(0)..<UInt32(positions.count)))

            guard let mesh = try? MeshResource.generate(from: [meshDescriptor]) else { return }

            var mat = UnlitMaterial()
            mat.color = .init(tint: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8))

            let cloud = ModelEntity(mesh: mesh, materials: [mat])
            let anchor = AnchorEntity(world: transform)
            anchor.name = "pointCloud"
            anchor.addChild(cloud)
            arView.scene.addAnchor(anchor)
            pointCloudAnchor = anchor
        }

        // MARK: - Tap

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            onTap?(point)
        }
    }
}
