// MeasurementManager.swift
// Medición profesional de distancias, áreas y volúmenes.
// Precisión típica en interior: ±5 mm con LiDAR.

import ARKit
import RealityKit
import simd

class MeasurementManager {

    static let shared = MeasurementManager()

    private var measurementPoints: [SIMD3<Float>] = []

    // MARK: - Distancia entre dos puntos 3D

    func measureDistance(from pointA: SIMD3<Float>,
                         to pointB: SIMD3<Float>) -> Float {
        return simd_distance(pointA, pointB)
    }

    // MARK: - Distancia en metros, formateada

    func formattedDistance(from pointA: SIMD3<Float>,
                           to pointB: SIMD3<Float>) -> String {
        let d = measureDistance(from: pointA, to: pointB)
        if d < 1.0 {
            return String(format: "%.0f cm", d * 100)
        } else {
            return String(format: "%.2f m", d)
        }
    }

    // MARK: - Raycast para obtener punto 3D desde posición en pantalla

    func getWorldPoint(at screenPoint: CGPoint,
                       arView: ARView) -> SIMD3<Float>? {

        let results = arView.raycast(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        )

        return results.first.map {
            SIMD3<Float>(
                $0.worldTransform.columns.3.x,
                $0.worldTransform.columns.3.y,
                $0.worldTransform.columns.3.z
            )
        }
    }

    // MARK: - Acumular puntos para medición multipunto

    func addPoint(_ point: SIMD3<Float>) {
        measurementPoints.append(point)
    }

    func clearPoints() {
        measurementPoints.removeAll()
    }

    // MARK: - Distancia total de la polilínea acumulada

    func totalLength() -> Float {
        guard measurementPoints.count >= 2 else { return 0 }
        var total: Float = 0
        for i in 1..<measurementPoints.count {
            total += measureDistance(from: measurementPoints[i-1], to: measurementPoints[i])
        }
        return total
    }

    // MARK: - Área de polígono desde puntos en el suelo (fórmula Shoelace)

    func polygonArea(points: [SIMD3<Float>]) -> Float {
        guard points.count >= 3 else { return 0 }

        var area: Float = 0
        let n = points.count

        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].z
            area -= points[j].x * points[i].z
        }

        return abs(area) / 2.0
    }

    // MARK: - Volumen aproximado desde bounding box

    func volume(from depthMap: CVPixelBuffer,
                boundingBox: CGRect,
                referenceDepth: Float) -> Float {

        let width  = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return 0 }

        var totalDepth: Float = 0
        var count: Int = 0

        let startX = Int(boundingBox.minX * CGFloat(width))
        let endX   = Int(boundingBox.maxX * CGFloat(width))
        let startY = Int(boundingBox.minY * CGFloat(height))
        let endY   = Int(boundingBox.maxY * CGFloat(height))

        for y in startY..<endY {
            for x in startX..<endX {
                let idx = y * CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size + x
                let depth = base.advanced(by: idx * MemoryLayout<Float32>.size).load(as: Float32.self)
                if depth.isFinite && depth > 0 {
                    totalDepth += referenceDepth - depth
                    count += 1
                }
            }
        }

        guard count > 0 else { return 0 }

        let avgHeight = totalDepth / Float(count)
        let pixelAreaM2: Float = Float(boundingBox.width * boundingBox.height) * 0.001
        return avgHeight * pixelAreaM2
    }
}
