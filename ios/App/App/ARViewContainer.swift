// ARViewContainer.swift
// Contenedor SwiftUI del ARView de RealityKit.
//
// Pipeline de renderizado:
//   ScanManager es el ÚNICO ARSessionDelegate.
//   Gestiona la malla LiDAR con AnchorEntity(anchor:) para seguimiento automático.
//
// Este Coordinator se encarga de:
//   - Overlay de superficies RoomPlan durante sesión activa
//   - Point cloud desde sceneDepth (via ScanManager.onEveryFrame)
//   - Tap gesture forwarding
//
// NO repite renderizado de mesh — eso lo hace exclusivamente ScanManager.

import SwiftUI
import ARKit
import RealityKit
import RoomPlan

struct ARViewContainer: UIViewRepresentable {

    var onTap:           ((CGPoint) -> Void)?
    var showSceneGraph:  Bool = false
    var showPointCloud:  Bool = false

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero,
                            cameraMode: .ar,
                            automaticallyConfigureSession: false)

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

        // ScanManager inicia la sesión y se asigna como ÚNICO session.delegate
        ScanManager.shared.startFullScan(arView: arView)

        context.coordinator.arView = arView
        context.coordinator.setupCallbacks(showPointCloud: showPointCloud)
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
        Coordinator(onTap: onTap)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {

        var onTap: ((CGPoint) -> Void)?
        weak var arView: ARView?

        /// RoomPlan surface identifier → AnchorEntity (overlay sesión RoomPlan)
        private var roomPlanAnchors: [UUID: AnchorEntity] = [:]

        /// Point cloud anchor activo
        private var pointCloudAnchor: AnchorEntity?

        init(onTap: ((CGPoint) -> Void)?) {
            self.onTap = onTap
        }

        // MARK: - Setup callbacks (en lugar de ser el delegate)

        func setupCallbacks(showPointCloud: Bool) {
            guard showPointCloud else { return }
            // Suscribirse al stream de frames de ScanManager para point cloud
            ScanManager.shared.onEveryFrame = { [weak self] frame in
                self?.updatePointCloud(frame: frame)
            }
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
            // Los overlays de color se manejan en LiDARPlugin.updateGuidanceOutlines
            // (cajas de borde blanco estilo Polycam). No añadir duplicados aquí.
        }

        private func clearRoomPlanOverlays(in arView: ARView) {
            roomPlanAnchors.values.forEach { $0.removeFromParent() }
            roomPlanAnchors.removeAll()
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
            var verts   = [SIMD3<Float>]()
            var indices = [UInt32]()
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
