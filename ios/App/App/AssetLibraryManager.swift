// AssetLibraryManager.swift
// Gestiona la biblioteca de assets 3D para insertar en la escena LiDAR.
// Soporta: .usdz, .reality, .obj, .glb
// Organiza por categoría, tipo de habitación y estilo de interior.
// Persiste los placements en Documents/projects/<id>/assetPlacements.json.

import UIKit
import RealityKit
import simd

// MARK: - AssetCategory

enum AssetCategory: String, CaseIterable, Codable {
    case furniture   = "furniture"
    case appliance   = "appliance"
    case door        = "door"
    case window      = "window"
    case light       = "light"
    case decoration  = "decoration"

    var displayName: String {
        switch self {
        case .furniture:  return "Mueble"
        case .appliance:  return "Electro"
        case .door:       return "Puerta"
        case .window:     return "Ventana"
        case .light:      return "Luz"
        case .decoration: return "Deco"
        }
    }

    var folderName: String { rawValue }

    var systemImage: String {
        switch self {
        case .furniture:  return "sofa.fill"
        case .appliance:  return "washer.fill"
        case .door:       return "door.left.hand.closed"
        case .window:     return "window.ceiling.closed"
        case .light:      return "lightbulb.fill"
        case .decoration: return "sparkles"
        }
    }
}

// MARK: - AssetRoomType

enum AssetRoomType: String, CaseIterable, Codable {
    case any         = "any"
    case livingRoom  = "livingRoom"
    case bedroom     = "bedroom"
    case kitchen     = "kitchen"
    case bathroom    = "bathroom"
    case office      = "office"
    case diningRoom  = "diningRoom"

    var displayName: String {
        switch self {
        case .any:        return "Todos"
        case .livingRoom: return "Salón"
        case .bedroom:    return "Dormitorio"
        case .kitchen:    return "Cocina"
        case .bathroom:   return "Baño"
        case .office:     return "Oficina"
        case .diningRoom: return "Comedor"
        }
    }
}

// MARK: - AssetStyle

enum AssetStyle: String, CaseIterable, Codable {
    case any          = "any"
    case modern       = "modern"
    case minimalist   = "minimalist"
    case industrial   = "industrial"
    case scandinavian = "scandinavian"
    case classic      = "classic"
    case rustic       = "rustic"

    var displayName: String {
        switch self {
        case .any:          return "Todos"
        case .modern:       return "Moderno"
        case .minimalist:   return "Minimalista"
        case .industrial:   return "Industrial"
        case .scandinavian: return "Escandinavo"
        case .classic:      return "Clásico"
        case .rustic:       return "Rústico"
        }
    }
}

// MARK: - Formato de archivo

enum AssetFormat: String, Codable {
    case usdz    = "usdz"
    case reality = "reality"
    case obj     = "obj"
    case glb     = "glb"

    var isNativeRealityKit: Bool {
        self == .usdz || self == .reality
    }
}

// MARK: - SceneAsset

struct SceneAsset: Identifiable, Hashable {
    let id:       UUID
    let name:     String
    let category: AssetCategory
    let roomType: AssetRoomType
    let style:    AssetStyle
    let format:   AssetFormat
    let fileURL:  URL

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SceneAsset, rhs: SceneAsset) -> Bool { lhs.id == rhs.id }
}

// MARK: - AssetPlacementRecord

struct AssetPlacementRecord: Codable {
    let placementID: UUID
    let assetName:   String
    let category:    AssetCategory

    // Posición y orientación como arrays de floats (simd_float4x4 → 16 floats)
    let positionX:   Float
    let positionY:   Float
    let positionZ:   Float

    // Quaternion de rotación
    let rotX: Float
    let rotY: Float
    let rotZ: Float
    let rotW: Float

    let scaleX: Float
    let scaleY: Float
    let scaleZ: Float

    var position: SIMD3<Float> { SIMD3(positionX, positionY, positionZ) }
    var rotation: simd_quatf   { simd_quatf(ix: rotX, iy: rotY, iz: rotZ, r: rotW) }
    var scale:    SIMD3<Float> { SIMD3(scaleX, scaleY, scaleZ) }
}

