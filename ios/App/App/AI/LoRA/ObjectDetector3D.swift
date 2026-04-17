// ObjectDetector3D.swift
// Detecta y localiza objetos de mobiliario en el espacio 3D combinando:
// - Detección 2D del modelo CoreML (bounding box en imagen)
// - Proyección a 3D usando ARFrame depth + camera intrinsics
// Placeholder: devuelve objetos vacíos hasta que el modelo LoRA esté disponible.

import ARKit
import CoreML
import CoreImage
import simd
import UIKit

// MARK: - Objeto detectado

struct DetectedObject3D {
    enum FurnitureClass: String, CaseIterable {
        case sofa, chair, table, bed, desk, wardrobe, shelf,
             lamp, door, window, plant, tv, refrigerator, other

        var displayName: String {
            switch self {
            case .sofa:        return "Sofá"
            case .chair:       return "Silla"
            case .table:       return "Mesa"
            case .bed:         return "Cama"
            case .desk:        return "Escritorio"
            case .wardrobe:    return "Armario"
            case .shelf:       return "Estantería"
            case .lamp:        return "Lámpara"
            case .door:        return "Puerta"
            case .window:      return "Ventana"
            case .plant:       return "Planta"
            case .tv:          return "TV"
            case .refrigerator: return "Frigorífico"
            case .other:       return "Objeto"
            }
        }

        /// Dimensiones típicas en metros (ancho, alto, profundo)
        var typicalSize: SIMD3<Float> {
            switch self {
            case .sofa:        return SIMD3(2.0, 0.8, 0.9)
            case .chair:       return SIMD3(0.6, 0.9, 0.6)
            case .table:       return SIMD3(1.2, 0.75, 0.8)
            case .bed:         return SIMD3(1.6, 0.5, 2.0)
            case .desk:        return SIMD3(1.2, 0.75, 0.6)
            case .wardrobe:    return SIMD3(1.2, 2.0, 0.6)
            case .shelf:       return SIMD3(0.8, 1.8, 0.3)
            case .lamp:        return SIMD3(0.3, 1.5, 0.3)
            case .door:        return SIMD3(0.9, 2.1, 0.05)
            case .window:      return SIMD3(1.2, 1.2, 0.05)
            case .plant:       return SIMD3(0.4, 1.0, 0.4)
            case .tv:          return SIMD3(1.2, 0.7, 0.05)
            case .refrigerator: return SIMD3(0.7, 1.8, 0.7)
            case .other:       return SIMD3(0.5, 0.5, 0.5)
            }
        }
    }

    let id:           UUID
    let label:        FurnitureClass
    let confidence:   Float
    let boundingBox2D: CGRect            // normalizado 0–1 en imagen
    let position3D:   SIMD3<Float>?     // coordenadas mundo ARKit (nil si no hay depth)
    let boundingBox3D: (min: SIMD3<Float>, max: SIMD3<Float>)?
}

// MARK: - ObjectDetector3D

final class ObjectDetector3D {

    static let shared = ObjectDetector3D()

    private let inputSize = CGSize(width: 416, height: 416)

    // MARK: - Detectar muebles

    /// Detecta objetos en el frame actual y los proyecta a 3D si hay depth disponible.
    func detectFurniture(frame: ARFrame,
                         completion: @escaping ([DetectedObject3D]) -> Void) {

        if let model = LoRALoader.shared.model(for: .objectDetector3D) {
            detectWithModel(model, frame: frame, completion: completion)
        } else {
            detectWithFallback(frame: frame, completion: completion)
        }
    }

    // MARK: - Inferencia real

    private func detectWithModel(_ model: MLModel,
                                 frame: ARFrame,
                                 completion: @escaping ([DetectedObject3D]) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            guard let resized = self.resize(pixelBuffer: frame.capturedImage,
                                            to: self.inputSize),
                  let input = try? MLDictionaryFeatureProvider(
                      dictionary: ["image": MLFeatureValue(pixelBuffer: resized)])
            else {
                self.detectWithFallback(frame: frame, completion: completion)
                return
            }

            guard let output = try? model.prediction(from: input) else {
                self.detectWithFallback(frame: frame, completion: completion)
                return
            }

            // TODO: parsear output (boxes + labels + scores) cuando el modelo esté listo.
            // Formato esperado: YOLO-style [cx, cy, w, h, conf, class_probs...]
            _ = output
            self.detectWithFallback(frame: frame, completion: completion)
        }
    }

    // MARK: - Fallback basado en ARMeshAnchor clusters

    private func detectWithFallback(frame: ARFrame,
                                    completion: @escaping ([DetectedObject3D]) -> Void) {

        var objects: [DetectedObject3D] = []

        // Usar ARObjectAnchor si existen en la sesión
        for anchor in frame.anchors.compactMap({ $0 as? ARObjectAnchor }) {
            let pos = SIMD3<Float>(anchor.transform.columns.3.x,
                                   anchor.transform.columns.3.y,
                                   anchor.transform.columns.3.z)
            objects.append(DetectedObject3D(
                id:            UUID(),
                label:         .other,
                confidence:    0.4,
                boundingBox2D: .zero,
                position3D:    pos,
                boundingBox3D: nil
            ))
        }

        DispatchQueue.main.async { completion(objects) }
    }

    // MARK: - Proyección 2D → 3D

    /// Proyecta un punto 2D al espacio 3D usando la depth map del frame.
    func project(point2D: CGPoint,
                 frame: ARFrame,
                 viewportSize: CGSize) -> SIMD3<Float>? {

        #if !targetEnvironment(simulator)
        guard let depthMap = frame.sceneDepth?.depthMap else { return nil }

        let depthW = CVPixelBufferGetWidth(depthMap)
        let depthH = CVPixelBufferGetHeight(depthMap)
        let px = Int(point2D.x / viewportSize.width  * CGFloat(depthW))
        let py = Int(point2D.y / viewportSize.height * CGFloat(depthH))

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let row    = base.advanced(by: py * CVPixelBufferGetBytesPerRow(depthMap))
        let depth  = row.assumingMemoryBound(to: Float32.self)[px]

        guard depth > 0, depth < 10 else { return nil }

        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0]; let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]; let cy = intrinsics[2][1]

        let xN = (Float(px) - cx) / fx
        let yN = (Float(py) - cy) / fy
        let localPoint = SIMD3<Float>(xN * depth, yN * depth, -depth)

        let world = frame.camera.transform * SIMD4<Float>(localPoint, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
        #else
        return nil
        #endif
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
