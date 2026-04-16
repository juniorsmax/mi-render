// FloorPlan2DGenerator.swift
// Genera un plano 2D arquitectónico desde la malla LiDAR reconstruida.
//
// Flujo:
//   1. Extrae caras verticales de ARMeshAnchor (class == wall o normal.y < 0.2)
//   2. Extrae ARPlaneAnchor.vertical como fallback
//   3. Proyecta vértices al plano XZ
//   4. Fusiona segmentos colineales
//   5. Filtra segmentos < 0.25 m
//   6. Exporta SVG / DXF / IFC y persiste en JSON

import ARKit
import simd
import UIKit

// MARK: - FloorSegment

struct FloorSegment: Codable {
    var start:     SIMD2<Float>
    var end:       SIMD2<Float>
    var thickness: Float

    var length: Float         { simd_distance(start, end) }
    var midpoint: SIMD2<Float> { (start + end) * 0.5 }

    var angle: Float {
        atan2(end.y - start.y, end.x - start.x)
    }
    var unitDirection: SIMD2<Float> {
        let d = end - start
        let l = simd_length(d)
        return l > 1e-5 ? d / l : SIMD2<Float>(1, 0)
    }
}

// MARK: - FloorPlan

struct FloorPlan: Codable {
    var segments:  [FloorSegment]
    var minBounds: SIMD2<Float>
    var maxBounds: SIMD2<Float>

    var roomBounds: CGRect {
        CGRect(
            x: CGFloat(minBounds.x), y: CGFloat(minBounds.y),
            width: CGFloat(maxBounds.x - minBounds.x),
            height: CGFloat(maxBounds.y - minBounds.y)
        )
    }
    var center: SIMD2<Float> { (minBounds + maxBounds) * 0.5 }

    static let empty = FloorPlan(segments: [], minBounds: .zero, maxBounds: .zero)
}

// MARK: - FloorPlan2DGenerator

class FloorPlan2DGenerator {

    static let shared = FloorPlan2DGenerator()

    private let docsDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    private var savedURL: URL { docsDir.appendingPathComponent("floorplan.json") }

    /// URL pública del archivo floorplan.json en Documents (para SceneProjectManager).
    var savedFloorplanURL: URL { savedURL }

    // MARK: - Generación principal

    func generateFloorPlan(from anchors: [ARAnchor]) -> FloorPlan {
        var raw: [FloorSegment] = []

        for anchor in anchors {
            if let mesh = anchor as? ARMeshAnchor {
                raw += extractWallSegments(from: mesh)
            } else if let plane = anchor as? ARPlaneAnchor,
                      plane.alignment == .vertical {
                if let seg = makeSegment(from: plane) { raw.append(seg) }
            }
        }

        guard !raw.isEmpty else { return .empty }

        let merged = mergeCollinear(raw).filter { $0.length >= 0.25 }
        guard !merged.isEmpty else { return .empty }

        let (minB, maxB) = bounds(of: merged)
        return FloorPlan(segments: merged, minBounds: minB, maxBounds: maxB)
    }

    // MARK: - Extracción ARMeshAnchor

    private func extractWallSegments(from anchor: ARMeshAnchor) -> [FloorSegment] {
        let geo     = anchor.geometry
        let t       = anchor.transform

        // Puntero a vértices
        let vPtr    = geo.vertices.buffer.contents()
            .advanced(by: geo.vertices.offset)
            .assumingMemoryBound(to: Float.self)
        let vStride = geo.vertices.stride / MemoryLayout<Float>.stride

        // Puntero a índices de caras
        let fCount  = geo.faces.count
        let iStride = geo.faces.indexCountPerPrimitive  // 3 para triángulos
        let iPtr    = geo.faces.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)

        // Puntero a clasificaciones (opcional)
        var clsPtr: UnsafeMutablePointer<UInt8>?
        var clsByteStride = 1
        if let cls = geo.classification {
            clsPtr        = cls.buffer.contents()
                .advanced(by: cls.offset)
                .assumingMemoryBound(to: UInt8.self)
            clsByteStride = cls.stride
        }

