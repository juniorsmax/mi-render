// SceneLayerManager.swift
// Sistema de capas de visualización post-escaneo.
// Gestiona el modo activo, persiste en UserDefaults y notifica cambios.
// Reemplaza SceneModeManager como control primario de capas.

import Foundation
import UIKit

// MARK: - SceneLayerMode

enum SceneLayerMode: String, CaseIterable {
    case meshRaw       = "meshRaw"
    case meshSemantic  = "meshSemantic"
    case floorplan2D   = "floorplan2D"
    case floorplan3D   = "floorplan3D"
    case walkthrough   = "walkthrough"
    case panoramaNodes = "panoramaNodes"

    // MARK: Etiqueta del botón UI

    var displayName: String {
        switch self {
        case .meshRaw:       return "Mesh"
        case .meshSemantic:  return "Semantic"
        case .floorplan2D:   return "2D Plan"
        case .floorplan3D:   return "3D Plan"
        case .walkthrough:   return "Walkthrough"
        case .panoramaNodes: return "Nodes"
        }
    }

    // MARK: SF Symbol

    var systemImage: String {
        switch self {
        case .meshRaw:       return "cube.fill"
        case .meshSemantic:  return "paintpalette"
        case .floorplan2D:   return "map"
        case .floorplan3D:   return "building.2.fill"
        case .walkthrough:   return "play.circle.fill"
        case .panoramaNodes: return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - SceneLayerManager

class SceneLayerManager {

    static let shared = SceneLayerManager()

    private static let defaultsKey = "mi_render_scene_layer_mode"

    /// Modo activo actualmente. Solo se modifica via switchMode(to:).
    private(set) var currentMode: SceneLayerMode

    /// Lista de todos los modos disponibles (para construir UI dinámicamente).
    var availableModes: [SceneLayerMode] { SceneLayerMode.allCases }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        currentMode = SceneLayerMode(rawValue: saved) ?? .meshRaw
    }

    /// Cambia el modo activo, persiste en UserDefaults y emite notificación.
    func switchMode(to mode: SceneLayerMode) {
        currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: .sceneLayerDidChange, object: mode)
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    static let sceneLayerDidChange = Notification.Name("mi_render_sceneLayerDidChange")
}