// MARK: - AssetLibraryManager

class AssetLibraryManager {

    static let shared = AssetLibraryManager()

    /// Todos los assets descubiertos en el bundle.
    private(set) var assets: [SceneAsset] = []

    private static let placementsFileName  = "assetPlacements.json"
    private static let supportedExtensions = ["usdz", "reality", "obj", "glb"]

    private init() {}

    // MARK: - Carga del catálogo

    /// Escanea Bundle.main/Assets3D/<category>/ y puebla `assets`.
    /// Infiere roomType y style desde el nombre del archivo:
    ///   sofa_modern_livingRoom.usdz → style=modern, roomType=livingRoom
    func loadAssets() {
        var discovered: [SceneAsset] = []
        let fm = FileManager.default

        for category in AssetCategory.allCases {
            guard let folderURL = Bundle.main.url(
                forResource: category.folderName,
                withExtension: nil,
                subdirectory: "Assets3D"
            ) else { continue }

            let contents = (try? fm.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents {
                let ext = url.pathExtension.lowercased()
                guard Self.supportedExtensions.contains(ext),
                      let format = AssetFormat(rawValue: ext) else { continue }

                let baseName  = url.deletingPathExtension().lastPathComponent
                let (room, style) = inferTags(from: baseName)

                discovered.append(SceneAsset(
                    id:       UUID(),
                    name:     baseName,
                    category: category,
                    roomType: room,
                    style:    style,
                    format:   format,
                    fileURL:  url
                ))
            }
        }

        assets = discovered
        print("[AssetLibraryManager] \(assets.count) assets cargados "
              + "(\(assets.filter { $0.format == .glb }.count) GLB, "
              + "\(assets.filter { $0.format == .usdz }.count) USDZ, "
              + "\(assets.filter { $0.format == .obj }.count) OBJ)")
    }

    // MARK: - loadAsset(name:)

    /// Carga un asset por nombre y devuelve la Entity lista para usar.
    func loadAsset(name: String,
                   completion: @escaping (Entity?) -> Void) {

        guard let asset = asset(named: name) else {
            print("[AssetLibraryManager] asset '\(name)' no encontrado")
            completion(nil)
            return
        }
        loadAsset(asset, completion: completion)
    }

    /// Carga un SceneAsset y devuelve la Entity.
    func loadAsset(_ asset: SceneAsset,
                   completion: @escaping (Entity?) -> Void) {

        let url = asset.fileURL

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let entity = try Entity.load(contentsOf: url)
                DispatchQueue.main.async { completion(entity) }
            } catch {
                print("[AssetLibraryManager] error cargando \(url.lastPathComponent): \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - insertAsset(into scene:)

    /// Inserta un asset (por nombre) en la escena en la posición indicada.
    @discardableResult
    func insertAsset(name: String,
                     at position: SIMD3<Float> = .zero,
                     into scene: RealityKit.Scene,
                     completion: ((AnchorEntity?) -> Void)? = nil) -> Bool {

        guard let asset = asset(named: name) else {
            completion?(nil)
            return false
        }
        insertAsset(asset, at: position, into: scene, completion: completion)
        return true
    }

    /// Inserta un SceneAsset en la escena en la posición indicada.
    func insertAsset(_ asset: SceneAsset,
                     at position: SIMD3<Float> = .zero,
                     into scene: RealityKit.Scene,
                     completion: ((AnchorEntity?) -> Void)? = nil) {

        loadAsset(asset) { entity in
            guard let entity = entity else {
                completion?(nil)
                return
            }
            let anchor = AnchorEntity(world: position)
            anchor.name = "asset_\(asset.id.uuidString)"
            anchor.addChild(entity)
            scene.addAnchor(anchor)
            completion?(anchor)

            NotificationCenter.default.post(
                name: .assetPlacedInScene,
                object: AssetPlacementInfo(asset: asset, anchor: anchor)
            )
            print("[AssetLibraryManager] insertado '\(asset.name)' en \(position)")
        }
    }

    // MARK: - Filtros

    /// Assets filtrados por categoría.
    func assets(in category: AssetCategory) -> [SceneAsset] {
        assets.filter { $0.category == category }
    }

    /// Assets filtrados por tipo de habitación (incluye .any).
    func assets(for roomType: AssetRoomType) -> [SceneAsset] {
        assets.filter { $0.roomType == roomType || $0.roomType == .any }
    }

    /// Assets filtrados por estilo (incluye .any).
    func assets(style: AssetStyle) -> [SceneAsset] {
        assets.filter { $0.style == style || $0.style == .any }
    }

    /// Filtro combinado: categoría + roomType + style.
    func assets(category: AssetCategory? = nil,
                roomType: AssetRoomType? = nil,
                style:    AssetStyle?    = nil) -> [SceneAsset] {
        assets.filter { asset in
            (category == nil || asset.category == category!) &&
            (roomType == nil || asset.roomType == roomType! || asset.roomType == .any) &&
            (style    == nil || asset.style    == style!    || asset.style    == .any)
        }
    }

    /// Devuelve el primer asset cuyo nombre coincide exactamente.
    func asset(named name: String) -> SceneAsset? {
        assets.first { $0.name == name }
    }

    // MARK: - Colocación en escena (alias legacy)

    func placeAsset(asset: SceneAsset,
                    at position: SIMD3<Float>,
                    in scene: RealityKit.Scene,
                    completion: ((AnchorEntity?) -> Void)? = nil) {
        insertAsset(asset, at: position, into: scene, completion: completion)
    }

    // MARK: - Inferencia de tags desde nombre de archivo

    private func inferTags(from name: String) -> (AssetRoomType, AssetStyle) {
        let lower = name.lowercased()

        let room: AssetRoomType = AssetRoomType.allCases.first {
            lower.contains($0.rawValue.lowercased()) && $0 != .any
        } ?? .any

        let style: AssetStyle = AssetStyle.allCases.first {
            lower.contains($0.rawValue.lowercased()) && $0 != .any
        } ?? .any

        return (room, style)
    }

    // MARK: - Persistencia de placements

    /// Guarda los placements activos en el directorio del proyecto.
    func savePlacements(_ records: [AssetPlacementRecord], toProjectFolder folder: URL) {
        let url = folder.appendingPathComponent(Self.placementsFileName)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Carga los placements persistidos para un proyecto.
    func loadPlacements(fromProjectFolder folder: URL) -> [AssetPlacementRecord] {
        let url = folder.appendingPathComponent(Self.placementsFileName)
        guard let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([AssetPlacementRecord].self, from: data)
        else { return [] }
        return records
    }

    /// Construye un AssetPlacementRecord a partir de un AnchorEntity colocado.
    func record(for anchor: AnchorEntity, asset: SceneAsset, scale: SIMD3<Float> = .one) -> AssetPlacementRecord {
        let pos = anchor.position(relativeTo: nil)
        let rot = anchor.orientation(relativeTo: nil)
        return AssetPlacementRecord(
            placementID: UUID(),
            assetName:   asset.name,
            category:    asset.category,
            positionX:   pos.x, positionY: pos.y, positionZ: pos.z,
            rotX: rot.imag.x, rotY: rot.imag.y, rotZ: rot.imag.z, rotW: rot.real,
            scaleX: scale.x, scaleY: scale.y, scaleZ: scale.z
        )
    }
}

// MARK: - AssetPlacementInfo (payload de notificación)

struct AssetPlacementInfo {
    let asset:  SceneAsset
    let anchor: AnchorEntity
}

// MARK: - Notification.Name

extension Notification.Name {
    /// Emitida cuando el usuario solicita colocar un asset (objeto: SceneAsset).
    static let assetPlacementRequested = Notification.Name("mi_render_assetPlacementRequested")

    /// Emitida cuando un asset queda colocado en la escena (objeto: AssetPlacementInfo).
    static let assetPlacedInScene      = Notification.Name("mi_render_assetPlacedInScene")
}
