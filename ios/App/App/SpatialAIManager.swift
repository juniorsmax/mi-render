// SpatialAIManager.swift
// Capa de integración entre el escaneo LiDAR y los modelos LoRA de IA espacial.
// Orquesta: SceneGraphManager, SpatialInferencePipeline, FloorPlan2DGenerator,
//           MeshManager y MaterialLibraryManager.
// Los modelos ML se cargan desde LoRALoader — no hay inferencia directa aquí.

import ARKit
import RealityKit
import UIKit

// MARK: - Estado del manager

enum SpatialAIState {
    case idle
    case loadingModels
    case processing
    case ready
    case failed(Error)
}

// MARK: - Resultado de una operación AI

struct SpatialAIResult {
    var walls:        [SegmentedRegion]        = []
    var furniture:    [DetectedObject3D]       = []
    var materials:    [MaterialPrediction]     = []
    var roomType:     RoomTypePrediction?
    var style:        InteriorStylePrediction?
    var floorplanURL: URL?
    var meshRefined:  Bool                     = false
    var timestamp:    Date                     = Date()
}

// MARK: - SpatialAIManager

class SpatialAIManager {

    static let shared = SpatialAIManager()

    // MARK: - Estado

    private(set) var state: SpatialAIState = .idle {
        didSet { DispatchQueue.main.async { self.onStateChanged?(self.state) } }
    }

    /// Último resultado procesado.
    private(set) var lastResult = SpatialAIResult()

    // MARK: - Callbacks

    var onStateChanged:    ((SpatialAIState) -> Void)?
    var onResultReady:     ((SpatialAIResult) -> Void)?
    var onWallsDetected:   (([SegmentedRegion]) -> Void)?
    var onFurnitureFound:  (([DetectedObject3D]) -> Void)?
    var onMaterialsMapped: (([MaterialPrediction]) -> Void)?
    var onFloorplanReady:  ((URL?) -> Void)?
    var onMeshRefined:     ((Bool) -> Void)?

    // MARK: - Inicialización

    /// Precarga los modelos LoRA en background al iniciar la app.
    func warmUp() {
        state = .loadingModels
        LoRALoader.shared.preloadAll { [weak self] results in
            let ready = results.filter { $0.value }.count
            print("[SpatialAIManager] modelos disponibles: \(ready)/\(results.count)")
            self?.state = .ready
        }
    }

    // MARK: - detectWalls

    /// Segmenta las paredes del frame ARKit actual.
    func detectWalls(frame: ARFrame,
                     completion: (([SegmentedRegion]) -> Void)? = nil) {

        state = .processing

        SpatialInferencePipeline.shared.detectWalls(frame: frame) { [weak self] walls in
            guard let self = self else { return }
            self.lastResult.walls = walls
            self.onWallsDetected?(walls)
            completion?(walls)
            self.state = .ready
            print("[SpatialAIManager] detectWalls: \(walls.count) paredes")
        }
    }

    // MARK: - detectFurniture

    /// Detecta y localiza muebles en el espacio 3D.
    func detectFurniture(frame: ARFrame,
                         completion: (([DetectedObject3D]) -> Void)? = nil) {

        state = .processing

        SpatialInferencePipeline.shared.detectFurniture(frame: frame) { [weak self] objects in
            guard let self = self else { return }
            self.lastResult.furniture = objects
            self.onFurnitureFound?(objects)
            completion?(objects)
            self.state = .ready
            print("[SpatialAIManager] detectFurniture: \(objects.count) objetos")
        }
    }

    // MARK: - detectMaterials

    /// Clasifica materiales en las regiones detectadas del frame.
    /// Si no se pasan regiones, usa los bounding boxes de muebles del último resultado.
    func detectMaterials(frame: ARFrame,
                         regions: [CGRect]? = nil,
                         completion: (([MaterialPrediction]) -> Void)? = nil) {

        state = .processing

        let targetRegions = regions
            ?? lastResult.furniture.map { $0.boundingBox2D }

        SpatialInferencePipeline.shared.detectMaterials(
            frame: frame,
            regions: targetRegions.isEmpty ? [CGRect(x: 0, y: 0, width: 1, height: 1)]
                                           : targetRegions
        ) { [weak self] predictions in
            guard let self = self else { return }
            self.lastResult.materials = predictions
            self.onMaterialsMapped?(predictions)
            completion?(predictions)
            self.state = .ready
            print("[SpatialAIManager] detectMaterials: \(predictions.count) regiones")
        }
    }

