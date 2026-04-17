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

        // Conectar delegate de sesión ARKit para mesh LiDAR
        context.coordinator.arView = arView
        context.coordinator.startObservingMesh()
        // Conectar RoomPlan para overlay en tiempo real durante sesión
        context.coordinator.connectRoomPlan()

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

        /// ARMeshAnchor → AnchorEntity en escena (mesh LiDAR)
        private var meshAnchors: [UUID: AnchorEntity] = [:]

        /// RoomPlan surface → AnchorEntity en escena (overlay sesión RoomPlan)
        private var roomPlanAnchors: [UUID: AnchorEntity] = [:]

        /// Entidad raíz del point cloud
        private var pointCloudAnchor: AnchorEntity?

        init(onTap: ((CGPoint) -> Void)?, showPointCloud: Bool) {
            self.onTap        = onTap
            self.showPointCloud = showPointCloud
        }

        // MARK: - Observar updates de mesh

        func startObservingMesh() {
            arView?.session.delegate = self
            // Mesh desde RoomPlan se genera en captureSession(_:didUpdate:) abajo.
            // No hay generación de mesh en init/setup.
        }

        // MARK: - RoomPlan captureSession(_:didUpdate:) — mesh en tiempo real

        /// Llamado desde RoomPlanManager.onRoomUpdated vía connectRoomPlan().
        /// Genera un ModelEntity por cada superficie de la sala y lo adjunta a la escena.
        @available(iOS 16.0, *)
        func captureSessionDidUpdate(room: CapturedRoom) {
            guard let arView = arView else { return }

            // Limpiar overlays de sesión anterior
            clearRoomPlanOverlays(in: arView)

            var newAnchors: [UUID: AnchorEntity] = [:]

            // Superficies: walls, doors, windows
            let surfaces: [(surfaces: [CapturedRoom.Surface], color: UIColor)] = [
                (room.walls,   UIColor(red: 0.8, green: 0.8, blue: 0.9, alpha: 0.5)),
                (room.doors,   UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.7)),
                (room.windows, UIColor(red: 0.5, green: 0.8, blue: 0.9, alpha: 0.4))
            ]

            for (surfaceList, color) in surfaces {
                for surface in surfaceList {
                    let id = surface.identifier
                    let d  = surface.dimensions
                    let mesh = MeshResource.generateBox(
                        size: SIMD3<Float>(d.x, d.y, max(d.z, 0.05))
                    )
                    let modelEntity = ModelEntity(mesh: mesh)
                    modelEntity.model?.materials = [
                        SimpleMaterial(color: color, isMetallic: false)
                    ]
                    let anchor = AnchorEntity(world: surface.transform)
                    anchor.name = "rp_\(id.uuidString.prefix(8))"
                    anchor.addChild(modelEntity)
                    arView.scene.addAnchor(anchor)
                    newAnchors[id] = anchor
                }
            }

            // Objetos / muebles
            for object in room.objects {
                let id = object.identifier
                let d  = object.dimensions
                let mesh = MeshResource.generateBox(size: d)
                let modelEntity = ModelEntity(mesh: mesh)
                modelEntity.model?.materials = [
                    SimpleMaterial(color: UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 0.6),
                                   isMetallic: false)
                ]
                let anchor = AnchorEntity(world: object.transform)
                anchor.name = "rp_obj_\(id.uuidString.prefix(8))"
                anchor.addChild(modelEntity)
                arView.scene.addAnchor(anchor)
                newAnchors[id] = anchor
            }

            roomPlanAnchors = newAnchors
        }

        private func clearRoomPlanOverlays(in arView: ARView) {
            roomPlanAnchors.values.forEach { $0.removeFromParent() }
            roomPlanAnchors.removeAll()
        }

        func connectRoomPlan() {
            if #available(iOS 16.0, *) {
                RoomPlanManager.shared.onRoomUpdated = { [weak self] room in
                    DispatchQueue.main.async {
                        self?.captureSessionDidUpdate(room: room)
                    }
                }
            }
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

            // ModelEntity con material visible garantizado (azul semitransparente)
            let modelEntity = ModelEntity(mesh: meshResource)
            modelEntity.model?.materials = [
                SimpleMaterial(color: .blue.withAlphaComponent(0.4), isMetallic: false)
            ]

            // Aplicar material semántico encima si la clasificación es conocida
            let classification: ARMeshClassification = anchor.geometry.faces.count > 0
                ? anchor.geometry.faceClassification(at: 0)
                : .none
            if classification != .none {
                modelEntity.model?.materials = [MeshRenderer.shared.material(for: classification)]
            }

            if let existing = meshAnchors[anchor.identifier] {
                existing.children.forEach { $0.removeFromParent() }
                existing.addChild(modelEntity)
                existing.transform = Transform(matrix: anchor.transform)
            } else {
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
