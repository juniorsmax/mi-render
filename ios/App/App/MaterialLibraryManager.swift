// MaterialLibraryManager.swift
// Biblioteca de materiales PBR para superficies semánticas AR.
// Expone dos APIs ortogonales:
//
//   API por tipo (nueva):
//     material(for type: MaterialType) → SceneMaterial
//     applyMaterial(type: MaterialType, to: ModelEntity)
//
//   API por categoría semántica (legacy, mantenida para compatibilidad):
//     material(for category: MeshCategory) → SceneMaterial?
//     applyMaterial(_ material: SceneMaterial, to: ModelEntity)
//
// Runtime switching:
//   setVariant(_:for:) cambia la variante activa de un MaterialType.
//   Emite .materialTypeDidChange para que la UI reaccione.

import UIKit
import RealityKit

// MARK: - MaterialType

enum MaterialType: String, CaseIterable {
    case wood     = "wood"
    case concrete = "concrete"
    case tile     = "tile"
    case glass    = "glass"
    case metal    = "metal"
    case paint    = "paint"

    // MARK: Metadatos de presentación

    var displayName: String {
        switch self {
        case .wood:     return "Madera"
        case .concrete: return "Hormigón"
        case .tile:     return "Cerámica"
        case .glass:    return "Vidrio"
        case .metal:    return "Metal"
        case .paint:    return "Pintura"
        }
    }

    var systemImage: String {
        switch self {
        case .wood:     return "square.3.layers.3d"
        case .concrete: return "square.fill.on.square.fill"
        case .tile:     return "square.grid.2x2.fill"
        case .glass:    return "square.dotted"
        case .metal:    return "bolt.circle.fill"
        case .paint:    return "paintbrush.fill"
        }
    }

    /// Color representativo para previsualización en UI.
    var previewColor: UIColor {
        switch self {
        case .wood:     return UIColor(red: 0.72, green: 0.53, blue: 0.34, alpha: 1.0)
        case .concrete: return UIColor(white: 0.65, alpha: 1.0)
        case .tile:     return UIColor(white: 0.90, alpha: 1.0)
        case .glass:    return UIColor(red: 0.70, green: 0.87, blue: 0.95, alpha: 0.60)
        case .metal:    return UIColor(white: 0.78, alpha: 1.0)
        case .paint:    return UIColor(red: 0.94, green: 0.88, blue: 0.76, alpha: 1.0)
        }
    }

    /// Variantes disponibles (nombres de SceneMaterial) para este tipo.
    var variantNames: [String] {
        switch self {
        case .wood:     return ["woodFloorOak", "woodFloorWalnut"]
        case .concrete: return ["concreteSurface"]
        case .tile:     return ["ceramicTileWhite", "ceramicTileGray"]
        case .glass:    return ["glassSurface"]
        case .metal:    return ["metalSurface", "metalBrushed"]
        case .paint:    return ["wallPaintWhite", "wallPaintBeige"]
        }
    }

    /// Clave UserDefaults para la variante activa de este tipo.
    var defaultsKey: String { "mi_render_mattype_\(rawValue)" }
}

// MARK: - TexturePattern (privado)

private enum TexturePattern {
    case solid
    case woodGrain
    case tileGrid
    case concrete
    case brushedMetal
}

// MARK: - SceneMaterial

struct SceneMaterial {
    let name:               String
    let type:               MaterialType
    let category:           MeshCategory        // mapeo semántico (para API legacy)
    let baseColorTexture:   TextureResource
    let normalTexture:      TextureResource?
    let roughnessTexture:   TextureResource?
    let metallicTexture:    TextureResource?
    let roughness:          Float
    let metallic:           Float
    let previewColor:       UIColor
}

// MARK: - MaterialLibraryManager

class MaterialLibraryManager {

    static let shared = MaterialLibraryManager()

    /// Catálogo completo de materiales generados.
    private(set) var materials: [SceneMaterial] = []

    // UserDefaults key prefix para API legacy (por categoría semántica)
    private let legacyKeyPrefix = "mi_render_mat_category_"

    private init() {
        loadDefaultMaterials()
    }

    // MARK: - API por MaterialType (nueva)

    /// Devuelve el SceneMaterial activo para un MaterialType.
    /// Respeta la variante seleccionada por el usuario (UserDefaults).
    func material(for type: MaterialType) -> SceneMaterial {
        let savedName = UserDefaults.standard.string(forKey: type.defaultsKey)
        if let name = savedName,
           let mat = materials.first(where: { $0.name == name && $0.type == type }) {
            return mat
        }
        // Fallback: primera variante del tipo
        return materials.first(where: { $0.type == type })
            ?? makeFallbackMaterial(type: type)
    }

    /// Aplica el material del tipo indicado a un ModelEntity.
    func applyMaterial(type: MaterialType, to entity: ModelEntity) {
        applyMaterial(material(for: type), to: entity)
    }

