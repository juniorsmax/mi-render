// SceneSegmentationModel.swift
// Segmenta semánticamente la imagen de cámara en regiones: pared, suelo,
// techo, mueble, ventana, puerta, otro.
// Placeholder: devuelve regiones vacías hasta que el modelo LoRA esté disponible.

import ARKit
import CoreML
import CoreImage
import UIKit
import simd

// MARK: - Región segmentada

struct SegmentedRegion {
    enum Label: String, CaseIterable {
        case wall, floor, ceiling, furniture, window, door, other
        var color: UIColor {
            switch self {
            case .wall:      return UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.5)
            case .floor:     return UIColor(red: 0.8, green: 0.7, blue: 0.5, alpha: 0.5)
            case .ceiling:   return UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 0.5)
            case .furniture: return UIColor(red: 0.5, green: 0.9, blue: 0.5, alpha: 0.5)
            case .window:    return UIColor(red: 0.5, green: 0.8, blue: 1.0, alpha: 0.4)
            case .door:      return UIColor(red: 0.9, green: 0.6, blue: 0.4, alpha: 0.5)
            case .other:     return UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.3)
            }
        }
    }

    let label:      Label
    let confidence: Float          // 0–1
    let boundingBox: CGRect        // normalizado 0–1
    let maskPixels: [Bool]?        // máscara densa opcional (ancho × alto)
    let maskWidth:  Int
    let maskHeight: Int
}

// MARK: - SceneSegmentationModel

final class SceneSegmentationModel {

    static let shared = SceneSegmentationModel()

    private let inputWidth  = 512
    private let inputHeight = 512

    // MARK: - Segmentación desde ARFrame

    /// Segmenta el frame actual. Usa el modelo CoreML si está disponible,
    /// si no devuelve regiones de placeholder basadas en ARPlaneAnchor.
    func segment(frame: ARFrame,
                 completion: @escaping ([SegmentedRegion]) -> Void) {

        if let model = LoRALoader.shared.model(for: .sceneSegmentation) {
            segmentWithModel(model, frame: frame, completion: completion)
        } else {
            segmentWithFallback(frame: frame, completion: completion)
        }
    }

    // MARK: - Inferencia real (cuando el modelo esté listo)

    private func segmentWithModel(_ model: MLModel,
                                  frame: ARFrame,
                                  completion: @escaping ([SegmentedRegion]) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            guard let resized = self.resize(pixelBuffer: frame.capturedImage,
                                            to: CGSize(width: self.inputWidth,
                                                       height: self.inputHeight)),
                  let input = try? MLDictionaryFeatureProvider(
                      dictionary: ["image": MLFeatureValue(pixelBuffer: resized)])
            else {
                completion([])
                return
            }

            guard let output = try? model.prediction(from: input) else {
                completion([])
                return
            }

            // TODO: parsear output.featureValue(for: "segmentation_mask")
            // cuando el modelo LoRA esté integrado.
            _ = output
            DispatchQueue.main.async { completion([]) }
        }
    }

    // MARK: - Fallback basado en ARPlaneAnchor

    private func segmentWithFallback(frame: ARFrame,
                                     completion: @escaping ([SegmentedRegion]) -> Void) {
        var regions: [SegmentedRegion] = []

        for anchor in frame.anchors.compactMap({ $0 as? ARPlaneAnchor }) {
            let label: SegmentedRegion.Label = anchor.alignment == .horizontal ? .floor : .wall
            // Proyectar centro del plano en imagen (aproximación)
            let center3D = SIMD3<Float>(anchor.center.x + anchor.transform.columns.3.x,
                                        anchor.center.y + anchor.transform.columns.3.y,
                                        anchor.center.z + anchor.transform.columns.3.z)
            let projected = frame.camera.projectPoint(
                center3D,
                orientation: .landscapeRight,
                viewportSize: CGSize(width: inputWidth, height: inputHeight)
            )
            let bbox = CGRect(
                x: (projected.x / CGFloat(inputWidth))  - 0.1,
                y: (projected.y / CGFloat(inputHeight)) - 0.1,
                width: 0.2, height: 0.2
            )
            regions.append(SegmentedRegion(
                label: label, confidence: 0.5,
                boundingBox: bbox, maskPixels: nil,
                maskWidth: 0, maskHeight: 0
            ))
        }

        DispatchQueue.main.async { completion(regions) }
    }

    // MARK: - Helper: resize CVPixelBuffer

    private func resize(_ pixelBuffer: CVPixelBuffer, to size: CGSize) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let scaleX  = size.width  / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let scaleY  = size.height / CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let scaled  = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var output: CVPixelBuffer?
        CVPixelBufferCreate(nil, Int(size.width), Int(size.height),
                            kCVPixelFormatType_32BGRA, nil, &output)
        guard let out = output else { return nil }

        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        ctx.render(scaled, to: out)
        return out
    }
}
