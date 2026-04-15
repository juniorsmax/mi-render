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

// MARK: - ARSessionDelegate — propaga ARMeshAnchor a MeshManager

extension ScanManager: ARSessionDelegate {

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
        meshAnchors.forEach { MeshManager.shared.update(anchor: $0) }
        onMeshAnchorsUpdated?(MeshManager.shared.meshAnchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }
        meshAnchors.forEach { MeshManager.shared.update(anchor: $0) }
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
