// FloorPlanOverlayEntity.swift
// Entidad RealityKit que renderiza el plano 2D como líneas (cajas aplanadas).
//
// Uso:
//   let overlay = FloorPlanOverlayEntity()
//   overlay.build(from: plan)
//   overlay.position = SIMD3<Float>(x, 0.02, z)
//   anchorEntity.addChild(overlay)

import RealityKit
import simd
import UIKit

class FloorPlanOverlayEntity: Entity {

    // MARK: - Construcción desde FloorPlan

    /// Reconstruye todas las entidades hijas a partir del plan generado.
    func build(from plan: FloorPlan, floorY: Float = 0.02) {
        // Eliminar hijos anteriores de forma segura
        Array(children).forEach { $0.removeFromParent() }
        guard !plan.segments.isEmpty else { return }

        // Segmentos de pared (blanco)
        for seg in plan.segments {
            let entity = makeLineEntity(
                segment: seg,
                floorY:  floorY,
                color:   UIColor.white
            )
            addChild(entity)
        }

        // Contorno del perímetro (azul semitransparente)
        addBoundsFrame(plan: plan, floorY: floorY + 0.005)
    }

    // MARK: - Caja aplanada para una línea de pared

    private func makeLineEntity(segment: FloorSegment,
                                 floorY:  Float,
                                 color:   UIColor) -> ModelEntity {
        let len = max(segment.length, 0.01)

        let boxW: Float = len
        let boxH: Float = 0.03
        let boxD: Float = max(segment.thickness * 0.25, 0.025)

        let mesh = MeshResource.generateBox(size: SIMD3<Float>(boxW, boxH, boxD))
        var mat  = UnlitMaterial()
        mat.color = .init(tint: color)

        let entity   = ModelEntity(mesh: mesh, materials: [mat])
        entity.position = SIMD3<Float>(segment.midpoint.x, floorY, segment.midpoint.y)

        // Rotar para alinear con dirección del segmento (eje Y hacia arriba, rotación en XZ)
        let angle = atan2(segment.end.y - segment.start.y,
                          segment.end.x - segment.start.x)
        entity.transform.rotation = simd_quatf(angle: angle, axis: [0, 1, 0])

        return entity
    }

    // MARK: - Bounding rect del perímetro

    private func addBoundsFrame(plan: FloorPlan, floorY: Float) {
        let mn = plan.minBounds
        let mx = plan.maxBounds
        guard (mx.x - mn.x) > 0.1, (mx.y - mn.y) > 0.1 else { return }

        let frameColor = UIColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.45)
        let corners: [(SIMD2<Float>, SIMD2<Float>)] = [
            (SIMD2(mn.x, mn.y), SIMD2(mx.x, mn.y)),
            (SIMD2(mx.x, mn.y), SIMD2(mx.x, mx.y)),
            (SIMD2(mx.x, mx.y), SIMD2(mn.x, mx.y)),
            (SIMD2(mn.x, mx.y), SIMD2(mn.x, mn.y)),
        ]
        for (s, e) in corners {
            let seg = FloorSegment(start: s, end: e, thickness: 0.04)
            let entity = makeLineEntity(segment: seg, floorY: floorY, color: frameColor)
            addChild(entity)
        }
    }

    // MARK: - Actualización dinámica de color de paredes

    func setWallColor(_ color: UIColor) {
        for child in children {
            guard let model = child as? ModelEntity else { continue }
            var mat = UnlitMaterial()
            mat.color = .init(tint: color)
            model.model?.materials = [mat]
        }
    }
}
