// MeasurementManager.swift
// Medición profesional de distancias, áreas y volúmenes.
// Incluye cálculo automático de paredes individuales desde ARMeshClassification.wall.
// Precisión típica en interior: ±5 mm con LiDAR.

import ARKit
import RealityKit
import simd

// ── Estructuras de pared detectada ───────────────────────────────────────────

struct WallDimensions {
    var width:  Float   // metros — extensión horizontal
    var height: Float   // metros — extensión vertical
}

struct WallPlane {
    var id:         Int
    var label:      String              // "N", "S", "E", "O" o "W1"…
    var normal:     SIMD3<Float>        // normal unitario en world space
    var distance:   Float               // distancia del plano al origen
    var area:       Float               // m² total acumulado
    var faceCount:  Int
    var centroid:   SIMD3<Float>        // promedio ponderado de centroides
    var dimensions: WallDimensions

    func toDictionary() -> [String: Any] {
        [
            "id":         id,
            "label":      label,
            "area":       Double((area    * 100).rounded() / 100),
            "width":      Double((dimensions.width  * 100).rounded() / 100),
            "height":     Double((dimensions.height * 100).rounded() / 100),
            "faceCount":  faceCount,
            "normalX":    Double(normal.x),
            "normalY":    Double(normal.y),
            "normalZ":    Double(normal.z),
            "centroidX":  Double(centroid.x),
            "centroidY":  Double(centroid.y),
            "centroidZ":  Double(centroid.z),
        ]
    }
}

// ── MeasurementManager ────────────────────────────────────────────────────────

class MeasurementManager {

    static let shared = MeasurementManager()

    private var measurementPoints: [SIMD3<Float>] = []

    // Paredes detectadas — actualizado cada vez que se llama calculateWallAreas()
    private(set) var wallPlanes: [WallPlane] = []

    // Callback en hilo principal cuando las paredes se recalculan
    var onWallsCalculated: (([WallPlane]) -> Void)?

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

    // MARK: - ── Cálculo automático de paredes desde ARMeshClassification ───────
    //
    // Algoritmo:
    //  1. Itera todos los ARMeshAnchor de MeshManager
    //  2. Para cada cara .wall: calcula normal world-space + área + centroide
    //  3. Filtra caras con normal demasiado vertical (suelo/techo mal clasificado)
    //  4. Agrupa por plano: normalidad similar (|dot| > 0.85) + distancia < 15 cm
    //  5. Calcula dimensiones (ancho × alto) proyectando vértices en coordenadas
    //     locales de la pared: tangente horizontal + eje Y vertical
    //  6. Ordena por área descendente, asigna etiquetas cardinales / W1…Wn
    //
    // Complejidad: O(total_faces). Ejecutar en background.

