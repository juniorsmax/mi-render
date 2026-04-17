// ARViewContainer.swift
// Contenedor SwiftUI del ARView de RealityKit.
// Pipeline de visualización en tiempo real:
//   - Mesh semántico desde ARMeshAnchor (coloreado por clasificación)
//   - Overlay de superficies RoomPlan durante sesión activa
//   - Overlay del SceneGraph en debug
//   - Point cloud desde sceneDepth si LiDAR disponible

import SwiftUI
import ARKit
import RealityKit
import RoomPlan

struct ARViewContainer: UIViewRepresentable {

    var onTap:           ((CGPoint) -> Void)?
    var showSceneGraph:  Bool = false
    var showPointCloud:  Bool = false

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        arView.environment.sceneUnderstanding.options = [
            .occlusion, .physics, .receivesLighting, .collision
        ]

        #if DEBUG
        if showSceneGraph {
            arView.debugOptions = [.showSceneUnderstanding, .showAnchorGeometry]
        }
        #endif

        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        ScanManager.shared.startFullScan(arView: arView)

        context.coordinator.arView = arView
        context.coordinator.startObservingMesh()
        context.coordinator.connectRoomPlan()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
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

        var onTap:        ((CGPoint) -> Void)?
        var showPointCloud: Bool

        weak var arView: ARView?

        /// ARMeshAnchor → AnchorEntity (mesh LiDAR)
        private var meshAnchors: [UUID: AnchorEntity] = [:]

        /// RoomPlan surface identifier → AnchorEntity (overlay sesión RoomPlan)
        private var roomPlanAnchors: [UUID: AnchorEntity] = [:]

        /// Point cloud anchor activo
        private var pointCloudAnchor: AnchorEntity?

        init(onTap: ((CGPoint) -> Void)?, showPointCloud: Bool) {
            self.onTap         = onTap
            self.showPointCloud = showPointCloud
        }

        // MARK: - Setup

        func startObservingMesh() {
            arView?.session.delegate = self
        }

