// MeshRenderer.swift
// Renderizado del mesh en pantalla con materiales PBR.
// Permite visualizar la reconstrucción 3D con texturas físicas realistas.

import RealityKit
import ARKit

class MeshRenderer {

    static let shared = MeshRenderer()

    // MARK: - Material PBR base

    func createMaterial(roughness: Float = 0.5,
                        metallic: Float = 0.2,
                        color: UIColor = .white) -> PhysicallyBasedMaterial {

        var material = PhysicallyBasedMaterial()
        material.roughness = .float(roughness)
        material.metallic  = .float(metallic)
        material.baseColor = .init(tint: color)

        return material
    }

    // MARK: - Material con color según clasificación

    func material(for classification: ARMeshClassification) -> PhysicallyBasedMaterial {

        var mat = PhysicallyBasedMaterial()
        mat.roughness = .float(0.8)
        mat.metallic  = .float(0.0)

        switch classification {
        case .wall:
            mat.baseColor = .init(tint: UIColor(red: 0.8, green: 0.8, blue: 0.9, alpha: 0.6))
        case .floor:
            mat.baseColor = .init(tint: UIColor(red: 0.6, green: 0.5, blue: 0.4, alpha: 0.6))
        case .ceiling:
            mat.baseColor = .init(tint: UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.4))
        case .table:
            mat.baseColor = .init(tint: UIColor(red: 0.7, green: 0.5, blue: 0.3, alpha: 0.8))
        case .seat:
            mat.baseColor = .init(tint: UIColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 0.8))
        case .window:
            mat.baseColor = .init(tint: UIColor(red: 0.5, green: 0.8, blue: 0.9, alpha: 0.4))
        case .door:
            mat.baseColor = .init(tint: UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.8))
        default:
            mat.baseColor = .init(tint: UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.3))
        }

        return mat
    }

    // MARK: - Material wireframe (para debug)

    func wireframeMaterial() -> UnlitMaterial {
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 0.6))
        return mat
    }

    // MARK: - Entidad de mesh para RealityKit

    func meshEntity(from mesh: MeshResource,
                    classification: ARMeshClassification = .none) -> ModelEntity {

        let material = self.material(for: classification)
        return ModelEntity(mesh: mesh, materials: [material])
    }
}
