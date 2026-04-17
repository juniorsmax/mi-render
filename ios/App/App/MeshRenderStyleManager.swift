// MeshRenderStyleManager.swift
// Gestiona el estilo de renderizado de la malla en SceneViewer.
// Aplica materiales RealityKit según el estilo activo y la categoría semántica.

import UIKit
import RealityKit

// MARK: - MeshRenderStyle

enum MeshRenderStyle: String, CaseIterable {
    case wireframe = "wireframe"
    case solid     = "solid"
    case semantic  = "semantic"
    case textured  = "textured"
    case xray      = "xray"

    var displayName: String {
        switch self {
        case .wireframe: return "Wire"
        case .solid:     return "Solid"
        case .semantic:  return "Sem."
        case .textured:  return "Tex."
        case .xray:      return "X-Ray"
        }
    }

    var systemImage: String {
        switch self {
        case .wireframe: return "square.on.square.intersection.dashed"
        case .solid:     return "cube.fill"
        case .semantic:  return "paintpalette.fill"
        case .textured:  return "photo.fill"
        case .xray:      return "waveform.and.magnifyingglass"
        }
    }
}

// MARK: - MeshRenderStyleManager

class MeshRenderStyleManager {

    static let shared = MeshRenderStyleManager()

    private static let defaultsKey = "mi_render_mesh_render_style"

    /// Estilo activo. Persiste en UserDefaults y emite .meshRenderStyleDidChange al cambiar.
    var currentStyle: MeshRenderStyle {
        didSet {
            guard currentStyle != oldValue else { return }
            UserDefaults.standard.set(currentStyle.rawValue, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: .meshRenderStyleDidChange, object: currentStyle)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        currentStyle = MeshRenderStyle(rawValue: saved) ?? .semantic
    }

    // MARK: - Aplicar estilo

    /// Aplica el material correspondiente al estilo activo a una ModelEntity.
    /// - Parameters:
    ///   - entity:   entidad objetivo
    ///   - category: categoría semántica (solo relevante para .semantic y .textured)
    func applyStyle(to entity: ModelEntity, category: MeshCategory?) {
        entity.model?.materials = [material(for: currentStyle, category: category)]
    }

    /// Devuelve el material RealityKit para un estilo y categoría dados.
    func material(for style: MeshRenderStyle, category: MeshCategory?) -> RealityKit.Material {
        switch style {

        case .wireframe:
            // RealityKit iOS no soporta wireframe nativo — aproximación con Unlit
            var m = UnlitMaterial()
            m.color = .init(tint: UIColor(red: 0.10, green: 0.95, blue: 0.55, alpha: 0.55))
            return m

        case .solid:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(white: 0.72, alpha: 1.0))
            m.roughness = .init(floatLiteral: 0.80)
            m.metallic  = .init(floatLiteral: 0.0)
            return m

        case .semantic:
            let color = category?.displayColor ?? UIColor(white: 0.45, alpha: 0.85)
            var m = UnlitMaterial()
            m.color = .init(tint: color)
            return m

        case .textured:
            if let cat = category,
               let sceneMat = MaterialLibraryManager.shared.material(for: cat) {
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: .white, texture: .init(sceneMat.baseColorTexture))
                m.roughness = .init(floatLiteral: sceneMat.roughness)
                m.metallic  = .init(floatLiteral: sceneMat.metallic)
                if let norm = sceneMat.normalTexture {
                    m.normal = .init(texture: .init(norm))
                }
                return m
            } else {
                // Sin categoría → solid neutro
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: UIColor(white: 0.78, alpha: 1.0))
                m.roughness = .init(floatLiteral: 0.70)
                m.metallic  = .init(floatLiteral: 0.0)
                return m
            }

        case .xray:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(red: 0.30, green: 0.70, blue: 1.0, alpha: 1.0))
            m.roughness = .init(floatLiteral: 0.0)
            m.metallic  = .init(floatLiteral: 0.0)
            m.blending   = .transparent(opacity: 0.25)
            return m
        }
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    static let meshRenderStyleDidChange = Notification.Name("mi_render_meshRenderStyleDidChange")
}
