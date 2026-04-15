// VolumeCalculator.swift
// Calcula el volumen de cada habitación usando:
//  - Área del footprint (RoomSegment.area)
//  - Altura = avgY(vértices .ceiling) − avgY(vértices .floor) dentro del bbox del segmento
//
// Fallback si no hay mesh de techo: 2.4 m estándar.

import ARKit
import simd

// MARK: - Resultado de volumen

struct RoomVolumeInfo {
    var roomId:     Int
    var floorArea:  Float   // m²
    var avgHeight:  Float   // m
    var minHeight:  Float   // m
    var maxHeight:  Float   // m
    var volume:     Float   // m³

    func toDictionary() -> [String: Any] {
        [
            "roomId":    roomId,
            "floorArea": Double(floorArea),
            "avgHeight": Double(avgHeight),
            "minHeight": Double(minHeight),
            "maxHeight": Double(maxHeight),
            "volume":    Double(volume),
        ]
    }
}

// MARK: - VolumeCalculator

class VolumeCalculator {

    static let shared = VolumeCalculator()

    // MARK: API pública

    /// Calcula volumen para un segmento individual.
    /// Busca vértices .ceiling dentro del bounding box del segmento.
    func calculate(for segment: RoomSegment) -> RoomVolumeInfo {
        let (ceilingYs, floorYs) = sampleYValues(for: segment)

        let avgCeiling: Float = ceilingYs.isEmpty
            ? estimateCeilingY() + 2.4
            : ceilingYs.reduce(0, +) / Float(ceilingYs.count)

        let avgFloor: Float = floorYs.isEmpty
            ? estimateFloorY()
            : floorYs.reduce(0, +) / Float(floorYs.count)

        let avgH   = max(0.5, avgCeiling - avgFloor)
        let minH   = (ceilingYs.isEmpty ? avgCeiling : (ceilingYs.min() ?? avgCeiling)) - avgFloor
        let maxH   = (ceilingYs.isEmpty ? avgCeiling : (ceilingYs.max() ?? avgCeiling)) - avgFloor
        let volume = segment.area * avgH

        return RoomVolumeInfo(
            roomId:    segment.id,
            floorArea: segment.area,
            avgHeight: avgH,
            minHeight: max(0.1, minH),
            maxHeight: max(0.1, maxH),
            volume:    volume
        )
    }

    /// Calcula volumen para todos los segmentos, enriquece el array y lo devuelve.
    func enrichAll(_ segments: [RoomSegment]) -> [RoomSegment] {
        segments.map { seg in
            let info = calculate(for: seg)
            var s = seg
            s.avgHeight = info.avgHeight
            s.volume    = info.volume
            return s
        }
    }

    /// Altura media en tiempo real: avgCeilingY − avgFloorY del mesh actual.
    /// Rápido — sampleamos máximo 300 vértices de cada tipo.
    /// Fallback: 2.4 m si no hay suficiente techo escaneado.
    func estimateHeight() -> Float {
        let floor   = estimateFloorY()
        let ceiling = estimateCeilingY()
        let h = ceiling - floor
        return h > 0.3 && h < 6.0 ? h : 2.4   // rango razonable para interior
    }

    /// Volumen total del espacio (suma de habitaciones o estimación directa).
    func totalVolume() -> Float {
        let segs = RoomSegmentationManager.shared.segments
        if segs.isEmpty {
            // Fallback: floor area × avg height estimada
            let floorArea  = MeshManager.shared.surfaces.floor
            let floorY     = estimateFloorY()
            let ceilingY   = estimateCeilingY()
            let h          = max(0.5, ceilingY - floorY)
            return floorArea > 0.1 ? floorArea * h : 0
        }
        return segs.reduce(0) { $0 + $1.volume }
    }

    // MARK: Privado

    private func sampleYValues(for seg: RoomSegment) -> (ceiling: [Float], floor: [Float]) {
        let anchors = MeshManager.shared.meshAnchors
        var ceilingYs = [Float]()
        var floorYs   = [Float]()

        // Tolerancia para incluir vértices ligeramente fuera del bbox
        let pad: Float = 0.30
        let minX = seg.bboxMin.x - pad; let maxX = seg.bboxMax.x + pad
        let minZ = seg.bboxMin.y - pad; let maxZ = seg.bboxMax.y + pad

        for anchor in anchors {
            let geo = anchor.geometry
            let transform = anchor.transform
            let vBuf = geo.vertices
            let fBuf = geo.faces
            let stride = fBuf.indexCountPerPrimitive

            for faceIdx in 0..<fBuf.count {
                let cls = geo.faceClassification(at: faceIdx)
                guard cls == .ceiling || cls == .floor else { continue }

                for k in 0..<stride {
                    let vIdx = fBuf.buffer.contents()
                        .advanced(by: (faceIdx * stride + k) * MemoryLayout<UInt32>.size)
                        .load(as: UInt32.self)
                    let local = vBuf.buffer.contents()
                        .advanced(by: Int(vIdx) * vBuf.stride)
                        .load(as: SIMD3<Float>.self)
                    let world = transform * SIMD4<Float>(local, 1)

                    // Solo vértices que caen dentro del bbox del segmento
                    guard world.x >= minX, world.x <= maxX,
                          world.z >= minZ, world.z <= maxZ else { continue }

                    if cls == .ceiling { ceilingYs.append(world.y) }
                    else               { floorYs.append(world.y)   }
                }
            }
        }

        return (ceilingYs, floorYs)
    }

    /// Y medio de todos los vértices .floor del mesh (referencia de suelo).
    private func estimateFloorY() -> Float {
        let anchors = MeshManager.shared.meshAnchors
        var ys = [Float]()
        for anchor in anchors {
            let geo = anchor.geometry
            let t   = anchor.transform
            for faceIdx in 0..<geo.faces.count {
                guard geo.faceClassification(at: faceIdx) == .floor else { continue }
                let stride = geo.faces.indexCountPerPrimitive
                for k in 0..<stride {
                    let vIdx = geo.faces.buffer.contents()
                        .advanced(by: (faceIdx * stride + k) * MemoryLayout<UInt32>.size)
                        .load(as: UInt32.self)
                    let local = geo.vertices.buffer.contents()
                        .advanced(by: Int(vIdx) * geo.vertices.stride)
                        .load(as: SIMD3<Float>.self)
                    ys.append((t * SIMD4<Float>(local, 1)).y)
                }
                if ys.count > 200 { break }
            }
        }
        return ys.isEmpty ? 0.0 : ys.reduce(0, +) / Float(ys.count)
    }

    /// Y medio de los vértices .ceiling (referencia de techo global).
    private func estimateCeilingY() -> Float {
        let anchors = MeshManager.shared.meshAnchors
        var ys = [Float]()
        for anchor in anchors {
            let geo = anchor.geometry
            let t   = anchor.transform
            for faceIdx in 0..<geo.faces.count {
                guard geo.faceClassification(at: faceIdx) == .ceiling else { continue }
                let stride = geo.faces.indexCountPerPrimitive
                for k in 0..<stride {
                    let vIdx = geo.faces.buffer.contents()
                        .advanced(by: (faceIdx * stride + k) * MemoryLayout<UInt32>.size)
                        .load(as: UInt32.self)
                    let local = geo.vertices.buffer.contents()
                        .advanced(by: Int(vIdx) * geo.vertices.stride)
                        .load(as: SIMD3<Float>.self)
                    ys.append((t * SIMD4<Float>(local, 1)).y)
                }
                if ys.count > 200 { break }
            }
        }
        return ys.isEmpty ? 2.4 : ys.reduce(0, +) / Float(ys.count)
    }
}
