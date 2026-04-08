// ScanQualityManager.swift
// Agente 10 — ScanQualityAgent
// Evalúa la calidad del escaneo en tiempo real.
// Detecta tracking débil, zonas sin cubrir y ruido de profundidad.
// Diferencia apps profesionales de demos básicas.

import ARKit

class ScanQualityManager {

    static let shared = ScanQualityManager()

    // MARK: - Estado de calidad

    enum ScanQuality {
        case excellent
        case good
        case poor
        case lost
    }

    var currentQuality: ScanQuality = .good
    var onQualityChanged: ((ScanQuality) -> Void)?
    var onSuggestRescan: ((String) -> Void)?

    private var consecutivePoorFrames = 0
    private let poorFrameThreshold = 30

    // MARK: - Evaluar frame ARKit

    func evaluate(frame: ARFrame) {
        let trackingQuality = evaluateTracking(state: frame.camera.trackingState)
        let lightQuality    = evaluateLighting(frame: frame)
        let depthAvailable  = frame.sceneDepth != nil

        let overall = combineQuality(tracking: trackingQuality,
                                     lighting: lightQuality,
                                     hasDepth: depthAvailable)

        if overall != currentQuality {
            currentQuality = overall
            onQualityChanged?(overall)
        }

        if overall == .poor || overall == .lost {
            consecutivePoorFrames += 1
        } else {
            consecutivePoorFrames = 0
        }

        if consecutivePoorFrames >= poorFrameThreshold {
            onSuggestRescan?("Mueve el dispositivo más despacio para mejorar el escaneo")
            consecutivePoorFrames = 0
        }
    }

    // MARK: - Tracking state

    private func evaluateTracking(state: ARCamera.TrackingState) -> ScanQuality {
        switch state {
        case .normal:
            return .excellent
        case .limited(let reason):
            switch reason {
            case .insufficientFeatures: return .poor
            case .excessiveMotion:      return .poor
            case .relocalizing:         return .good
            case .initializing:         return .good
            @unknown default:           return .good
            }
        case .notAvailable:
            return .lost
        }
    }

    // MARK: - Iluminación

    private func evaluateLighting(frame: ARFrame) -> ScanQuality {
        guard let intensity = frame.lightEstimate?.ambientIntensity else { return .good }
        if intensity < 100  { return .poor }
        if intensity < 500  { return .good }
        return .excellent
    }

    // MARK: - Combinar factores

    private func combineQuality(tracking: ScanQuality,
                                 lighting: ScanQuality,
                                 hasDepth: Bool) -> ScanQuality {
        if tracking == .lost   { return .lost }
        if tracking == .poor   { return .poor }
        if lighting == .poor   { return .poor }
        if !hasDepth           { return .good }
        if tracking == .excellent && lighting == .excellent { return .excellent }
        return .good
    }

    // MARK: - Detectar pérdida de tracking

    func detectTrackingLoss(state: ARCamera.TrackingState) -> Bool {
        if case .notAvailable = state { return true }
        return false
    }

    // MARK: - Detectar zonas sin cubrir (basado en densidad mesh)

    func detectCoverageGaps(anchors: [ARMeshAnchor], expectedArea: Float) -> Float {
        var scannedArea: Float = 0
        for anchor in anchors {
            let bounds = anchor.geometry.vertices
            let vCount = Float(bounds.count)
            scannedArea += vCount * 0.01
        }
        return min(1.0, scannedArea / max(1, expectedArea))
    }

    // MARK: - Sugerir rescaneo

    func suggestRescan(reason: String) {
        onSuggestRescan?(reason)
    }

    // MARK: - Texto legible de calidad

    func qualityLabel(_ quality: ScanQuality) -> String {
        switch quality {
        case .excellent: return "Excelente"
        case .good:      return "Bueno"
        case .poor:      return "Bajo — mueve el dispositivo más despacio"
        case .lost:      return "Tracking perdido — apunta a una superficie"
        }
    }

    // MARK: - Reset

    func reset() {
        currentQuality = .good
        consecutivePoorFrames = 0
    }
}
