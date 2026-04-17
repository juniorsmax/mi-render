// SpatialInferencePipeline.swift
// Pipeline unificado de inferencia espacial LoRA.
// Expone la API pública que conecta todos los modelos AI:
//   detectWalls()      → segmentación de paredes
//   detectFurniture()  → detección 3D de muebles
//   detectMaterials()  → clasificación de materiales por región
//   detectRoomType()   → tipo + estilo de habitación
//   enhanceMesh()      → refinamiento semántico del mesh LiDAR

import ARKit
import RealityKit
import simd

// MARK: - Resultado completo del pipeline

struct SpatialInferenceResult {
    var walls:       [SegmentedRegion]         = []
    var furniture:   [DetectedObject3D]        = []
    var materials:   [MaterialPrediction]      = []
    var roomType:    RoomTypePrediction?        = nil
    var style:       InteriorStylePrediction?   = nil
    var timestamp:   Date                       = Date()
}

// MARK: - SpatialInferencePipeline

final class SpatialInferencePipeline {

    static let shared = SpatialInferencePipeline()

    /// Última inferencia completa ejecutada.
    private(set) var lastResult = SpatialInferenceResult()

    /// Callback invocado cuando se completa una inferencia completa.
    var onResultUpdated: ((SpatialInferenceResult) -> Void)?

    // MARK: - Precargar modelos

    /// Inicia la carga de todos los modelos LoRA en background.
    func warmUp() {
        LoRALoader.shared.preloadAll { results in
            let loaded  = results.filter { $0.value }.count
            let total   = results.count
            print("[SpatialPipeline] modelos listos: \(loaded)/\(total)")
        }
    }

    // MARK: - API pública

    /// Detecta paredes en el frame actual.
    func detectWalls(frame: ARFrame,
                     completion: @escaping ([SegmentedRegion]) -> Void) {

        SceneSegmentationModel.shared.segment(frame: frame) { regions in
            let walls = regions.filter { $0.label == .wall }
            completion(walls)
        }
    }

    /// Detecta y localiza muebles en 3D.
    func detectFurniture(frame: ARFrame,
                         completion: @escaping ([DetectedObject3D]) -> Void) {

        ObjectDetector3D.shared.detectFurniture(frame: frame, completion: completion)
    }

    /// Clasifica materiales en las regiones detectadas de la imagen.
    func detectMaterials(frame: ARFrame,
                         regions: [CGRect],
                         completion: @escaping ([MaterialPrediction]) -> Void) {

        guard !regions.isEmpty else { completion([]); return }
        MaterialClassifier.shared.classifyBatch(frame: frame,
                                                regions: regions,
                                                completion: completion)
    }

    /// Infiere el tipo de habitación y el estilo de interior.
    func detectRoomType(frame: ARFrame,
                        completion: @escaping (RoomTypePrediction, InteriorStylePrediction) -> Void) {

        let surfaces = MeshManager.shared.surfaces

        // 1. Detectar objetos para heurística de tipo de habitación
        ObjectDetector3D.shared.detectFurniture(frame: frame) { objects in

            InteriorStyleClassifier.shared.detectRoomType(
                detectedObjects: objects,
                surfaces: surfaces
            ) { roomPrediction in

                InteriorStyleClassifier.shared.classifyStyle(frame: frame) { stylePrediction in
                    completion(roomPrediction, stylePrediction)
                }
            }
        }
    }

    /// Refina semánticamente el mesh LiDAR usando los resultados de segmentación.
    /// Asigna clasificaciones mejoradas a los ARMeshAnchor basándose en la imagen.
    func enhanceMesh(frame: ARFrame,
                     anchors: [ARMeshAnchor],
                     completion: @escaping ([ARMeshAnchor]) -> Void) {

        guard !anchors.isEmpty else { completion([]); return }

        SceneSegmentationModel.shared.segment(frame: frame) { regions in
            // Placeholder: sin modificación real hasta que el modelo esté disponible.
            // Cuando esté integrado: proyectar máscara 2D a espacio 3D y reclasificar
            // los triángulos del anchor usando back-projection camera → world.
            print("[SpatialPipeline] enhanceMesh: \(anchors.count) anchors, "
                  + "\(regions.count) regiones segmentadas (stub)")
            DispatchQueue.main.async { completion(anchors) }
        }
    }

    // MARK: - Pipeline completo

    /// Ejecuta todos los modelos en secuencia sobre un frame.
    func runFullPipeline(frame: ARFrame,
                         completion: @escaping (SpatialInferenceResult) -> Void) {

        var result = SpatialInferenceResult()
        let group  = DispatchGroup()

        // Segmentación (paredes + todos)
        group.enter()
        SceneSegmentationModel.shared.segment(frame: frame) { regions in
            result.walls = regions.filter { $0.label == .wall }
            group.leave()
        }

        // Detección de muebles
        group.enter()
        ObjectDetector3D.shared.detectFurniture(frame: frame) { objects in
            result.furniture = objects
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            // Materiales en bounding boxes de muebles
            let rects = result.furniture.map { $0.boundingBox2D }
            MaterialClassifier.shared.classifyBatch(frame: frame, regions: rects) { preds in
                result.materials = preds

                // Tipo de habitación + estilo
                let surfaces = MeshManager.shared.surfaces
                InteriorStyleClassifier.shared.detectRoomType(
                    detectedObjects: result.furniture,
                    surfaces: surfaces
                ) { roomPred in
                    result.roomType = roomPred
                    InteriorStyleClassifier.shared.classifyStyle(frame: frame) { stylePred in
                        result.style     = stylePred
                        result.timestamp = Date()
                        self.lastResult  = result
                        DispatchQueue.main.async {
                            self.onResultUpdated?(result)
                            completion(result)
                        }
                    }
                }
            }
        }
    }
}