    func calculateWallAreas() {
        let anchors = MeshManager.shared.meshAnchors    // acceso al snapshot interno
        guard !anchors.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let planes = self.detectWallPlanes(from: anchors)
            DispatchQueue.main.async {
                self.wallPlanes = planes
                self.onWallsCalculated?(planes)
            }
        }
    }

    // ── Núcleo: detecta y agrupa planos de pared ──────────────────────────────

    private func detectWallPlanes(from anchors: [ARMeshAnchor]) -> [WallPlane] {

        // Acumuladores temporales con buffers de extensión para dimensiones
        struct GroupAccum {
            var normal:    SIMD3<Float>
            var distance:  Float
            var area:      Float
            var centroid:  SIMD3<Float>
            var faceCount: Int
            var minU: Float =  .infinity    // extensión horizontal (tangente)
            var maxU: Float = -.infinity
            var minV: Float =  .infinity    // extensión vertical (eje Y)
            var maxV: Float = -.infinity
        }

        var groups: [GroupAccum] = []

        let worldUp = SIMD3<Float>(0, 1, 0)

        for anchor in anchors {
            let geometry  = anchor.geometry
            let transform = anchor.transform
            let vBuf      = geometry.vertices
            let fBuf      = geometry.faces
            let faceCount = fBuf.count

            let vPtr = vBuf.buffer.contents()
                .advanced(by: vBuf.offset)
                .assumingMemoryBound(to: Float.self)
            let iPtr = fBuf.buffer.contents()
                .advanced(by: fBuf.offset)
                .assumingMemoryBound(to: UInt32.self)

            let vStride = vBuf.stride / MemoryLayout<Float>.stride

            for f in 0..<faceCount {

                guard geometry.faceClassification(at: f) == .wall else { continue }

                let base = f * 3
                let i0 = Int(iPtr[base]),  i1 = Int(iPtr[base+1]),  i2 = Int(iPtr[base+2])

                let lp0 = SIMD3<Float>(vPtr[i0*vStride], vPtr[i0*vStride+1], vPtr[i0*vStride+2])
                let lp1 = SIMD3<Float>(vPtr[i1*vStride], vPtr[i1*vStride+1], vPtr[i1*vStride+2])
                let lp2 = SIMD3<Float>(vPtr[i2*vStride], vPtr[i2*vStride+1], vPtr[i2*vStride+2])

                let r0  = transform * SIMD4<Float>(lp0, 1)
                let r1  = transform * SIMD4<Float>(lp1, 1)
                let r2  = transform * SIMD4<Float>(lp2, 1)
                let wp0 = SIMD3<Float>(r0.x, r0.y, r0.z)
                let wp1 = SIMD3<Float>(r1.x, r1.y, r1.z)
                let wp2 = SIMD3<Float>(r2.x, r2.y, r2.z)

                // Normal de la cara en world space
                let ab = wp1 - wp0
                let ac = wp2 - wp0
                let rawNormal = simd_cross(ab, ac)
                let rawLen    = simd_length(rawNormal)
                guard rawLen > 1e-6 else { continue }

                let faceNormal = rawNormal / rawLen
                let faceArea   = 0.5 * rawLen

                // Filtrar caras demasiado horizontales → no son pared vertical
                guard abs(faceNormal.y) < 0.45 else { continue }

                // Normalizar normal a componente horizontal (anular inclinación residual)
                let nFlat = simd_normalize(SIMD3<Float>(faceNormal.x, 0, faceNormal.z))

                let faceCentroid  = (wp0 + wp1 + wp2) / 3.0
                let faceDistance  = simd_dot(nFlat, faceCentroid)

                // Tangente de la pared: perpendicular horizontal al normal
                let tangent = simd_normalize(simd_cross(worldUp, nFlat))

                // Proyecciones para dimensiones
                let us = [simd_dot(wp0, tangent), simd_dot(wp1, tangent), simd_dot(wp2, tangent)]
                let vs = [wp0.y, wp1.y, wp2.y]

                // Buscar grupo compatible
                var matched = false
                for idx in 0..<groups.count {
                    let g = groups[idx]
                    let normalSim  = abs(simd_dot(g.normal, nFlat))
                    let distDelta  = abs(g.distance - faceDistance)

                    guard normalSim > 0.85, distDelta < 0.15 else { continue }

                    // Fusionar: actualizar promedio ponderado por área
                    let totalArea = g.area + faceArea
                    let newNormal = simd_normalize(g.normal * g.area + nFlat * faceArea)
                    let newDist   = (g.distance * g.area + faceDistance * faceArea) / totalArea
                    let newCent   = (g.centroid * g.area + faceCentroid * faceArea) / totalArea

                    groups[idx].normal    = newNormal
                    groups[idx].distance  = newDist
                    groups[idx].area      = totalArea
                    groups[idx].centroid  = newCent
                    groups[idx].faceCount += 1
                    groups[idx].minU = min(g.minU, us.min()!)
                    groups[idx].maxU = max(g.maxU, us.max()!)
                    groups[idx].minV = min(g.minV, vs.min()!)
                    groups[idx].maxV = max(g.maxV, vs.max()!)
                    matched = true
                    break
                }

                if !matched {
                    groups.append(GroupAccum(
                        normal:    nFlat,
                        distance:  faceDistance,
                        area:      faceArea,
                        centroid:  faceCentroid,
                        faceCount: 1,
                        minU: us.min()!, maxU: us.max()!,
                        minV: vs.min()!, maxV: vs.max()!
                    ))
                }
            }
        }

        // Filtrar grupos demasiado pequeños (ruido < 0.05 m²)
        let significant = groups.filter { $0.area >= 0.05 }

        // Ordenar por área descendente
        let sorted = significant.sorted { $0.area > $1.area }

        // Convertir a WallPlane con etiquetas
        return sorted.enumerated().map { (i, g) in
            let dims = WallDimensions(
                width:  max(0, g.maxU - g.minU),
                height: max(0, g.maxV - g.minV)
            )
            return WallPlane(
                id:         i + 1,
                label:      cardinalLabel(for: g.normal, index: i + 1),
                normal:     g.normal,
                distance:   g.distance,
                area:       g.area,
                faceCount:  g.faceCount,
                centroid:   g.centroid,
                dimensions: dims
            )
        }
    }

    // ── Etiqueta cardinal según normal ────────────────────────────────────────
    //
    // ARKit: +X = derecha, +Z = hacia el usuario al inicio de sesión.
    // Normal apunta HACIA FUERA de la pared.

    private func cardinalLabel(for normal: SIMD3<Float>, index: Int) -> String {
        let nx = normal.x, nz = normal.z
        let thresh: Float = 0.65

        if nz >  thresh { return "S" }   // pared sur — normal apunta hacia el usuario
        if nz < -thresh { return "N" }   // pared norte
        if nx >  thresh { return "E" }   // pared este
        if nx < -thresh { return "O" }   // pared oeste
        return "W\(index)"               // pared diagonal o sin dirección dominante
    }
}