    /// Cambia la variante activa de un MaterialType en runtime.
    /// Emite `.materialTypeDidChange` con el tipo como `object`.
    func setVariant(_ variantName: String, for type: MaterialType) {
        guard materials.contains(where: { $0.name == variantName && $0.type == type }) else { return }
        UserDefaults.standard.set(variantName, forKey: type.defaultsKey)
        NotificationCenter.default.post(name: .materialTypeDidChange, object: type)
    }

    /// Devuelve todas las variantes disponibles para un MaterialType.
    func variants(for type: MaterialType) -> [SceneMaterial] {
        materials.filter { $0.type == type }
    }

    // MARK: - API por MeshCategory (legacy)

    /// Devuelve el material asignado a una categoría semántica.
    func material(for category: MeshCategory) -> SceneMaterial? {
        let key = legacyKeyPrefix + category.rawValue
        if let saved = UserDefaults.standard.string(forKey: key),
           let mat = materials.first(where: { $0.name == saved }) {
            return mat
        }
        return defaultMaterial(for: category)
    }

    /// Guarda la preferencia de material para una categoría semántica.
    func setMaterial(_ material: SceneMaterial, for category: MeshCategory) {
        UserDefaults.standard.set(material.name, forKey: legacyKeyPrefix + category.rawValue)
    }

    /// Aplica un SceneMaterial a un ModelEntity.
    func applyMaterial(_ material: SceneMaterial, to entity: ModelEntity) {
        var pbr = PhysicallyBasedMaterial()
        pbr.baseColor = .init(tint: .white, texture: .init(material.baseColorTexture))
        pbr.roughness = .init(floatLiteral: material.roughness)
        pbr.metallic  = .init(floatLiteral: material.metallic)
        if let norm = material.normalTexture {
            pbr.normal = .init(texture: .init(norm))
        }
        entity.model?.materials = [pbr]
    }

    // MARK: - Carga de materiales por defecto

    func loadDefaultMaterials() {
        materials = [
            // MARK: Wood
            make("woodFloorOak",    .wood,     .floor,
                 UIColor(red: 0.72, green: 0.53, blue: 0.34, alpha: 1.0), r: 0.60, m: 0.00, pattern: .woodGrain),
            make("woodFloorWalnut", .wood,     .floor,
                 UIColor(red: 0.42, green: 0.28, blue: 0.18, alpha: 1.0), r: 0.55, m: 0.00, pattern: .woodGrain),

            // MARK: Concrete
            make("concreteSurface", .concrete, .wall,
                 UIColor(white: 0.70, alpha: 1.0),                         r: 0.90, m: 0.00, pattern: .concrete),

            // MARK: Tile
            make("ceramicTileWhite", .tile,    .floor,
                 UIColor(white: 0.92, alpha: 1.0),                         r: 0.30, m: 0.05, pattern: .tileGrid),
            make("ceramicTileGray",  .tile,    .floor,
                 UIColor(white: 0.60, alpha: 1.0),                         r: 0.32, m: 0.05, pattern: .tileGrid),

            // MARK: Glass
            make("glassSurface",     .glass,   .window,
                 UIColor(red: 0.70, green: 0.85, blue: 0.95, alpha: 0.55), r: 0.05, m: 0.00, pattern: .solid),

            // MARK: Metal
            make("metalSurface",     .metal,   .appliance,
                 UIColor(white: 0.80, alpha: 1.0),                         r: 0.20, m: 0.85, pattern: .solid),
            make("metalBrushed",     .metal,   .appliance,
                 UIColor(white: 0.72, alpha: 1.0),                         r: 0.35, m: 0.80, pattern: .brushedMetal),

            // MARK: Paint
            make("wallPaintWhite",  .paint,    .wall,
                 UIColor(white: 0.95, alpha: 1.0),                         r: 0.85, m: 0.00, pattern: .solid),
            make("wallPaintBeige",  .paint,    .wall,
                 UIColor(red: 0.93, green: 0.87, blue: 0.75, alpha: 1.0),  r: 0.82, m: 0.00, pattern: .solid),
        ].compactMap { $0 }
    }

    // MARK: - Mapeo categoría semántica → material por defecto

    private func defaultMaterial(for category: MeshCategory) -> SceneMaterial? {
        switch category {
        case .wall:      return material(for: .paint)
        case .floor:     return material(for: .wood)
        case .ceiling:   return material(for: .paint)
        case .window:    return material(for: .glass)
        case .appliance: return material(for: .metal)
        case .door:      return materials.first(where: { $0.name == "woodFloorWalnut" })
        case .furniture: return material(for: .wood)
        case .unknown:   return material(for: .concrete)
        }
    }

    // MARK: - Fábrica de SceneMaterial

