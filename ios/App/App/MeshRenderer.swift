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
        // Alpha 1.0 — completamente opaco para confirmar que el mesh se renderiza.
        // Una vez confirmado, bajar a 0.5–0.7 para efecto semitransparente.
        switch classification {
        case .wall:
            mat.color = .init(tint: UIColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 1.0))
        case .floor:
            mat.color = .init(tint: UIColor(red: 0.10, green: 0.85, blue: 0.40, alpha: 1.0))
        case .ceiling:
            mat.color = .init(tint: UIColor(red: 0.70, green: 0.70, blue: 1.00, alpha: 1.0))
        case .table:
            mat.color = .init(tint: UIColor(red: 0.95, green: 0.65, blue: 0.10, alpha: 1.0))
        case .seat:
            mat.color = .init(tint: UIColor(red: 0.20, green: 0.40, blue: 0.90, alpha: 1.0))
        case .window:
            mat.color = .init(tint: UIColor(red: 0.20, green: 0.85, blue: 1.00, alpha: 1.0))
        case .door:
            mat.color = .init(tint: UIColor(red: 0.85, green: 0.45, blue: 0.10, alpha: 1.0))
        default:
            mat.color = .init(tint: UIColor(red: 0.20, green: 0.80, blue: 1.00, alpha: 1.0))
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
