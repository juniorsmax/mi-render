// SceneModeManager.swift
// Gestiona el modo de visualización activo en SceneViewer.
// Persiste la selección con UserDefaults y notifica cambios via NotificationCenter.

import Foundation
import UIKit

// MARK: - SceneMode

enum SceneMode: String, CaseIterable {
    case meshSolid           = "meshSolid"
    case meshWireframe       = "meshWireframe"
    case meshSemantic        = "meshSemantic"
    case floorPlan2D         = "floorPlan2D"
    case roomVolumeBounding  = "roomVolumeBounding"
    case orbitViewer         = "orbitViewer"
    case walkthroughPlayback = "walkthroughPlayback"
    case panoramaNodes       = "panoramaNodes"

    var displayName: String {
        switch self {
        case .meshSolid:           return "Sólido"
        case .meshWireframe:       return "Wire"
        case .meshSemantic:        return "Semánt."
        case .floorPlan2D:         return "Plano"
        case .roomVolumeBounding:  return "Volumen"
        case .orbitViewer:         return "Órbita"
        case .walkthroughPlayback: return "Recorrido"
        case .panoramaNodes:       return "Nodos"
        }
    }

    var systemImage: String {
        switch self {
        case .meshSolid:           return "cube.fill"
        case .meshWireframe:       return "cube"
        case .meshSemantic:        return "paintpalette"
        case .floorPlan2D:         return "map"
        case .roomVolumeBounding:  return "square.3.layers.3d"
        case .orbitViewer:         return "rotate.3d"
        case .walkthroughPlayback: return "play.circle"
        case .panoramaNodes:       return "dot.radiowaves.left.and.right"
        }
    }
}

// MARK: - SceneModeManager

class SceneModeManager {

    static let shared = SceneModeManager()

    private static let defaultsKey = "mi_render_scene_mode"

    private(set) var currentMode: SceneMode

    private init() {
        let saved  = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        currentMode = SceneMode(rawValue: saved) ?? .meshSolid
    }

    func switchMode(_ mode: SceneMode) {
        currentMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: .sceneModeDidChange, object: mode)
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let sceneModeDidChange = Notification.Name("mi_render_sceneModeDidChange")
}
