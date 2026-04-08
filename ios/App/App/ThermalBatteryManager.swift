// ThermalBatteryManager.swift
// Agente 12 — ThermalBatteryAgent
// Monitorea temperatura y batería durante escaneos largos.
// Ajusta calidad de escaneo automáticamente para evitar cierre del sistema.
// Evita que iOS cierre la app por sobrecalentamiento.

import Foundation
import UIKit

class ThermalBatteryManager {

    static let shared = ThermalBatteryManager()

    // MARK: - Estado térmico

    enum ThermalLevel {
        case nominal    // normal
        case fair       // calentando
        case serious    // reducir carga
        case critical   // detener escaneo
    }

    private(set) var thermalLevel: ThermalLevel = .nominal
    private(set) var batteryLevel: Float = 1.0
    private(set) var isLowBattery: Bool = false

    var onThermalWarning:  ((ThermalLevel) -> Void)?
    var onBatteryWarning:  ((Float) -> Void)?
    var onShouldReduceScan: (() -> Void)?
    var onShouldStopScan:   (() -> Void)?

    private var thermalObserver: NSObjectProtocol?
    private var batteryTimer: Timer?

    // MARK: - Iniciar monitoreo

    func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBattery()

        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateBattery()
        }

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateThermal()
        }

        updateThermal()
    }

    // MARK: - Detener monitoreo

    func stopMonitoring() {
        batteryTimer?.invalidate()
        batteryTimer = nil

        if let obs = thermalObserver {
            NotificationCenter.default.removeObserver(obs)
            thermalObserver = nil
        }

        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: - Actualizar estado térmico

    private func updateThermal() {
        let state = ProcessInfo.processInfo.thermalState

        switch state {
        case .nominal:
            thermalLevel = .nominal
        case .fair:
            thermalLevel = .fair
            onThermalWarning?(.fair)
        case .serious:
            thermalLevel = .serious
            onThermalWarning?(.serious)
            onShouldReduceScan?()
        case .critical:
            thermalLevel = .critical
            onThermalWarning?(.critical)
            onShouldStopScan?()
        @unknown default:
            thermalLevel = .nominal
        }
    }

    // MARK: - Actualizar batería

    private func updateBattery() {
        batteryLevel = UIDevice.current.batteryLevel
        isLowBattery = batteryLevel > 0 && batteryLevel < 0.15

        if isLowBattery {
            onBatteryWarning?(batteryLevel)
        }

        if batteryLevel > 0 && batteryLevel < 0.05 {
            onShouldStopScan?()
        }
    }

    // MARK: - Ajustar calidad de escaneo según estado

    func recommendedScanQuality() -> ScanQualityManager.ScanQuality {
        switch thermalLevel {
        case .nominal:  return isLowBattery ? .good : .excellent
        case .fair:     return .good
        case .serious:  return .poor
        case .critical: return .lost
        }
    }

    // MARK: - Mensajes de advertencia

    func thermalWarningMessage() -> String? {
        switch thermalLevel {
        case .nominal: return nil
        case .fair:    return "Dispositivo calentando — reduciendo calidad"
        case .serious: return "Temperatura alta — escaneo reducido"
        case .critical: return "Temperatura crítica — escaneo pausado"
        }
    }

    func batteryWarningMessage() -> String? {
        guard isLowBattery else { return nil }
        return "Batería baja (\(Int(batteryLevel * 100))%) — conecta el cargador"
    }

    // MARK: - Estado para bridge JS

    func stateDictionary() -> [String: Any] {
        return [
            "thermalLevel": thermalLevelString(),
            "batteryLevel": batteryLevel,
            "isLowBattery": isLowBattery,
            "thermalWarning": thermalWarningMessage() ?? "",
            "batteryWarning": batteryWarningMessage() ?? ""
        ]
    }

    private func thermalLevelString() -> String {
        switch thermalLevel {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        }
    }
}
