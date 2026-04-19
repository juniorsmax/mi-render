// MeshRenderer.swift
// Renderizado del mesh LiDAR como overlay semi-transparente coloreado por clasificación.
// UnlitMaterial respeta el alpha del color tint por defecto — NO añadir blending explícito:
// blending = .transparent hace que RealityKit ignore el color.alpha y deje el material invisible.

import RealityKit
import ARKit

class MeshRenderer {

    static let shared = MeshRenderer()

    // MARK: - Material Unlit por clasificación (overlay semitransparente)

    func material(for classification: ARMeshClassification) -> UnlitMaterial {
        var mat = UnlitMaterial()
        switch classification {
        case .wall:
            mat.color = .init(tint: UIColor(red: 0.40, green: 0.60, blue: 1.00, alpha: 0.75))
        case .floor:
            mat.color = .init(tint: UIColor(red: 0.25, green: 0.90, blue: 0.55, alpha: 0.70))
        case .ceiling:
            mat.color = .init(tint: UIColor(red: 0.80, green: 0.80, blue: 1.00, alpha: 0.60))
        case .table:
            mat.color = .init(tint: UIColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 0.80))
        case .seat:
            mat.color = .init(tint: UIColor(red: 0.30, green: 0.50, blue: 0.95, alpha: 0.80))
        case .window:
            mat.color = .init(tint: UIColor(red: 0.40, green: 0.90, blue: 1.00, alpha: 0.65))
        case .door:
            mat.color = .init(tint: UIColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 0.80))
        default:
            mat.color = .init(tint: UIColor(red: 0.35, green: 0.85, blue: 1.00, alpha: 0.65))
        }
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
