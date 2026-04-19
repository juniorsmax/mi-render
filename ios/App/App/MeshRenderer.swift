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
        // UnlitMaterial: no depende de luz, el color siempre es visible.
        // Alpha 0.40 = cámara visible + color identificable por superficie.
        // Colores estilo Polycam/Canvas: cada superficie tiene color único y vibrante.
        var mat = UnlitMaterial()
        switch classification {
        case .wall:
            mat.color = .init(tint: UIColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 0.22))
        case .floor:
            mat.color = .init(tint: UIColor(red: 0.10, green: 0.88, blue: 0.45, alpha: 0.20))
        case .ceiling:
            mat.color = .init(tint: UIColor(red: 0.55, green: 0.75, blue: 1.00, alpha: 0.18))
        case .table:
            mat.color = .init(tint: UIColor(red: 1.00, green: 0.55, blue: 0.10, alpha: 0.25))
        case .seat:
            mat.color = .init(tint: UIColor(red: 0.65, green: 0.35, blue: 1.00, alpha: 0.25))
        case .window:
            mat.color = .init(tint: UIColor(red: 0.15, green: 0.90, blue: 1.00, alpha: 0.22))
        case .door:
            mat.color = .init(tint: UIColor(red: 1.00, green: 0.75, blue: 0.10, alpha: 0.25))
        default:
            mat.color = .init(tint: UIColor(red: 0.20, green: 0.80, blue: 1.00, alpha: 0.18))
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