    // MARK: - generateFloorplan

    /// Genera el plano de planta 2D a partir de la geometría LiDAR acumulada.
    func generateFloorplan(projectId: UUID? = nil,
                           completion: ((URL?) -> Void)? = nil) {

        state = .processing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Obtener imagen del plano desde RoomPlanManager (iOS 16+)
            // o como PNG del plano generado con FloorPlan2DGenerator
            let image: UIImage
            if #available(iOS 16.0, *),
               RoomPlanManager.shared.lastCapturedRoom != nil {
                image = RoomPlanManager.shared.renderFloorPlan()
            } else {
                // Renderizar footprint del suelo como UIImage 800×800
                if let footprint = RoomPlanManager.shared.floorFootprint {
                    image = PlanRenderer.shared.renderFloorFootprint(footprint,
                                                                     size: CGSize(width: 800, height: 800))
                } else {
                    image = UIImage()
                }
            }

            // Guardar PNG en el proyecto si hay projectId
            var savedURL: URL? = nil
            if let pid = projectId {
                let docs = FileManager.default.urls(for: .documentDirectory,
                                                    in: .userDomainMask)[0]
                let dir  = docs.appendingPathComponent("projects/\(pid.uuidString)")
                try? FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true)
                let url  = dir.appendingPathComponent("floorplan.png")
                if let data = image.pngData() {
                    try? data.write(to: url, options: .atomic)
                    savedURL = url
                }
            }

            DispatchQueue.main.async {
                self.lastResult.floorplanURL = savedURL
                self.onFloorplanReady?(savedURL)
                completion?(savedURL)
                self.state = .ready
                print("[SpatialAIManager] generateFloorplan → \(savedURL?.lastPathComponent ?? "nil")")
            }
        }
    }

    // MARK: - refineMesh

    /// Aplica el pipeline de IA para mejorar las clasificaciones semánticas del mesh.
    func refineMesh(frame: ARFrame,
                    completion: ((Bool) -> Void)? = nil) {

        state = .processing

        let anchors = MeshManager.shared.meshAnchors

        SpatialInferencePipeline.shared.enhanceMesh(
            frame: frame,
            anchors: anchors
        ) { [weak self] refinedAnchors in
            guard let self = self else { return }

            // Actualizar SceneGraph con el mesh refinado
            SceneGraphManager.shared.buildGraph(from: refinedAnchors)
            SceneGraphManager.shared.saveGraph()

            self.lastResult.meshRefined = true
            self.onMeshRefined?(true)
            completion?(true)
            self.state = .ready
            print("[SpatialAIManager] refineMesh: \(refinedAnchors.count) anchors procesados")
        }
    }

    // MARK: - Pipeline completo

    /// Ejecuta toda la cadena de IA sobre el frame actual.
    func runFullAnalysis(frame: ARFrame,
                         projectId: UUID? = nil,
                         completion: ((SpatialAIResult) -> Void)? = nil) {

        state = .processing

        SpatialInferencePipeline.shared.runFullPipeline(frame: frame) { [weak self] result in
            guard let self = self else { return }

            self.lastResult = SpatialAIResult(
                walls:     result.walls,
                furniture: result.furniture,
                materials: result.materials,
                roomType:  result.roomType,
                style:     result.style
            )

            // Actualizar SceneGraph con tipo de habitación detectado
            if let roomType = result.roomType {
                SceneGraphManager.shared.updateNode(id: SceneGraphManager.shared.graph.rootId ?? UUID()) {
                    $0.metadata["roomType"]   = roomType.roomType.rawValue
                    $0.metadata["roomStyle"]  = result.style?.topStyle.rawValue ?? ""
                    $0.metadata["confidence"] = String(format: "%.2f", roomType.confidence)
                }
            }

            // Generar floorplan si hay proyecto
            if let pid = projectId {
                self.generateFloorplan(projectId: pid) { url in
                    self.lastResult.floorplanURL = url
                    self.onResultReady?(self.lastResult)
                    completion?(self.lastResult)
                    self.state = .ready
                }
            } else {
                self.onResultReady?(self.lastResult)
                completion?(self.lastResult)
                self.state = .ready
            }
        }
    }

    // MARK: - Reset

    func reset() {
        lastResult = SpatialAIResult()
        state      = .idle
    }
}
