// UIStateManager.swift
// Agente 11 — UIStateAgent
// Centraliza el estado de la interfaz de escaneo.
// Gestiona modo activo, progreso, warnings y transiciones.
// Desacopla el estado UI del código ARKit.

import Foundation
import ARKit

class UIStateManager {

    static let shared = UIStateManager()

    // MARK: - Modos de escaneo

    enum ScanMode: String {
        case idle       = "idle"
        case scanning   = "scanning"
        case processing = "processing"
        case complete   = "complete"
        case error      = "error"
    }

    // MARK: - Estado actual

    private(set) var currentMode: ScanMode = .idle
    private(set) var progress: Float = 0.0
    private(set) var statusMessage: String = ""
    private(set) var warnings: [String] = []
    private(set) var isLiDARAvailable: Bool = false

    // Callbacks para la UI (React via bridge)
    var onModeChanged:    ((ScanMode) -> Void)?
    var onProgressUpdate: ((Float) -> Void)?
    var onWarning:        ((String) -> Void)?
    var onStatusUpdate:   ((String) -> Void)?

    // MARK: - Inicialización

    init() {
        isLiDARAvailable = ARKitCapabilities.hasLiDAR
    }

    // MARK: - Cambiar modo

    func switchMode(_ mode: ScanMode) {
        guard mode != currentMode else { return }
        currentMode = mode
        onModeChanged?(mode)
        updateDefaultStatus(for: mode)
    }

    // MARK: - Actualizar progreso

    func updateProgress(_ value: Float) {
        progress = min(1.0, max(0.0, value))
        onProgressUpdate?(progress)
    }

    // MARK: - Mostrar warning

    func showWarning(_ message: String) {
        warnings.append(message)
        onWarning?(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.warnings.removeAll { $0 == message }
        }
    }

    // MARK: - Estado de texto

    func setStatus(_ message: String) {
        statusMessage = message
        onStatusUpdate?(message)
    }

    // MARK: - Mensajes por defecto

    private func updateDefaultStatus(for mode: ScanMode) {
        switch mode {
        case .idle:
            setStatus("Listo para escanear")
        case .scanning:
            setStatus("Escaneando habitación…")
        case .processing:
            setStatus("Procesando modelo 3D…")
        case .complete:
            setStatus("Escaneo completado")
        case .error:
            setStatus("Error en el escaneo")
        }
    }

    // MARK: - Exportar estado como diccionario (para bridge JS)

    func stateDictionary() -> [String: Any] {
        return [
            "mode":       currentMode.rawValue,
            "progress":   progress,
            "status":     statusMessage,
            "warnings":   warnings,
            "hasLiDAR":   isLiDARAvailable
        ]
    }

    // MARK: - Reset

    func reset() {
        currentMode = .idle
        progress    = 0.0
        statusMessage = ""
        warnings.removeAll()
    }
}

// MARK: - Capacidades ARKit (helper)

enum ARKitCapabilities {
    static var hasLiDAR: Bool {
        if #available(iOS 14.0, *) {
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }
        return false
    }

    static var hasDepth: Bool {
        if #available(iOS 14.0, *) {
            return ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        }
        return false
    }
}
