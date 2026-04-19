// MeshRenderer.swift
// Renderizado del mesh LiDAR como overlay semitransparente coloreado por clasificación.
// Usa SimpleMaterial con alpha bajo (0.30–0.35) para que la cámara se vea claramente
// detrás de los colores. Misma técnica que Polycam / Canvas / RoomPlan demo de Apple.

import RealityKit
import ARKit

class MeshRenderer {

    static let shared = MeshRenderer()

    // MARK: - Material por clasificación

    func material(for classification: ARMeshClassification) -> UnlitMaterial {
        // Color tint con alpha=1.0, transparencia via blending = .transparent
        // blending .transparent desactiva depth write → la cámara se ve detrás
        var mat = UnlitMaterial()
        let opacity: Float
        let tint: UIColor
        switch classification {
        case .wall:
            tint = UIColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1.0); opacity = 0.25
        case .floor:
            tint = UIColor(red: 0.10, green: 0.88, blue: 0.45, alpha: 1.0); opacity = 0.22
        case .ceiling:
            tint = UIColor(red: 0.55, green: 0.75, blue: 1.00, alpha: 1.0); opacity = 0.18
        case .table:
            tint = UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 1.0); opacity = 0.28
        case .seat:
            tint = UIColor(red: 0.65, green: 0.35, blue: 1.00, alpha: 1.0); opacity = 0.28
        case .window:
            tint = UIColor(red: 0.15, green: 0.90, blue: 1.00, alpha: 1.0); opacity = 0.25
        case .door:
            tint = UIColor(red: 1.00, green: 0.75, blue: 0.10, alpha: 1.0); opacity = 0.28
        default:
            tint = UIColor(red: 0.20, green: 0.80, blue: 1.00, alpha: 1.0); opacity = 0.18
        }
        mat.color    = .init(tint: tint)
        mat.blending = .transparent(opacity: .init(floatLiteral: opacity))
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
