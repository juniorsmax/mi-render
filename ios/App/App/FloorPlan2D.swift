// FloorPlan2D.swift
// Proyección 2D del mesh de suelo → contorno exterior limpio.
//
// Pipeline:
//   ARMeshAnchor (faces .floor) → SIMD2<Float> XZ → ConvexHull → Douglas-Peucker → FloorFootprint
//
// FloorFootprint es el dato central que PlanRenderer usa para dibujar
// el plano planta cuando no hay CapturedRoom (solo ARKit mesh).

import simd
import CoreGraphics

// ── Footprint del espacio ─────────────────────────────────────────────────────

struct FloorFootprint {
    /// Polígono convex hull en metros, plano XZ (x → X, y → Z)
    let polygon:  [SIMD2<Float>]
    /// Bounding box en metros
    let minPoint: SIMD2<Float>
    let maxPoint: SIMD2<Float>
    /// Área del polígono en m² — fórmula del calzador
    let area:     Float
    /// Perímetro del polígono en metros (suma de aristas consecutivas)
    let perimeter: Float

    var pointCount: Int    { polygon.count }
    var width: Float       { maxPoint.x - minPoint.x }   // metros
    var depth: Float       { maxPoint.y - minPoint.y }   // metros (Y = Z)

    /// Serializa a diccionario listo para CAPPluginCall.resolve
    func toDictionary() -> [String: Any] {
        let pts = polygon.map { ["x": Double($0.x), "z": Double($0.y)] }
        return [
            "polygon":    pts,
            "area":       Double(area),
            "perimeter":  Double(perimeter),
            "width":      Double(width),
            "depth":      Double(depth),
            "minX":       Double(minPoint.x),
            "minZ":       Double(minPoint.y),
            "maxX":       Double(maxPoint.x),
            "maxZ":       Double(maxPoint.y),
            "pointCount": pointCount,
        ]
    }

    /// CGPath escalado listo para CoreGraphics (escala en puntos/metro)
    func cgPath(scale: CGFloat, offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        guard let first = polygon.first else { return path }
        path.move(to: CGPoint(x: CGFloat(first.x) * scale + offsetX,
                              y: CGFloat(first.y) * scale + offsetY))
        for pt in polygon.dropFirst() {
            path.addLine(to: CGPoint(x: CGFloat(pt.x) * scale + offsetX,
                                     y: CGFloat(pt.y) * scale + offsetY))
        }
        path.closeSubpath()
        return path
    }
}

// ── Convex Hull — Graham Scan O(n log n) ─────────────────────────────────────

enum ConvexHull {

    /// Devuelve el convex hull o nil si hay menos de 3 puntos no colineales.
    static func compute(_ points: [SIMD2<Float>]) -> [SIMD2<Float>]? {
        guard points.count >= 3 else { return nil }

        // 1. Punto ancla: mínima Y, desempate mínima X
        let anchor = points.min { a, b in
            a.y < b.y || (a.y == b.y && a.x < b.x)
        }!

        // 2. Ordenar por ángulo polar respecto al ancla
        let others = points.filter { $0 != anchor }
        let sorted = others.sorted { p1, p2 in
            let a1 = atan2(p1.y - anchor.y, p1.x - anchor.x)
            let a2 = atan2(p2.y - anchor.y, p2.x - anchor.x)
            if abs(a1 - a2) > 1e-9 { return a1 < a2 }
            return simd_distance(anchor, p1) < simd_distance(anchor, p2)
        }

        // 3. Colineales mismo ángulo → conservar el más lejano
        var filtered: [SIMD2<Float>] = []
        var i = 0
        while i < sorted.count {
            var j = i
            let baseAngle = atan2(sorted[i].y - anchor.y, sorted[i].x - anchor.x)
            while j < sorted.count - 1 {
                let nextAngle = atan2(sorted[j+1].y - anchor.y, sorted[j+1].x - anchor.x)
                if abs(baseAngle - nextAngle) < 1e-6 { j += 1 } else { break }
            }
            filtered.append(sorted[j])
            i = j + 1
        }

        guard filtered.count >= 2 else { return nil }

        // 4. Graham Scan
        var stack: [SIMD2<Float>] = [anchor, filtered[0], filtered[1]]
        for k in 2..<filtered.count {
            while stack.count > 1 && cross(stack[stack.count-2],
                                           stack[stack.count-1],
                                           filtered[k]) <= 0 {
                stack.removeLast()
            }
            stack.append(filtered[k])
        }

        return stack.count >= 3 ? stack : nil
    }

