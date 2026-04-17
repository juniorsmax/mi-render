// AssetLibraryManager.swift
// Gestiona la biblioteca de assets 3D para insertar en la escena LiDAR.
// Escanea Bundle.main/Assets3D/<category>/ en busca de .usdz, .reality, .obj.
// Coloca assets como AnchorEntity(world:) en la escena RealityKit.
// Persiste los placements en Documents/Projects/<id>/assetPlacements.json.

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

// MARK: - SceneAsset

struct SceneAsset: Identifiable, Hashable {
    let id:       UUID
    let name:     String
    let category: AssetCategory
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

    private static let placementsFileName = "assetPlacements.json"
    private static let supportedExtensions = ["usdz", "reality", "obj"]

    private init() {}

    // MARK: - Carga de assets del bundle

    /// Escanea Bundle.main/Assets3D/<category>/ y puebla `assets`.
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
                guard Self.supportedExtensions.contains(ext) else { continue }
                let assetName = url.deletingPathExtension().lastPathComponent
                discovered.append(SceneAsset(
                    id:       UUID(),
                    name:     assetName,
                    category: category,
                    fileURL:  url
                ))
            }
        }

        assets = discovered
    }

    /// Devuelve el primer asset cuyo nombre coincide exactamente.
    func asset(named name: String) -> SceneAsset? {
        assets.first { $0.name == name }
    }

    // MARK: - Colocación en escena

    /// Carga el asset en background y lo añade a la escena en main thread.
    /// - Parameters:
    ///   - asset:    asset a colocar
    ///   - position: coordenadas mundo 3D
    ///   - scene:    escena RealityKit destino
    ///   - completion: devuelve el AnchorEntity colocado (o nil si falla)
    func placeAsset(
        asset:      SceneAsset,
        at position: SIMD3<Float>,
        in scene:   RealityKit.Scene,
        completion: ((AnchorEntity?) -> Void)? = nil
    ) {
        let fileURL = asset.fileURL

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let entity = try Entity.load(contentsOf: fileURL)
                DispatchQueue.main.async {
                    let anchor = AnchorEntity(world: position)
                    anchor.name = "asset_\(asset.name)"
                    anchor.addChild(entity)
                    scene.addAnchor(anchor)
                    completion?(anchor)

                    NotificationCenter.default.post(
                        name: .assetPlacedInScene,
                        object: AssetPlacementInfo(asset: asset, anchor: anchor)
                    )
                }
            } catch {
                DispatchQueue.main.async { completion?(nil) }
            }
        }
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
