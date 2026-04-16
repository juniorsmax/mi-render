// MaterialLibraryManager.swift
// Biblioteca de materiales PBR para superficies semánticas.
// Genera texturas programáticamente y aplica PhysicallyBasedMaterial
// a entidades de RealityKit según la categoría semántica.

import UIKit
import RealityKit

// MARK: - TexturePattern

private enum TexturePattern {
    case solid
    case woodGrain
    case tileGrid
    case concrete
}

// MARK: - SceneMaterial

struct SceneMaterial {
    let name:               String
    let category:           MeshCategory
    let baseColorTexture:   TextureResource
    let normalTexture:      TextureResource?
    let roughnessTexture:   TextureResource?
    let metallicTexture:    TextureResource?
    let roughness:          Float
    let metallic:           Float
}

// MARK: - MaterialLibraryManager

class MaterialLibraryManager {

    static let shared = MaterialLibraryManager()

    private(set) var materials: [SceneMaterial] = []
    private let defaultsKeyPrefix = "mi_render_mat_category_"

    private init() {
        loadDefaultMaterials()
    }

    // MARK: - Carga de materiales por defecto

    func loadDefaultMaterials() {
        materials = [
            make("wallPaintWhite",   .wall,      UIColor(white: 0.95, alpha: 1.0),                          r: 0.85, m: 0.00, pattern: .solid),
            make("wallPaintBeige",   .wall,      UIColor(red: 0.93, green: 0.87, blue: 0.75, alpha: 1.0),   r: 0.82, m: 0.00, pattern: .solid),
            make("woodFloorOak",     .floor,     UIColor(red: 0.72, green: 0.53, blue: 0.34, alpha: 1.0),   r: 0.60, m: 0.00, pattern: .woodGrain),
            make("woodFloorWalnut",  .floor,     UIColor(red: 0.42, green: 0.28, blue: 0.18, alpha: 1.0),   r: 0.55, m: 0.00, pattern: .woodGrain),
            make("ceramicTileWhite", .floor,     UIColor(white: 0.92, alpha: 1.0),                          r: 0.30, m: 0.05, pattern: .tileGrid),
            make("ceramicTileGray",  .floor,     UIColor(white: 0.60, alpha: 1.0),                          r: 0.32, m: 0.05, pattern: .tileGrid),
            make("concreteSurface",  .wall,      UIColor(white: 0.70, alpha: 1.0),                          r: 0.90, m: 0.00, pattern: .concrete),
            make("glassSurface",     .window,    UIColor(red: 0.70, green: 0.85, blue: 0.95, alpha: 0.55),  r: 0.05, m: 0.00, pattern: .solid),
            make("metalSurface",     .appliance, UIColor(white: 0.80, alpha: 1.0),                          r: 0.20, m: 0.85, pattern: .solid),
        ].compactMap { $0 }
    }

    // MARK: - API pública

    /// Devuelve el material asignado a una categoría (persistido en UserDefaults o por defecto).
    func material(for category: MeshCategory) -> SceneMaterial? {
        let key = defaultsKeyPrefix + category.rawValue
        if let saved = UserDefaults.standard.string(forKey: key),
           let mat = materials.first(where: { $0.name == saved }) {
            return mat
        }
        return defaultMaterial(for: category)
    }

    /// Guarda la preferencia de material para una categoría.
    func setMaterial(_ material: SceneMaterial, for category: MeshCategory) {
        let key = defaultsKeyPrefix + category.rawValue
        UserDefaults.standard.set(material.name, forKey: key)
    }

    /// Aplica un SceneMaterial a un ModelEntity usando PhysicallyBasedMaterial.
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

    // MARK: - Mapeo por defecto categoría → material

    private func defaultMaterial(for category: MeshCategory) -> SceneMaterial? {
        let name: String
        switch category {
        case .wall:      name = "wallPaintWhite"
        case .floor:     name = "woodFloorOak"
        case .ceiling:   name = "wallPaintWhite"
        case .window:    name = "glassSurface"
        case .appliance: name = "metalSurface"
        case .door:      name = "woodFloorWalnut"
        case .furniture: name = "woodFloorOak"
        case .unknown:   name = "concreteSurface"
        }
        return materials.first(where: { $0.name == name })
    }

    // MARK: - Generación de materiales

    private func make(_ name: String,
                      _ category: MeshCategory,
                      _ color: UIColor,
                      r roughness: Float,
                      m metallic: Float,
                      pattern: TexturePattern) -> SceneMaterial? {
        guard let baseColor = generateTexture(color: color, pattern: pattern, name: name) else {
            return nil
        }
        return SceneMaterial(
            name:             name,
            category:         category,
            baseColorTexture: baseColor,
            normalTexture:    nil,
            roughnessTexture: nil,
            metallicTexture:  nil,
            roughness:        roughness,
            metallic:         metallic
        )
    }

    // MARK: - Generación de texturas

    private func generateTexture(color: UIColor,
                                  pattern: TexturePattern,
                                  name: String) -> TextureResource? {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cgCtx = ctx.cgContext
            switch pattern {
            case .solid:
                color.setFill()
                cgCtx.fill(CGRect(origin: .zero, size: size))

            case .woodGrain:
                drawWoodGrain(in: cgCtx, size: size, color: color)

            case .tileGrid:
                drawTileGrid(in: cgCtx, size: size, color: color)

            case .concrete:
                drawConcrete(in: cgCtx, size: size, color: color)
            }
        }
        guard let cgImage = image.cgImage else { return nil }
        return try? TextureResource.generate(
            from: cgImage,
            withName: name,
            options: .init(semantic: .color)
        )
    }

    // MARK: - Dibujo de patrones

    private func drawWoodGrain(in ctx: CGContext, size: CGSize, color: UIColor) {
        // Fondo base
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))

        // Vetas horizontales más oscuras
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let darkColor = UIColor(red: red * 0.72, green: green * 0.72, blue: blue * 0.72, alpha: alpha)

        ctx.setLineWidth(1.5)
        darkColor.setStroke()

        var y: CGFloat = 6
        while y < size.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            // Leve ondulación en la veta
            let wave: CGFloat = 3.0 * sin(y * 0.15)
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
        // Fondo de la baldosa
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))

        // Líneas de lechada (grout)
        let tileSize: CGFloat = 48
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
        // Fondo
        color.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))

        // Ruido simulado con rectángulos semitransparentes
        let noiseCount = 300
        for _ in 0..<noiseCount {
            let nx = CGFloat.random(in: 0..<size.width)
            let ny = CGFloat.random(in: 0..<size.height)
            let nw = CGFloat.random(in: 1...6)
            let nh = CGFloat.random(in: 1...4)
            let brightness = CGFloat.random(in: -0.12...0.12)
            UIColor(white: 0.5 + brightness, alpha: 0.30).setFill()
            ctx.fill(CGRect(x: nx, y: ny, width: nw, height: nh))
        }
    }
}
