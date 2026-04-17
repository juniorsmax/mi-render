// InteriorStyleClassifier.swift
// Clasifica el estilo de interior de la escena capturada.
// Estilos: moderno, minimalista, industrial, escandinavo, clásico,
//          rústico, bohemio, contemporáneo.
// Placeholder: devuelve distribución uniforme hasta que el modelo LoRA esté disponible.

import ARKit
import CoreML
import CoreImage
import UIKit

// MARK: - Estilo de interior

struct InteriorStylePrediction {
    enum Style: String, CaseIterable {
        case modern, minimalist, industrial, scandinavian,
             classic, rustic, bohemian, contemporary

        var displayName: String {
            switch self {
            case .modern:        return "Moderno"
            case .minimalist:    return "Minimalista"
            case .industrial:    return "Industrial"
            case .scandinavian:  return "Escandinavo"
            case .classic:       return "Clásico"
            case .rustic:        return "Rústico"
            case .bohemian:      return "Bohemio"
            case .contemporary:  return "Contemporáneo"
            }
        }

        /// Paleta de color representativa del estilo
        var accentColor: UIColor {
            switch self {
            case .modern:        return UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            case .minimalist:    return UIColor(red: 0.95, green: 0.95, blue: 0.92, alpha: 1)
            case .industrial:    return UIColor(red: 0.5, green: 0.45, blue: 0.4, alpha: 1)
            case .scandinavian:  return UIColor(red: 0.9, green: 0.87, blue: 0.82, alpha: 1)
            case .classic:       return UIColor(red: 0.8, green: 0.72, blue: 0.55, alpha: 1)
            case .rustic:        return UIColor(red: 0.65, green: 0.48, blue: 0.3, alpha: 1)
            case .bohemian:      return UIColor(red: 0.78, green: 0.5, blue: 0.35, alpha: 1)
            case .contemporary:  return UIColor(red: 0.6, green: 0.65, blue: 0.7, alpha: 1)
            }
        }

        /// Materiales predominantes en este estilo
        var dominantMaterials: [String] {
            switch self {
            case .modern:        return ["metal", "glass", "concrete"]
            case .minimalist:    return ["wood", "paint", "fabric"]
            case .industrial:    return ["metal", "concrete", "wood"]
            case .scandinavian:  return ["wood", "fabric", "paint"]
            case .classic:       return ["wood", "fabric", "stone"]
            case .rustic:        return ["wood", "stone", "fabric"]
            case .bohemian:      return ["fabric", "wood", "tile"]
            case .contemporary:  return ["metal", "wood", "glass"]
            }
        }
    }

    let topStyle:   Style
    let confidence: Float
    let allScores:  [Style: Float]
    let roomType:   RoomTypePrediction.RoomType
}

// MARK: - Tipo de habitación

struct RoomTypePrediction {
    enum RoomType: String, CaseIterable {
        case livingRoom, bedroom, kitchen, bathroom,
             diningRoom, office, hallway, unknown

        var displayName: String {
            switch self {
            case .livingRoom:  return "Salón"
            case .bedroom:     return "Dormitorio"
            case .kitchen:     return "Cocina"
            case .bathroom:    return "Baño"
            case .diningRoom:  return "Comedor"
            case .office:      return "Oficina"
            case .hallway:     return "Pasillo"
            case .unknown:     return "Desconocido"
            }
        }
    }

    let roomType:   RoomType
    let confidence: Float
    let allScores:  [RoomType: Float]
}

// MARK: - InteriorStyleClassifier

final class InteriorStyleClassifier {

    static let shared = InteriorStyleClassifier()

    private let inputSize = CGSize(width: 299, height: 299)

    // MARK: - Clasificar estilo

    /// Clasifica el estilo de la escena a partir de un frame.
    func classifyStyle(frame: ARFrame,
                       completion: @escaping (InteriorStylePrediction) -> Void) {

        if let model = LoRALoader.shared.model(for: .interiorStyle) {
            classifyWithModel(model, frame: frame, completion: completion)
        } else {
            classifyStyleFallback(completion: completion)
        }
    }

    /// Infiere el tipo de habitación a partir de los objetos y superficies detectados.
    func detectRoomType(detectedObjects: [DetectedObject3D],
                        surfaces: MeshSurfaces,
                        completion: @escaping (RoomTypePrediction) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            let prediction = self.inferRoomType(
                objects: detectedObjects,
                surfaces: surfaces
            )
            DispatchQueue.main.async { completion(prediction) }
        }
    }

    // MARK: - Inferencia real

    private func classifyWithModel(_ model: MLModel,
                                   frame: ARFrame,
                                   completion: @escaping (InteriorStylePrediction) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            guard let resized = self.resize(pixelBuffer: frame.capturedImage,
                                            to: self.inputSize),
                  let input = try? MLDictionaryFeatureProvider(
                      dictionary: ["image": MLFeatureValue(pixelBuffer: resized)])
            else {
                self.classifyStyleFallback(completion: completion)
                return
            }

            guard let output = try? model.prediction(from: input) else {
                self.classifyStyleFallback(completion: completion)
                return
            }

            // TODO: extraer probabilidades del output cuando el modelo esté integrado.
            // let probs = output.featureValue(for: "styleProbs")?.dictionaryValue
            _ = output
            self.classifyStyleFallback(completion: completion)
        }
    }

    // MARK: - Fallback: heurística basada en objetos y superficies

    private func classifyStyleFallback(completion: @escaping (InteriorStylePrediction) -> Void) {
        let uniform = 1.0 / Float(InteriorStylePrediction.Style.allCases.count)
        var scores: [InteriorStylePrediction.Style: Float] = [:]
        InteriorStylePrediction.Style.allCases.forEach { scores[$0] = uniform }

        let prediction = InteriorStylePrediction(
            topStyle:   .contemporary,
            confidence: uniform,
            allScores:  scores,
            roomType:   .unknown
        )
        DispatchQueue.main.async { completion(prediction) }
    }

    /// Infiere tipo de habitación por reglas heurísticas simples.
    private func inferRoomType(objects: [DetectedObject3D],
                               surfaces: MeshSurfaces) -> RoomTypePrediction {

        var scores: [RoomTypePrediction.RoomType: Float] = [:]
        RoomTypePrediction.RoomType.allCases.forEach { scores[$0] = 0.1 }

        let labels = objects.map { $0.label }

        if labels.contains(.sofa)   { scores[.livingRoom, default: 0] += 0.4 }
        if labels.contains(.bed)    { scores[.bedroom,    default: 0] += 0.5 }
        if labels.contains(.desk)   { scores[.office,     default: 0] += 0.3 }
        if labels.contains(.chair)  { scores[.office,     default: 0] += 0.15 }
        if labels.contains(.tv)     { scores[.livingRoom, default: 0] += 0.25 }
        if labels.contains(.refrigerator) { scores[.kitchen, default: 0] += 0.6 }

        // Baño: mucha cerámica relativa al suelo
        if surfaces.floor > 0 && surfaces.wall / surfaces.floor > 1.5 {
            scores[.bathroom, default: 0] += 0.2
        }

        let best = scores.max { $0.value < $1.value }!
        return RoomTypePrediction(
            roomType:   best.key,
            confidence: best.value,
            allScores:  scores
        )
    }

    // MARK: - Helper: resize

    private func resize(_ pixelBuffer: CVPixelBuffer, to size: CGSize) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX  = size.width  / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY  = size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaled  = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                            kCVPixelFormatType_32BGRA, nil, &output)
        guard let out = output else { return nil }

        CIContext(options: [.useSoftwareRenderer: false]).render(scaled, to: out)
        return out
    }
}
