// DepthManager.swift
// Gestiona el depth map píxel por píxel.
// Permite mediciones precisas, detección volumétrica y visión artificial.
// sceneDepth → rápido / smoothedSceneDepth → preciso

import ARKit
import CoreImage

class DepthManager {

    static let shared = DepthManager()

    // MARK: - Acceso al depth map del frame actual

    func depthMap(from frame: ARFrame) -> CVPixelBuffer? {
        return frame.sceneDepth?.depthMap
    }

    func smoothedDepthMap(from frame: ARFrame) -> CVPixelBuffer? {
        return frame.smoothedSceneDepth?.depthMap
    }

    // MARK: - Profundidad en un punto específico de pantalla (en metros)

    func depth(at point: CGPoint, in frame: ARFrame, viewSize: CGSize) -> Float? {

        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }

        let width  = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        let scaleX = CGFloat(width)  / viewSize.width
        let scaleY = CGFloat(height) / viewSize.height

        let x = Int(point.x * scaleX)
        let y = Int(point.y * scaleY)

        guard x >= 0, x < width, y >= 0, y < height else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let ptr = base.advanced(by: y * bytesPerRow + x * MemoryLayout<Float32>.size)

        return ptr.load(as: Float32.self)
    }

    // MARK: - Estadísticas del depth map (min, max, promedio)

    func statistics(from frame: ARFrame) -> (min: Float, max: Float, average: Float)? {

        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }

        let width  = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        var minVal: Float = Float.greatestFiniteMagnitude
        var maxVal: Float = 0
        var sum: Float = 0
        let count = width * height

        for i in 0..<count {
            let val = base.advanced(by: i * MemoryLayout<Float32>.size).load(as: Float32.self)
            if val.isFinite && val > 0 {
                minVal = Swift.min(minVal, val)
                maxVal = Swift.max(maxVal, val)
                sum += val
            }
        }

        return (minVal, maxVal, sum / Float(count))
    }

    // MARK: - Mapa de confianza

    func confidenceMap(from frame: ARFrame) -> CVPixelBuffer? {
        return frame.sceneDepth?.confidenceMap
    }
}