    private func make(_ name:     String,
                      _ type:     MaterialType,
                      _ category: MeshCategory,
                      _ color:    UIColor,
                      r roughness: Float,
                      m metallic:  Float,
                      pattern:     TexturePattern) -> SceneMaterial? {
        guard let baseColor = generateTexture(color: color, pattern: pattern, name: name) else {
            return nil
        }
        return SceneMaterial(
            name:             name,
            type:             type,
            category:         category,
            baseColorTexture: baseColor,
            normalTexture:    nil,
            roughnessTexture: nil,
            metallicTexture:  nil,
            roughness:        roughness,
            metallic:         metallic,
            previewColor:     color
        )
    }

    /// Devuelve un SceneMaterial mínimo sin textura cuando el catálogo falla.
    private func makeFallbackMaterial(type: MaterialType) -> SceneMaterial {
        let size  = CGSize(width: 4, height: 4)
        let rdr   = UIGraphicsImageRenderer(size: size)
        let image = rdr.image { ctx in
            type.previewColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let tex = (image.cgImage.flatMap {
            try? TextureResource.generate(from: $0, withName: type.rawValue + "_fallback",
                                          options: .init(semantic: .color))
        })!

        return SceneMaterial(
            name: type.rawValue + "_fallback",
            type: type,
            category: .unknown,
            baseColorTexture: tex,
            normalTexture: nil, roughnessTexture: nil, metallicTexture: nil,
            roughness: 0.75, metallic: 0.0,
            previewColor: type.previewColor
        )
    }

    // MARK: - Generación de texturas

    private func generateTexture(color: UIColor,
                                  pattern: TexturePattern,
                                  name: String) -> TextureResource? {
        let size = CGSize(width: 256, height: 256)
        let rdr  = UIGraphicsImageRenderer(size: size)
        let image = rdr.image { ctx in
            let cgCtx = ctx.cgContext
            switch pattern {
            case .solid:        drawSolid(in: cgCtx, size: size, color: color)
            case .woodGrain:    drawWoodGrain(in: cgCtx, size: size, color: color)
            case .tileGrid:     drawTileGrid(in: cgCtx, size: size, color: color)
            case .concrete:     drawConcrete(in: cgCtx, size: size, color: color)
            case .brushedMetal: drawBrushedMetal(in: cgCtx, size: size, color: color)
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource.generate(
            from: cgImage,
            withName: name,
            options: .init(semantic: .color)
        )
    }

    // MARK: - Patrones de textura

    private func drawSolid(in ctx: CGContext, size: CGSize, color: UIColor) {
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
    }

    private func drawWoodGrain(in ctx: CGContext, size: CGSize, color: UIColor) {
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let dark = UIColor(red: r * 0.72, green: g * 0.72, blue: b * 0.72, alpha: a)
        ctx.setLineWidth(1.5)
        dark.setStroke()

        var y: CGFloat = 6
        while y < size.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            let wave = 3.0 * sin(y * 0.15)
            ctx.addCurve(
                to: CGPoint(x: size.width, y: y + wave),
                control1: CGPoint(x: size.width * 0.33, y: y - wave * 0.5),
                control2: CGPoint(x: size.width * 0.66, y: y + wave)
            )
            ctx.strokePath()
            y += CGFloat.random(in: 7...14)
        }
    }

    private func drawTileGrid(in ctx: CGContext, size: CGSize, color: UIColor) {
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        let tileSize: CGFloat  = 48
        let groutWidth: CGFloat = 4
        UIColor(white: 0.78, alpha: 0.9).setFill()
        var x: CGFloat = tileSize
        while x < size.width {
            ctx.fill(CGRect(x: x - groutWidth * 0.5, y: 0, width: groutWidth, height: size.height))
            x += tileSize
        }
        var y: CGFloat = tileSize
        while y < size.height {
            ctx.fill(CGRect(x: 0, y: y - groutWidth * 0.5, width: size.width, height: groutWidth))
            y += tileSize
        }
    }

    private func drawConcrete(in ctx: CGContext, size: CGSize, color: UIColor) {
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        for _ in 0..<300 {
            let brightness = CGFloat.random(in: -0.12...0.12)
            UIColor(white: 0.5 + brightness, alpha: 0.30).setFill()
            ctx.fill(CGRect(
                x: CGFloat.random(in: 0..<size.width),
                y: CGFloat.random(in: 0..<size.height),
                width: CGFloat.random(in: 1...6),
                height: CGFloat.random(in: 1...4)
            ))
        }
    }

    private func drawBrushedMetal(in ctx: CGContext, size: CGSize, color: UIColor) {
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setLineWidth(0.8)
        var y: CGFloat = 0
        while y < size.height {
            let alpha = CGFloat.random(in: 0.04...0.18)
            UIColor(white: CGFloat.random(in: 0.6...1.0), alpha: alpha).setStroke()
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y + CGFloat.random(in: -0.5...0.5)))
            ctx.strokePath()
            y += CGFloat.random(in: 1.0...2.5)
        }
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    /// Emitida cuando cambia la variante activa de un MaterialType (object: MaterialType).
    static let materialTypeDidChange = Notification.Name("mi_render_materialTypeDidChange")
}
