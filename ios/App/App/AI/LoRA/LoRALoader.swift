// LoRALoader.swift
// Carga adaptadores LoRA (.mlmodelc / .mlpackage) en tiempo de ejecución.
// Los modelos se buscan en Bundle.main/AI/LoRA/ o en Documents/AI/LoRA/.
// Cuando los modelos reales estén disponibles, sustituir los stubs por
// MLModel.load(contentsOf:configuration:) con los pesos LoRA aplicados.

import CoreML
import Foundation

// MARK: - Tipos de modelo LoRA disponibles

enum LoRAModelType: String, CaseIterable {
    case sceneSegmentation   = "SceneSegmentation"
    case materialClassifier  = "MaterialClassifier"
    case objectDetector3D    = "ObjectDetector3D"
    case interiorStyle       = "InteriorStyleClassifier"

    /// Nombre del archivo esperado en el bundle (sin extensión).
    var fileName: String { rawValue }

    /// Descripción legible.
    var displayName: String {
        switch self {
        case .sceneSegmentation: return "Segmentación de escena"
        case .materialClassifier: return "Clasificador de materiales"
        case .objectDetector3D:  return "Detector 3D de objetos"
        case .interiorStyle:     return "Estilo de interior"
        }
    }
}

// MARK: - Estado de carga de un modelo

enum LoRAModelState {
    case notLoaded
    case loading
    case ready(MLModel)
    case failed(Error)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - LoRALoader

final class LoRALoader {

    static let shared = LoRALoader()

    private var modelStates: [LoRAModelType: LoRAModelState] = [:]
    private let queue = DispatchQueue(label: "ai.loraloader", qos: .userInitiated)

    // MARK: - API pública

    /// Carga todos los modelos disponibles en background.
    func preloadAll(completion: @escaping ([LoRAModelType: Bool]) -> Void) {
        let group = DispatchGroup()
        var results: [LoRAModelType: Bool] = [:]
        let lock = NSLock()

        for type in LoRAModelType.allCases {
            group.enter()
            load(type) { state in
                lock.lock()
                results[type] = state.isReady
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { completion(results) }
    }

    /// Carga un modelo específico.
    func load(_ type: LoRAModelType, completion: @escaping (LoRAModelState) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Si ya está cargado, devolver directamente
            if case .ready = self.modelStates[type] {
                DispatchQueue.main.async { completion(self.modelStates[type]!) }
                return
            }

            self.modelStates[type] = .loading

            // Buscar .mlmodelc en bundle o Documents
            if let url = self.resolveModelURL(for: type) {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .cpuAndNeuralEngine
                    let model = try MLModel(contentsOf: url, configuration: config)
                    let state = LoRAModelState.ready(model)
                    self.modelStates[type] = state
                    print("[LoRALoader] ✓ \(type.rawValue) cargado desde \(url.lastPathComponent)")
                    DispatchQueue.main.async { completion(state) }
                } catch {
                    let state = LoRAModelState.failed(error)
                    self.modelStates[type] = state
                    print("[LoRALoader] ✗ \(type.rawValue): \(error.localizedDescription)")
                    DispatchQueue.main.async { completion(state) }
                }
            } else {
                // Placeholder: modelo no disponible aún
                let state = LoRAModelState.notLoaded
                self.modelStates[type] = state
                print("[LoRALoader] ⚠ \(type.rawValue): modelo no encontrado — usando stub")
                DispatchQueue.main.async { completion(state) }
            }
        }
    }

    /// Devuelve el modelo listo si está cargado, nil si no.
    func model(for type: LoRAModelType) -> MLModel? {
        if case .ready(let model) = modelStates[type] { return model }
        return nil
    }

    /// Estado actual de un modelo.
    func state(for type: LoRAModelType) -> LoRAModelState {
        modelStates[type] ?? .notLoaded
    }

    /// Descarga todos los modelos de memoria.
    func unloadAll() {
        queue.async { [weak self] in
            self?.modelStates.removeAll()
        }
    }

    // MARK: - Resolución de URL

    private func resolveModelURL(for type: LoRAModelType) -> URL? {
        let name = type.fileName

        // 1. Bundle principal — AI/LoRA/<name>.mlmodelc
        if let url = Bundle.main.url(forResource: name,
                                      withExtension: "mlmodelc",
                                      subdirectory: "AI/LoRA") {
            return url
        }

        // 2. Documents — AI/LoRA/<name>.mlmodelc (modelos descargados en runtime)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let docsURL = docs
            .appendingPathComponent("AI/LoRA")
            .appendingPathComponent("\(name).mlmodelc")
        if FileManager.default.fileExists(atPath: docsURL.path) {
            return docsURL
        }

        // 3. .mlpackage como fallback
        if let url = Bundle.main.url(forResource: name,
                                      withExtension: "mlpackage",
                                      subdirectory: "AI/LoRA") {
            return url
        }

        return nil
    }
}
