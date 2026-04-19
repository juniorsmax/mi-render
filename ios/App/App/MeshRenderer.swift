// MeshRenderer.swift
// Renderizado del mesh LiDAR como overlay semi-transparente coloreado por clasificación.
//
// REGLAS DE RENDERIZADO (equivalente a la recomendación de RoomPlan overlays):
//   • blending = .transparent  → NO escribe al depth buffer (depthWriteEnabled = false)
//     Esto evita que la malla "bloquee" el feed de cámara que hay debajo.
//   • Alpha 0.55–0.75           → visible con claridad sobre ARView transparente
//   • renderingOrder en entidad → se aplica en ScanManager.renderMesh()
//     La entidad usa renderingOrder = 100 (encima del fondo AR, debajo de la UI)

import RealityKit
import ARKit

class MeshRenderer {

    static let shared = MeshRenderer()

    // MARK: - Material Unlit por clasificación (overlay semitransparente)

    func material(for classification: ARMeshClassification) -> UnlitMaterial {
        let tint: UIColor
        switch classification {
        case .wall:
            tint = UIColor(red: 0.40, green: 0.60, blue: 1.00, alpha: 0.70)
        case .floor:
            tint = UIColor(red: 0.25, green: 0.90, blue: 0.55, alpha: 0.65)
        case .ceiling:
            tint = UIColor(red: 0.80, green: 0.80, blue: 1.00, alpha: 0.55)
        case .table:
            tint = UIColor(red: 0.95, green: 0.70, blue: 0.20, alpha: 0.75)
        case .seat:
            tint = UIColor(red: 0.30, green: 0.50, blue: 0.95, alpha: 0.75)
        case .window:
            tint = UIColor(red: 0.40, green: 0.90, blue: 1.00, alpha: 0.60)
        case .door:
            tint = UIColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 0.75)
        default:
            tint = UIColor(red: 0.35, green: 0.85, blue: 1.00, alpha: 0.60)
        }
        // blending .transparent → RealityKit no escribe al depth buffer,
        // la malla se superpone sin "tapar" la cámara AR.
        var mat = UnlitMaterial()
        mat.color = .init(tint: tint)
        mat.blending = .transparent(opacity: .init(floatLiteral: Float(tint.cgColor.alpha ?? 0.65)))
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
