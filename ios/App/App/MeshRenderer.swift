// MeshRenderer.swift
// Renderizado del mesh LiDAR como overlay semitransparente coloreado por clasificación.
// Usa SimpleMaterial con alpha bajo (0.30–0.35) para que la cámara se vea claramente
// detrás de los colores. Misma técnica que Polycam / Canvas / RoomPlan demo de Apple.

import RealityKit
import ARKit

class MeshRenderer {

    static let shared = MeshRenderer()

    // MARK: - Material por clasificación

    func material(for classification: ARMeshClassification) -> SimpleMaterial {
        // Alpha 0.30–0.35: la cámara se ve claramente detrás, el color identifica la superficie.
        // roughness=1 + metallic=0 = apariencia mate sin reflejos especulares.
        let alpha: CGFloat = 0.42
        let tint: UIColor
        switch classification {
        case .wall:    tint = UIColor(red: 0.20, green: 0.50, blue: 1.00, alpha: alpha)
        case .floor:   tint = UIColor(red: 0.10, green: 0.85, blue: 0.40, alpha: alpha)
        case .ceiling: tint = UIColor(red: 0.65, green: 0.65, blue: 1.00, alpha: alpha * 0.8)
        case .table:   tint = UIColor(red: 0.95, green: 0.60, blue: 0.10, alpha: alpha)
        case .seat:    tint = UIColor(red: 0.25, green: 0.45, blue: 0.95, alpha: alpha)
        case .window:  tint = UIColor(red: 0.20, green: 0.85, blue: 1.00, alpha: alpha)
        case .door:    tint = UIColor(red: 0.85, green: 0.40, blue: 0.10, alpha: alpha)
        default:       tint = UIColor(red: 0.20, green: 0.75, blue: 1.00, alpha: alpha * 0.8)
        }
        var mat = SimpleMaterial()
        mat.color     = .init(tint: tint, texture: nil)
        mat.roughness = .init(floatLiteral: 1.0)
        mat.metallic  = .init(floatLiteral: 0.0)
        return mat
    }

    // MARK: - Material PBR para exportación/visualización offline

    func pbr(roughness: Float = 0.8,
             metallic: Float = 0.0,
             color: UIColor = .white) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.roughness  = .init(floatLiteral: roughness)
        mat.metallic   = .init(floatLiteral: metallic)
        mat.baseColor  = .init(tint: color)
        return mat
    }

    // MARK: - Material wireframe (debug)

    func wireframeMaterial() -> UnlitMaterial {
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 0.6))
        return mat
    }

    // MARK: - ModelEntity directo

    func meshEntity(from mesh: MeshResource,
                    classification: ARMeshClassification = .none) -> ModelEntity {
        ModelEntity(mesh: mesh, materials: [material(for: classification)])
    }
}
