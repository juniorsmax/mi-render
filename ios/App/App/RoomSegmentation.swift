// RoomSegmentation.swift
// Detecta habitaciones múltiples separando el mesh del suelo en regiones conectadas.
// Algoritmo: grid XZ de ocupación → BFS flood-fill 8-conectividad → ConvexHull por región.

import ARKit
import simd

// MARK: - RoomSegment

struct RoomSegment {
    var id:         Int
    var label:      String          // "Habitacion 1", "Pasillo 2", etc.
    var area:       Float           // m² — shoelace sobre el polígono simplificado
    var centroid:   SIMD2<Float>    // centro XZ del segmento
    var polygon:    [SIMD2<Float>]  // convex hull simplificado
    var bboxMin:    SIMD2<Float>
    var bboxMax:    SIMD2<Float>
    var avgHeight:  Float = 0       // m — rellenado por VolumeCalculator
    var volume:     Float = 0       // m³ — area × avgHeight

    var width: Float  { bboxMax.x - bboxMin.x }
    var depth: Float  { bboxMax.y - bboxMin.y }

    func toDictionary() -> [String: Any] {
        [
            "id":       id,
            "label":    label,
            "area":     Double(area),
            "centroid": ["x": Double(centroid.x), "z": Double(centroid.y)],
            "polygon":  polygon.map { ["x": Double($0.x), "z": Double($0.y)] },
            "bbox": [
                "minX": Double(bboxMin.x), "minZ": Double(bboxMin.y),
                "maxX": Double(bboxMax.x), "maxZ": Double(bboxMax.y),
                "width": Double(width),    "depth": Double(depth),
            ],
            "avgHeight": Double(avgHeight),
            "volume":    Double(volume),
        ]
    }
}

// MARK: - RoomSegmentationManager

class RoomSegmentationManager {

    static let shared = RoomSegmentationManager()

    private(set) var segments: [RoomSegment] = []

    // MARK: Segmentación principal

    /// Segmenta los vértices .floor del mesh en habitaciones individuales.
    /// - Parameters:
    ///   - cellSize:   tamaño de celda de la cuadrícula en metros (default 0.20 m)
    ///   - minAreaM2:  área mínima para considerar una región habitación (default 0.8 m²)
    @discardableResult
    func segmentRooms(cellSize: Float = 0.20, minAreaM2: Float = 0.8) -> [RoomSegment] {
        let pts = MeshManager.shared.getFloorVertices2D()
        guard pts.count >= 10 else {
            segments = []
            return []
        }

        // ── 1. Construir cuadrícula de ocupación ────────────────────────────
        let xs = pts.map { $0.x }; let ys = pts.map { $0.y }
        let gMinX = xs.min()! - cellSize
        let gMinY = ys.min()! - cellSize
        let gMaxX = xs.max()! + cellSize
        let gMaxY = ys.max()! + cellSize

        let cols = max(1, Int((gMaxX - gMinX) / cellSize) + 1)
        let rows = max(1, Int((gMaxY - gMinY) / cellSize) + 1)

        var occupied = [[Bool]](repeating: [Bool](repeating: false, count: cols), count: rows)
        var cellPts  = [[[SIMD2<Float>]]](repeating:
                            [[SIMD2<Float>]](repeating: [], count: cols), count: rows)

        for pt in pts {
            let c = min(cols - 1, max(0, Int((pt.x - gMinX) / cellSize)))
            let r = min(rows - 1, max(0, Int((pt.y - gMinY) / cellSize)))
            occupied[r][c] = true
            cellPts[r][c].append(pt)
        }

        // ── 2. BFS flood-fill 8-conectividad ─────────────────────────────────
        var visited  = [[Bool]](repeating: [Bool](repeating: false, count: cols), count: rows)
        var rawSegs: [[SIMD2<Float>]] = []

        for sr in 0..<rows {
            for sc in 0..<cols {
                guard occupied[sr][sc] && !visited[sr][sc] else { continue }

                var queue    = [(sr, sc)]
                var head     = 0
                var segPts   = [SIMD2<Float>]()
                visited[sr][sc] = true

                while head < queue.count {
                    let (r, c) = queue[head]; head += 1
                    segPts.append(contentsOf: cellPts[r][c])

                    for dr in -1...1 {
                        for dc in -1...1 {
                            guard !(dr == 0 && dc == 0) else { continue }
                            let nr = r + dr; let nc = c + dc
                            guard nr >= 0, nr < rows, nc >= 0, nc < cols else { continue }
                            guard occupied[nr][nc] && !visited[nr][nc]   else { continue }
                            visited[nr][nc] = true
                            queue.append((nr, nc))
                        }
                    }
                }
                if segPts.count >= 5 { rawSegs.append(segPts) }
            }
        }

        // ── 3. Construir RoomSegment por región ───────────────────────────────
        var result: [RoomSegment] = []

        for (idx, segPts) in rawSegs.enumerated() {
            guard let hull = ConvexHull.compute(segPts) else { continue }
            let poly   = PolySimplify.simplify(hull, epsilon: 0.08)
            let area   = shoelace(poly)
            guard area >= minAreaM2 else { continue }

            let cx = segPts.reduce(0) { $0 + $1.x } / Float(segPts.count)
            let cy = segPts.reduce(0) { $0 + $1.y } / Float(segPts.count)
            let bMin = SIMD2<Float>(segPts.map { $0.x }.min()!, segPts.map { $0.y }.min()!)
            let bMax = SIMD2<Float>(segPts.map { $0.x }.max()!, segPts.map { $0.y }.max()!)

            result.append(RoomSegment(
                id:       idx,
                label:    roomLabel(area: area, index: idx),
                area:     area,
                centroid: SIMD2<Float>(cx, cy),
                polygon:  poly,
                bboxMin:  bMin,
                bboxMax:  bMax
            ))
        }

        // Ordenar por área desc, re-asignar IDs y etiquetas
        result.sort { $0.area > $1.area }
        for i in result.indices {
            result[i].id    = i
            result[i].label = roomLabel(area: result[i].area, index: i)
        }

        segments = result
        return result
    }

    // MARK: Helpers privados

    private func shoelace(_ pts: [SIMD2<Float>]) -> Float {
        guard pts.count >= 3 else { return 0 }
        var sum: Float = 0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            sum += pts[i].x * pts[j].y - pts[j].x * pts[i].y
        }
        return abs(sum) / 2
    }

    private func roomLabel(area: Float, index: Int) -> String {
        switch area {
        case 0..<4:   return "Baño \(index + 1)"
        case 4..<8:   return "Dormitorio \(index + 1)"
        case 8..<15:  return "Habitacion \(index + 1)"
        default:      return "Salon \(index + 1)"
        }
    }
}