    // Producto vectorial 2D — positivo: giro antihorario
    private static func cross(_ O: SIMD2<Float>,
                               _ A: SIMD2<Float>,
                               _ B: SIMD2<Float>) -> Float {
        (A.x - O.x) * (B.y - O.y) - (A.y - O.y) * (B.x - O.x)
    }
}

// ── Douglas-Peucker — simplificación de polígono ──────────────────────────────

enum PolySimplify {

    /// Reduce el número de vértices conservando la forma global.
    /// epsilon en metros — típico: 0.05 m para habitaciones
    static func simplify(_ points: [SIMD2<Float>], epsilon: Float) -> [SIMD2<Float>] {
        guard points.count > 2 else { return points }

        let (maxDist, maxIdx) = maxPerpendicularDistance(points)

        if maxDist > epsilon {
            let left  = simplify(Array(points[0...maxIdx]), epsilon: epsilon)
            let right = simplify(Array(points[maxIdx...]),  epsilon: epsilon)
            return Array(left.dropLast()) + right
        } else {
            return [points.first!, points.last!]
        }
    }

    private static func maxPerpendicularDistance(
        _ pts: [SIMD2<Float>]
    ) -> (Float, Int) {
        let a = pts.first!, b = pts.last!
        let ab    = b - a
        let abLen = simd_length(ab)
        var maxDist: Float = 0
        var maxIdx = 0

        for i in 1..<(pts.count - 1) {
            let dist: Float
            if abLen < 1e-6 {
                dist = simd_distance(pts[i], a)
            } else {
                let ap = pts[i] - a
                let t  = max(0, min(1, simd_dot(ap, ab) / (abLen * abLen)))
                dist   = simd_distance(pts[i], a + t * ab)
            }
            if dist > maxDist { maxDist = dist; maxIdx = i }
        }
        return (maxDist, maxIdx)
    }
}

// ── FloorFootprintBuilder ─────────────────────────────────────────────────────

enum FloorFootprintBuilder {

    /// Construye el FloorFootprint desde MeshManager.shared.
    ///
    /// - Parameter simplifyEpsilon: tolerancia D-P en metros (0 = sin simplificar)
    /// - Returns: nil si no hay suficientes vértices de suelo escaneados
    static func build(simplifyEpsilon: Float = 0.05) -> FloorFootprint? {
        let raw = MeshManager.shared.getFloorVertices2D()
        guard raw.count >= 3 else { return nil }

        // Diezmar para limitar coste del hull con >2000 puntos
        let sampled = downsample(raw, maxPoints: 2000)

        // Convex Hull
        guard var hull = ConvexHull.compute(sampled) else { return nil }

        // Simplificar D-P
        if simplifyEpsilon > 0, hull.count > 6 {
            hull = PolySimplify.simplify(hull, epsilon: simplifyEpsilon)
            // Garantizar polígono cerrado mínimo
            if hull.count < 3 { hull = ConvexHull.compute(sampled) ?? hull }
        }

        // Bounding box
        var minPt = hull[0], maxPt = hull[0]
        for p in hull { minPt = simd_min(minPt, p); maxPt = simd_max(maxPt, p) }

        // Área y perímetro del polígono
        let area      = shoelaceArea(hull)
        let perimeter = polygonPerimeter(hull)

        return FloorFootprint(polygon:   hull,
                              minPoint:  minPt,
                              maxPoint:  maxPt,
                              area:      area,
                              perimeter: perimeter)
    }

    // Muestrea puntos equidistantes para reducir tamaño del array
    private static func downsample(_ pts: [SIMD2<Float>],
                                   maxPoints: Int) -> [SIMD2<Float>] {
        guard pts.count > maxPoints else { return pts }
        let step = pts.count / maxPoints
        return (0..<maxPoints).map { pts[$0 * step] }
    }

    // Perímetro del polígono — suma de distancias entre vértices consecutivos
    private static func polygonPerimeter(_ pts: [SIMD2<Float>]) -> Float {
        guard pts.count >= 2 else { return 0 }
        var total: Float = 0
        for i in 0..<pts.count {
            total += simd_distance(pts[i], pts[(i + 1) % pts.count])
        }
        return total
    }

    // Área del polígono — fórmula del calzador
    private static func shoelaceArea(_ pts: [SIMD2<Float>]) -> Float {
        let n = pts.count
        var sum: Float = 0
        for i in 0..<n {
            let j = (i + 1) % n
            sum += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return abs(sum) / 2.0
    }
}