        func connectRoomPlan() {
            if #available(iOS 16.0, *) {
                RoomPlanManager.shared.onRoomUpdated = { [weak self] room in
                    DispatchQueue.main.async { self?.captureSessionDidUpdate(room: room) }
                }
            }
        }

        // MARK: - RoomPlan overlay en tiempo real

        @available(iOS 16.0, *)
        private func captureSessionDidUpdate(room: CapturedRoom) {
            guard let arView = arView else { return }
            clearRoomPlanOverlays(in: arView)
            var newAnchors: [UUID: AnchorEntity] = [:]

            let surfaceGroups: [(surfaces: [CapturedRoom.Surface], color: UIColor)] = [
                (room.walls,   UIColor(red: 0.8, green: 0.8, blue: 0.9, alpha: 0.5)),
                (room.doors,   UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.7)),
                (room.windows, UIColor(red: 0.5, green: 0.8, blue: 0.9, alpha: 0.4))
            ]

            for (surfaceList, color) in surfaceGroups {
                for surface in surfaceList {
                    let d    = surface.dimensions
                    let mesh = MeshResource.generateBox(
                        size: SIMD3<Float>(d.x, d.y, max(d.z, 0.05))
                    )
                    let entity = ModelEntity(mesh: mesh)
                    entity.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
                    let anchor = AnchorEntity(world: surface.transform)
                    anchor.name = "rp_\(surface.identifier.uuidString.prefix(8))"
                    anchor.addChild(entity)
                    arView.scene.addAnchor(anchor)
                    newAnchors[surface.identifier] = anchor
                }
            }

            for object in room.objects {
                let mesh   = MeshResource.generateBox(size: object.dimensions)
                let entity = ModelEntity(mesh: mesh)
                entity.model?.materials = [
                    SimpleMaterial(color: UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 0.6),
                                   isMetallic: false)
                ]
                let anchor = AnchorEntity(world: object.transform)
                anchor.name = "rp_obj_\(object.identifier.uuidString.prefix(8))"
                anchor.addChild(entity)
                arView.scene.addAnchor(anchor)
                newAnchors[object.identifier] = anchor
            }

            roomPlanAnchors = newAnchors
        }

        private func clearRoomPlanOverlays(in arView: ARView) {
            roomPlanAnchors.values.forEach { $0.removeFromParent() }
            roomPlanAnchors.removeAll()
        }

        // MARK: - ARSessionDelegate — mesh LiDAR

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            processAnchors(anchors)
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            processAnchors(anchors)
        }

        func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for anchor in anchors {
                    self.meshAnchors.removeValue(forKey: anchor.identifier)?.removeFromParent()
                }
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard showPointCloud else { return }
            updatePointCloud(frame: frame)
        }

        // MARK: - Procesar ARMeshAnchor

        private func processAnchors(_ anchors: [ARAnchor]) {
            let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
            guard !meshes.isEmpty else { return }

            meshes.forEach { MeshManager.shared.addAnchor($0) }
            SceneGraphManager.shared.buildGraph(from: MeshManager.shared.meshAnchors)

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let arView = self.arView else { return }
                meshes.forEach { self.renderMeshAnchor($0, in: arView) }
            }
        }

        // MARK: - Renderizar ARMeshAnchor

        private func renderMeshAnchor(_ anchor: ARMeshAnchor, in arView: ARView) {
            guard let descriptor = meshDescriptor(from: anchor.geometry),
                  let meshResource = try? MeshResource.generate(from: [descriptor]) else { return }

            let modelEntity = ModelEntity(mesh: meshResource)

            // Material visible por defecto; reemplazar con semántico si disponible
            let classification: ARMeshClassification = anchor.geometry.faces.count > 0
                ? anchor.geometry.faceClassification(at: 0)
                : .none

            modelEntity.model?.materials = [
                classification != .none
                    ? MeshRenderer.shared.material(for: classification)
                    : SimpleMaterial(color: .blue.withAlphaComponent(0.4), isMetallic: false)
            ]

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

        /// Convierte ARMeshGeometry en MeshDescriptor leyendo directamente los buffers MTL.
        private func meshDescriptor(from geometry: ARMeshGeometry) -> MeshDescriptor? {
            let vSrc   = geometry.vertices
            let fSrc   = geometry.faces

            // Vértices (format .float3, stride >= 12, offset suele ser 0)
            let vPtr   = vSrc.buffer.contents()
            var positions = [SIMD3<Float>]()
            positions.reserveCapacity(vSrc.count)
            for i in 0..<vSrc.count {
                let byteOffset = vSrc.offset + i * vSrc.stride
                let x = vPtr.load(fromByteOffset: byteOffset,     as: Float.self)
                let y = vPtr.load(fromByteOffset: byteOffset + 4, as: Float.self)
                let z = vPtr.load(fromByteOffset: byteOffset + 8, as: Float.self)
                positions.append(SIMD3(x, y, z))
            }

            // Índices de triángulos (3 índices por cara)
            let fPtr   = fSrc.buffer.contents()
            let bpi    = fSrc.bytesPerIndex          // 2 (UInt16) o 4 (UInt32)
            let total  = fSrc.count * 3
            var indices = [UInt32]()
            indices.reserveCapacity(total)
            for i in 0..<total {
                let byteOffset = i * bpi
                let idx: UInt32 = bpi == 2
                    ? UInt32(fPtr.load(fromByteOffset: byteOffset, as: UInt16.self))
                    : fPtr.load(fromByteOffset: byteOffset, as: UInt32.self)
                indices.append(idx)
            }

            var descriptor = MeshDescriptor(name: "arMesh")
            descriptor.positions  = MeshBuffer(positions)
            descriptor.primitives = .triangles(indices)
            return descriptor
        }

        // MARK: - Point cloud (sceneDepth, LiDAR)

        private func updatePointCloud(frame: ARFrame) {
            guard let depthMap = frame.sceneDepth?.depthMap else { return }

            let width  = CVPixelBufferGetWidth(depthMap)
            let height = CVPixelBufferGetHeight(depthMap)
            let step   = 8

            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

            guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return }
            let floatPtr = base.assumingMemoryBound(to: Float32.self)

            let intr = frame.camera.intrinsics
            let fx = intr[0][0], fy = intr[1][1]
            let cx = intr[2][0], cy = intr[2][1]

            var points: [SIMD3<Float>] = []
            for row in stride(from: 0, to: height, by: step) {
                for col in stride(from: 0, to: width, by: step) {
                    let depth = floatPtr[row * width + col]
                    guard depth > 0.1 && depth < 5.0 else { continue }
                    points.append(SIMD3(
                        (Float(col) - cx) / fx * depth,
                        -(Float(row) - cy) / fy * depth,
                        -depth
                    ))
                }
            }
            guard !points.isEmpty else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let arView = self.arView else { return }
                self.renderPointCloud(points: points,
                                      transform: frame.camera.transform,
                                      in: arView)
            }
        }

        /// Renderiza el point cloud como micro-triángulos (RealityKit no soporta .points).
        private func renderPointCloud(points: [SIMD3<Float>],
                                      transform: simd_float4x4,
                                      in arView: ARView) {
            pointCloudAnchor?.removeFromParent()

            let tiny: Float = 0.004
            var verts    = [SIMD3<Float>]()
            var indices  = [UInt32]()
            verts.reserveCapacity(points.count * 3)
            indices.reserveCapacity(points.count * 3)

            for (i, p) in points.enumerated() {
                let base = UInt32(i * 3)
                verts.append(p + SIMD3( 0,     tiny, 0))
                verts.append(p + SIMD3(-tiny, -tiny, 0))
                verts.append(p + SIMD3( tiny, -tiny, 0))
                indices.append(contentsOf: [base, base + 1, base + 2])
            }

            var descriptor = MeshDescriptor(name: "pointCloud")
            descriptor.positions  = MeshBuffer(verts)
            descriptor.primitives = .triangles(indices)

            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return }

            var mat = UnlitMaterial()
            mat.color = .init(tint: UIColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.8))

            let cloud  = ModelEntity(mesh: mesh, materials: [mat])
            let anchor = AnchorEntity(world: transform)
            anchor.name = "pointCloud"
            anchor.addChild(cloud)
            arView.scene.addAnchor(anchor)
            pointCloudAnchor = anchor
        }

        // MARK: - Tap

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onTap?(gesture.location(in: gesture.view))
        }
    }
}