        // Rotación 3×3 para transformar normales
        let rot = simd_float3x3(
            SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z),
            SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z),
            SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        )

        var segments: [FloorSegment] = []
        segments.reserveCapacity(fCount / 8)

        for f in 0..<fCount {
            let base = f * iStride

            // ── Filtro de pared ──────────────────────────────────────────────
            if let cp = clsPtr {
                // ARKit classification: 1 = wall
                guard cp[f * clsByteStride] == 1 else { continue }
            } else {
                // Fallback: normal casi horizontal → abs(normal.y) < 0.2
                let i0 = Int(iPtr[base])
                let i1 = Int(iPtr[base + 1])
                let i2 = Int(iPtr[base + 2])
                let lv0 = vert(vPtr, i0, vStride)
                let lv1 = vert(vPtr, i1, vStride)
                let lv2 = vert(vPtr, i2, vStride)
                let cross = simd_cross(lv1 - lv0, lv2 - lv0)
                let cLen  = simd_length(cross)
                guard cLen > 1e-7 else { continue }
                let normalW = simd_normalize(rot * (cross / cLen))
                guard abs(normalW.y) < 0.2 else { continue }
            }

            // ── Vértices al espacio mundo ────────────────────────────────────
            let i0 = Int(iPtr[base])
            let i1 = Int(iPtr[base + 1])
            let i2 = Int(iPtr[base + 2])
            let wv0 = worldPoint(vert(vPtr, i0, vStride), t)
            let wv1 = worldPoint(vert(vPtr, i1, vStride), t)
            let wv2 = worldPoint(vert(vPtr, i2, vStride), t)

            // ── Proyección XZ ────────────────────────────────────────────────
            let p0 = SIMD2<Float>(wv0.x, wv0.z)
            let p1 = SIMD2<Float>(wv1.x, wv1.z)
            let p2 = SIMD2<Float>(wv2.x, wv2.z)

            // Borde más largo del triángulo proyectado = candidato de segmento
            let d01 = simd_distance(p0, p1)
            let d12 = simd_distance(p1, p2)
            let d20 = simd_distance(p2, p0)

            let seg: FloorSegment
            if d01 >= d12 && d01 >= d20 {
                seg = FloorSegment(start: p0, end: p1, thickness: 0.15)
            } else if d12 >= d20 {
                seg = FloorSegment(start: p1, end: p2, thickness: 0.15)
            } else {
                seg = FloorSegment(start: p2, end: p0, thickness: 0.15)
            }

            if seg.length >= 0.05 { segments.append(seg) }
        }
        return segments
    }

    // MARK: - Extracción ARPlaneAnchor vertical

    private func makeSegment(from anchor: ARPlaneAnchor) -> FloorSegment? {
        // planeExtent requiere iOS 16+; usamos extent (deprecado pero disponible iOS 15)
        let cx   = anchor.center.x
        let cz   = anchor.center.z
        let half: Float

        if #available(iOS 16.0, *) {
            half = anchor.planeExtent.width * 0.5
        } else {
            half = anchor.extent.x * 0.5
        }

        let localA = SIMD3<Float>(cx - half, anchor.center.y, cz)
        let localB = SIMD3<Float>(cx + half, anchor.center.y, cz)
        let wA     = worldPoint(localA, anchor.transform)
        let wB     = worldPoint(localB, anchor.transform)

        let seg = FloorSegment(
            start: SIMD2<Float>(wA.x, wA.z),
            end:   SIMD2<Float>(wB.x, wB.z),
            thickness: 0.15
        )
        return seg.length >= 0.25 ? seg : nil
    }

    // MARK: - Fusión de segmentos colineales

    private func mergeCollinear(_ input: [FloorSegment]) -> [FloorSegment] {
        var remaining = input
        var result:    [FloorSegment] = []

        while !remaining.isEmpty {
            let seed = remaining.removeFirst()
            let sa   = normalizedAngle(seed.angle)
            let dir  = SIMD2<Float>(cos(sa), sin(sa))
            let perp = SIMD2<Float>(-dir.y, dir.x)
            let spd  = simd_dot(seed.midpoint, perp)

            var cluster: [FloorSegment] = [seed]
            var i = 0
            while i < remaining.count {
                let other = remaining[i]
                let oa    = normalizedAngle(other.angle)
                let da    = abs(sa - oa)
                let angleOK = da < 0.17 || da > (.pi - 0.17)   // ≤ 10°

                let opd    = simd_dot(other.midpoint, perp)
                let distOK = abs(spd - opd) < 0.30              // ≤ 30 cm paralelo

                if angleOK && distOK {
                    cluster.append(remaining.remove(at: i))
                } else {
                    i += 1
                }
            }

            if let merged = mergeCluster(cluster, dir: dir, perp: perp) {
                result.append(merged)
            }
        }
        return result
    }

    private func normalizedAngle(_ a: Float) -> Float {
        var angle = a.truncatingRemainder(dividingBy: .pi)
        if angle < 0 { angle += .pi }
        return angle
    }

    private func mergeCluster(_ segs: [FloorSegment],
                               dir:  SIMD2<Float>,
                               perp: SIMD2<Float>) -> FloorSegment? {
        var minT =  Float.greatestFiniteMagnitude
        var maxT = -Float.greatestFiniteMagnitude
        var perpAcc: Float = 0

        for seg in segs {
            perpAcc += simd_dot(seg.midpoint, perp)
            let ts = simd_dot(seg.start, dir)
            let te = simd_dot(seg.end,   dir)
            minT = min(minT, min(ts, te))
            maxT = max(maxT, max(ts, te))
        }

        let pp    = perpAcc / Float(segs.count)
        let start = dir * minT + perp * pp
        let end   = dir * maxT + perp * pp
        let seg   = FloorSegment(start: start, end: end, thickness: 0.15)
        return seg.length >= 0.25 ? seg : nil
    }

    // MARK: - Bounding box

    private func bounds(of segs: [FloorSegment])
        -> (SIMD2<Float>, SIMD2<Float>) {
        var minP = SIMD2<Float>(repeating:  Float.greatestFiniteMagnitude)
        var maxP = SIMD2<Float>(repeating: -Float.greatestFiniteMagnitude)
        for s in segs {
            minP = simd_min(minP, simd_min(s.start, s.end))
            maxP = simd_max(maxP, simd_max(s.start, s.end))
        }
        guard minP.x != Float.greatestFiniteMagnitude else { return (.zero, .zero) }
        return (minP, maxP)
    }

    // MARK: - Helpers geométricos

    private func vert(_ ptr: UnsafePointer<Float>, _ i: Int, _ stride: Int) -> SIMD3<Float> {
        SIMD3<Float>(ptr[i * stride], ptr[i * stride + 1], ptr[i * stride + 2])
    }

    private func worldPoint(_ v: SIMD3<Float>, _ t: simd_float4x4) -> SIMD3<Float> {
        let w = t * SIMD4<Float>(v.x, v.y, v.z, 1)
        return SIMD3<Float>(w.x, w.y, w.z)
    }

    // MARK: - Persistencia JSON

    @discardableResult
    func save(_ plan: FloorPlan) -> Bool {
        guard let data = try? JSONEncoder().encode(plan) else { return false }
        do {
            try data.write(to: savedURL, options: .atomic)
            print("[FloorPlan] guardado \(plan.segments.count) segmentos")
            return true
        } catch {
            print("[FloorPlan] save error: \(error)")
            return false
        }
    }

    func loadSaved() -> FloorPlan? {
        guard let data = try? Data(contentsOf: savedURL) else { return nil }
        return try? JSONDecoder().decode(FloorPlan.self, from: data)
    }

    // MARK: - Exportación SVG

    func exportSVG(_ plan: FloorPlan) -> String {
        let scale:   Float = 80.0
        let padding: Float = 40.0
        let W = (plan.maxBounds.x - plan.minBounds.x) * scale + padding * 2
        let H = (plan.maxBounds.y - plan.minBounds.y) * scale + padding * 2
        var body = ""
        for seg in plan.segments {
            let x1 = (seg.start.x - plan.minBounds.x) * scale + padding
            let y1 = (seg.start.y - plan.minBounds.y) * scale + padding
            let x2 = (seg.end.x   - plan.minBounds.x) * scale + padding
            let y2 = (seg.end.y   - plan.minBounds.y) * scale + padding
            let sw = max(1.5, Double(seg.thickness * scale * 0.35))
            body += "  <line x1=\"\(x1)\" y1=\"\(y1)\" x2=\"\(x2)\" y2=\"\(y2)\""
            body += " stroke=\"#FFFFFF\" stroke-width=\"\(sw)\" stroke-linecap=\"round\"/>\n"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(W)" height="\(H)" style="background:#111">
        \(body)</svg>
        """
    }

    // MARK: - Exportación DXF (R12 compatible)

    func exportDXF(_ plan: FloorPlan) -> String {
        var s = "0\nSECTION\n2\nHEADER\n0\nENDSEC\n"
        s += "0\nSECTION\n2\nTABLES\n"
        s += "0\nTABLE\n2\nLAYER\n70\n1\n"
        s += "0\nLAYER\n2\nWALLS\n70\n0\n62\n7\n6\nCONTINUOUS\n"
        s += "0\nENDTAB\n0\nENDSEC\n"
        s += "0\nSECTION\n2\nENTITIES\n"
        for seg in plan.segments {
            s += "0\nLINE\n8\nWALLS\n62\n7\n"
            s += "10\n\(seg.start.x)\n20\n\(seg.start.y)\n30\n0.0\n"
            s += "11\n\(seg.end.x)\n21\n\(seg.end.y)\n31\n0.0\n"
        }
        s += "0\nENDSEC\n0\nEOF"
        return s
    }

    // MARK: - Exportación IFC (STEP, IFC4, simplificado)

    func exportIFC(_ plan: FloorPlan) -> String {
        let ts = Int(Date().timeIntervalSince1970)
        var s = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('mi-render FloorPlan Export'),'2;1');
        FILE_NAME('floorplan_\(ts).ifc','',('mi-render'),(''),'','','');
        FILE_SCHEMA(('IFC4'));
        ENDSEC;
        DATA;
        #1=IFCPROJECT('PROJ\(ts)',$,'mi-render',$,$,$,$,(#100),#200);
        #100=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-5,#101,$);
        #101=IFCAXIS2PLACEMENT3D(#102,$,$);
        #102=IFCCARTESIANPOINT((0.,0.,0.));
        #200=IFCUNITASSIGNMENT((#201));
        #201=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);
        """
        var idx = 300
        for seg in plan.segments {
            s += "\n#\(idx)=IFCWALLSTANDARDCASE('W\(idx)',$,'Wall',$,$,$,$,$,$);"
            idx += 1
            s += "\n#\(idx)=IFCCARTESIANPOINT((\(seg.start.x),\(seg.start.y),0.));"
            idx += 1
            s += "\n#\(idx)=IFCCARTESIANPOINT((\(seg.end.x),\(seg.end.y),0.));"
            idx += 1
        }
        s += "\nENDSEC;\nEND-ISO-10303-21;"
        return s
    }

    // MARK: - Exportación a archivo en Documents/

    @discardableResult
    func exportToFile(_ content: String, name: String) -> URL? {
        let url = docsDir.appendingPathComponent(name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("[FloorPlan] export error: \(error)")
            return nil
        }
    }
}
