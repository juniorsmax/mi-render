// MaterialClassifier.swift
// Clasifica el material de una región de imagen (madera, hormigón, cerámica,
// cristal, metal, pintura, tela, piedra).
// Placeholder: devuelve confianza uniforme hasta que el modelo LoRA esté listo.

import CoreML
import CoreImage
import UIKit
import ARKit

// MARK: - Resultado de clasificación de material

struct MaterialPrediction {
    enum MaterialClass: String, CaseIterable {
        case wood, concrete, tile, glass, metal, paint, fabric, stone, unknown

        var displayName: String {
            switch self {
            case .wood:     return "Madera"
            case .concrete: return "Hormigón"
            case .tile:     return "Cerámica"
            case .glass:    return "Cristal"
            case .metal:    return "Metal"
            case .paint:    return "Pintura"
            case .fabric:   return "Tela"
            case .stone:    return "Piedra"
            case .unknown:  return "Desconocido"
            }
        }

        var roughness: Float {
            switch self {
            case .glass:  return 0.05
            case .metal:  return 0.2
            case .tile:   return 0.3
            case .wood:   return 0.6
            case .paint:  return 0.55
            case .concrete: return 0.8
            case .fabric: return 0.9
            case .stone:  return 0.75
            case .unknown: return 0.5
            }
        }

        var metallic: Float {
            switch self {
            case .metal:  return 0.9
            case .glass:  return 0.1
            default:      return 0.0
            }
        }
    }

    let topClass:    MaterialClass
    let confidence:  Float
    let allScores:   [MaterialClass: Float]
    let sourceRect:  CGRect        // región de la imagen analizada (normalizada 0–1)
}

// MARK: - MaterialClassifier

final class MaterialClassifier {

    static let shared = MaterialClassifier()

    private let cropSize = CGSize(width: 224, height: 224)

    // MARK: - Clasificar región de un ARFrame

    /// Clasifica el material en un rectángulo normalizado del frame actual.
    func classify(frame: ARFrame,
                  region: CGRect,
                  completion: @escaping (MaterialPrediction) -> Void) {

        if let model = LoRALoader.shared.model(for: .materialClassifier) {
            classifyWithModel(model, frame: frame, region: region, completion: completion)
        } else {
            classifyWithFallback(region: region, completion: completion)
        }
    }

    /// Clasifica múltiples regiones en un único frame.
    func classifyBatch(frame: ARFrame,
                       regions: [CGRect],
                       completion: @escaping ([MaterialPrediction]) -> Void) {

        guard !regions.isEmpty else { completion([]); return }

        var results   = [MaterialPrediction?](repeating: nil, count: regions.count)
        let group     = DispatchGroup()
        let lock      = NSLock()

        for (i, rect) in regions.enumerated() {
            group.enter()
            classify(frame: frame, region: rect) { pred in
                lock.lock()
                results[i] = pred
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results.compactMap { $0 })
        }
    }

    // MARK: - Inferencia real

    private func classifyWithModel(_ model: MLModel,
                                   frame: ARFrame,
                                   region: CGRect,
                                   completion: @escaping (MaterialPrediction) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            guard let cropped = self.crop(pixelBuffer: frame.capturedImage,
                                          region: region,
                                          to: self.cropSize),
                  let input = try? MLDictionaryFeatureProvider(
                      dictionary: ["image": MLFeatureValue(pixelBuffer: cropped)])
            else {
                self.classifyWithFallback(region: region, completion: completion)
                return
            }

            guard let output = try? model.prediction(from: input) else {
                self.classifyWithFallback(region: region, completion: completion)
                return
            }

            // TODO: extraer probabilidades del output cuando el modelo esté integrado.
            // let probs = output.featureValue(for: "classLabelProbs")?.dictionaryValue
            _ = output
            self.classifyWithFallback(region: region, completion: completion)
        }
    }

    // MARK: - Fallback

    private func classifyWithFallback(region: CGRect,
                                      completion: @escaping (MaterialPrediction) -> Void) {
        // Distribución uniforme de placeholder
        var scores: [MaterialPrediction.MaterialClass: Float] = [:]
        let uniform: Float = 1.0 / Float(MaterialPrediction.MaterialClass.allCases.count)
        MaterialPrediction.MaterialClass.allCases.forEach { scores[$0] = uniform }

        let prediction = MaterialPrediction(
            topClass:   .unknown,
            confidence: uniform,
            allScores:  scores,
            sourceRect: region
        )
        DispatchQueue.main.async { completion(prediction) }
    }

    // MARK: - Helper: crop + resize

    private func crop(_ pixelBuffer: CVPixelBuffer,
                      region: CGRect,
                      to size: CGSize) -> CVPixelBuffer? {

        let ciImage  = CIImage(cvPixelBuffer: pixelBuffer)
        let fullSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                              height: CVPixelBufferGetHeight(pixelBuffer))

        let cropRect = CGRect(
            x: region.origin.x * fullSize.width,
            y: region.origin.y * fullSize.height,
            width: region.width  * fullSize.width,
            height: region.height * fullSize.height
        )

        let scaleX = size.width  / cropRect.width
        let scaleY = size.height / cropRect.height
        let cropped = ciImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                            kCVPixelFormatType_32BGRA, nil, &output)
        guard let out = output else { return nil }

        CIContext(options: [.useSoftwareRenderer: false]).render(cropped, to: out)
        return out
    }
}
