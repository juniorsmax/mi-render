// SpatialAIManager.swift
// Capa de integración entre el escaneo LiDAR y los modelos LoRA de IA espacial.
// Orquesta: SceneGraphManager, FloorPlan2DGenerator, MeshManager.
// Los modelos LoRA están excluidos del target iOS — hooks preparados para CoreML.

import ARKit
import RealityKit
import UIKit

// MARK: - Stub types (LoRA pipeline excluido del target)
// Estos tipos se sustituirán por los reales cuando los archivos AI/LoRA
// se reintegren al target con modelos CoreML compilados.

struct SegmentedRegion {
    var label: String = ""
    var confidence: Float = 0
}

struct DetectedObject3D {
    var label: String = ""
    var confidence: Float = 0
    var boundingBox2D: CGRect = .zero
    var worldPosition: SIMD3<Float> = .zero
}

struct MaterialPrediction {
    var material: String = ""
    var confidence: Float = 0
    var region: CGRect = .zero
}

struct RoomTypePrediction {
    var roomType: RoomTypeLabel = .unknown
    var confidence: Float = 0
    enum RoomTypeLabel: String { case unknown, living, bedroom, kitchen, bathroom, office }
}

struct InteriorStylePrediction {
    var topStyle: StyleLabel = .unknown
    var confidence: Float = 0
    enum StyleLabel: String { case unknown, modern, classic, industrial, nordic }
}

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
    var walls:        [SegmentedRegion]    = []
    var furniture:    [DetectedObject3D]   = []
    var materials:    [MaterialPrediction] = []
    var roomType:     RoomTypePrediction?
    var style:        InteriorStylePrediction?
    var floorplanURL: URL?
    var meshRefined:  Bool                 = false
    var timestamp:    Date                 = Date()
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
    /// TODO: conectar LoRALoader cuando AI/LoRA se reintegre al target.
    func warmUp() {
        state = .loadingModels
        // Stub: LoRALoader excluido del target iOS
        // LoRALoader.shared.preloadAll { results in ... }
        print("[SpatialAIManager] warmUp: LoRA pipeline no disponible (stub)")
        state = .ready
    }

    // MARK: - detectWalls

    /// Segmenta las paredes del frame ARKit actual.
    /// TODO: conectar SpatialInferencePipeline cuando AI/LoRA se reintegre.
    func detectWalls(frame: ARFrame,
                     completion: (([SegmentedRegion]) -> Void)? = nil) {
        state = .processing
        // Stub: SpatialInferencePipeline excluido del target iOS
        let walls: [SegmentedRegion] = []
        lastResult.walls = walls
        onWallsDetected?(walls)
        completion?(walls)
        state = .ready
        print("[SpatialAIManager] detectWalls: stub (0 paredes)")
    }

    // MARK: - detectFurniture

    /// Detecta y localiza muebles en el espacio 3D.
    /// TODO: conectar SpatialInferencePipeline cuando AI/LoRA se reintegre.
    func detectFurniture(frame: ARFrame,
                         completion: (([DetectedObject3D]) -> Void)? = nil) {
        state = .processing
        // Stub: SpatialInferencePipeline excluido del target iOS
        let objects: [DetectedObject3D] = []
        lastResult.furniture = objects
        onFurnitureFound?(objects)
        completion?(objects)
        state = .ready
        print("[SpatialAIManager] detectFurniture: stub (0 objetos)")
    }

    // MARK: - detectMaterials

    /// Clasifica materiales en las regiones detectadas del frame.
    /// TODO: conectar SpatialInferencePipeline cuando AI/LoRA se reintegre.
    func detectMaterials(frame: ARFrame,
                         regions: [CGRect]? = nil,
                         completion: (([MaterialPrediction]) -> Void)? = nil) {
        state = .processing
        // Stub: SpatialInferencePipeline excluido del target iOS
        let predictions: [MaterialPrediction] = []
        lastResult.materials = predictions
        onMaterialsMapped?(predictions)
        completion?(predictions)
        state = .ready
        print("[SpatialAIManager] detectMaterials: stub (0 predicciones)")
    }

    // MARK: - generateFloorplan

    /// Genera el plano de planta 2D a partir de la geometría LiDAR acumulada.
    func generateFloorplan(projectId: UUID? = nil,
                           completion: ((URL?) -> Void)? = nil) {

        state = .processing

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let image: UIImage
            if #available(iOS 16.0, *),
               RoomPlanManager.shared.lastCapturedRoom != nil {
                image = RoomPlanManager.shared.renderFloorPlan()
            } else if #available(iOS 16.0, *),
                      let footprint = RoomPlanManager.shared.floorFootprint {
                image = PlanRenderer.shared.renderFloorFootprint(footprint,
                                                                 size: CGSize(width: 800, height: 800))
            } else {
                image = UIImage()
            }

            var savedURL: URL? = nil
            if let pid = projectId {
                let docs = FileManager.default.urls(for: .documentDirectory,
                                                    in: .userDomainMask)[0]
                let dir  = docs.appendingPathComponent("projects/\(pid.uuidString)")
                try? FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent("floorplan.png")
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

    /// Aplica mejoras semánticas al mesh usando ARKit.
    /// TODO: conectar SpatialInferencePipeline cuando AI/LoRA se reintegre.
    func refineMesh(frame: ARFrame,
                    completion: ((Bool) -> Void)? = nil) {
        state = .processing
        // Stub: SpatialInferencePipeline excluido del target iOS
        // Reconstruye el SceneGraph directamente desde los anchors actuales
        let anchors = MeshManager.shared.meshAnchors
        SceneGraphManager.shared.buildGraph(from: anchors)
        SceneGraphManager.shared.saveGraph()
        lastResult.meshRefined = true
        onMeshRefined?(true)
        completion?(true)
        state = .ready
        print("[SpatialAIManager] refineMesh: stub (\(anchors.count) anchors directos)")
    }

    // MARK: - Pipeline completo

    /// Ejecuta toda la cadena de IA sobre el frame actual.
    /// TODO: conectar SpatialInferencePipeline cuando AI/LoRA se reintegre.
    func runFullAnalysis(frame: ARFrame,
                         projectId: UUID? = nil,
                         completion: ((SpatialAIResult) -> Void)? = nil) {
        state = .processing
        // Stub: pipeline LoRA no disponible — resultado vacío
        lastResult = SpatialAIResult()

        if let pid = projectId {
            generateFloorplan(projectId: pid) { [weak self] url in
                guard let self = self else { return }
                self.lastResult.floorplanURL = url
                self.onResultReady?(self.lastResult)
                completion?(self.lastResult)
                self.state = .ready
            }
        } else {
            onResultReady?(lastResult)
            completion?(lastResult)
            state = .ready
        }
    }

    // MARK: - Semantic Mesh Refinement Pipeline

    /// Refina la geometría de paredes detectadas.
    /// TODO: conectar inferencia CoreML (LoRA wall segmentation) cuando esté listo.
    func refineWallGeometry(completion: ((Bool) -> Void)? = nil) {
        let anchors = MeshManager.shared.meshAnchors
        let wallAnchors = anchors.filter { anchor in
            if #available(iOS 13.4, *) {
                return anchor.geometry.faces.count > 0
            }
            return false
        }
        print("[SpatialAIManager] refineWallGeometry: \(wallAnchors.count) anchors de pared (placeholder)")
        completion?(true)
    }

    /// Refina la geometría del suelo detectado.
    /// TODO: conectar inferencia CoreML (LoRA floor segmentation) cuando esté listo.
    func refineFloorGeometry(completion: ((Bool) -> Void)? = nil) {
        let anchors = MeshManager.shared.meshAnchors
        print("[SpatialAIManager] refineFloorGeometry: \(anchors.count) anchors totales (placeholder)")
        completion?(true)
    }

    /// Elimina fragmentos de ruido del mesh (triángulos aislados, micro-clusters).
    /// TODO: umbral de ruido configurable vía CoreML cuando esté listo.
    func removeNoiseFragments(minTriangles: Int = 10,
                              completion: ((Int) -> Void)? = nil) {
        let anchors = MeshManager.shared.meshAnchors
        var removedCount = 0
        for anchor in anchors {
            let faceCount = anchor.geometry.faces.count
            if faceCount < minTriangles {
                removedCount += faceCount
            }
        }
        print("[SpatialAIManager] removeNoiseFragments: \(removedCount) caras de ruido (placeholder)")
        completion?(removedCount)
    }

    /// Suaviza los bordes del mesh para reducir artefactos de digitalización.
    /// TODO: aplicar Laplacian smoothing o inferencia CoreML cuando esté listo.
    func smoothMeshEdges(iterations: Int = 2,
                         completion: ((Bool) -> Void)? = nil) {
        print("[SpatialAIManager] smoothMeshEdges: \(iterations) iteraciones (placeholder)")
        completion?(true)
    }

    /// Ejecuta el pipeline completo de refinamiento semántico del mesh.
    func runRefinementPipeline(completion: ((Bool) -> Void)? = nil) {
        state = .processing
        print("[SpatialAIManager] runRefinementPipeline: iniciando")
        refineWallGeometry { [weak self] _ in
            self?.refineFloorGeometry { _ in
                self?.removeNoiseFragments { _ in
                    self?.smoothMeshEdges { success in
                        self?.state = .ready
                        print("[SpatialAIManager] runRefinementPipeline: completado")
                        completion?(success ?? false)
                    }
                }
            }
        }
    }

    // MARK: - Reset

    func reset() {
        lastResult = SpatialAIResult()
        state      = .idle
    }
}
