// SceneGraphManager.swift
// Representa el entorno escaneado como grafo semántico jerárquico.
// Construye SceneNode desde ARMeshAnchor, RoomPlan y anchors ARKit.
// Persiste el grafo en Documents/projects/{uuid}/sceneGraph.json

import ARKit
import RoomPlan
import simd

// MARK: - Tipo de nodo

enum SceneNodeType: String, Codable, CaseIterable {
    case room
    case wall
    case floor
    case ceiling
    case door
    case window
    case object
    case furniture
    case unknown
}

// MARK: - SceneNode

struct SceneNode: Identifiable, Codable {

    let id:       UUID
    var type:     SceneNodeType
    var label:    String               // nombre legible: "pared norte", "sofá", etc.
    var children: [UUID]               // IDs de nodos hijos
    var metadata: [String: String]     // pares clave–valor libres

    // Transform column-major (simd_float4x4 manual Codable)
    var t00: Float; var t01: Float; var t02: Float; var t03: Float
    var t10: Float; var t11: Float; var t12: Float; var t13: Float
    var t20: Float; var t21: Float; var t22: Float; var t23: Float
    var t30: Float; var t31: Float; var t32: Float; var t33: Float

    // Bounding box en metros
    var minX: Float; var minY: Float; var minZ: Float
    var maxX: Float; var maxY: Float; var maxZ: Float

    // MARK: Computed

    var transform: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(t00, t01, t02, t03),
            SIMD4(t10, t11, t12, t13),
            SIMD4(t20, t21, t22, t23),
            SIMD4(t30, t31, t32, t33)
        ))
    }

    var position: SIMD3<Float> {
        SIMD3(t30, t31, t32)
    }

    var boundingSize: SIMD3<Float> {
        SIMD3(maxX - minX, maxY - minY, maxZ - minZ)
    }

    var boundingCenter: SIMD3<Float> {
        SIMD3((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
    }

    // MARK: Init

    init(id: UUID = UUID(),
         type: SceneNodeType,
         label: String,
         transform t: simd_float4x4 = matrix_identity_float4x4,
         children: [UUID] = [],
         metadata: [String: String] = [:],
         boundingMin: SIMD3<Float> = .zero,
         boundingMax: SIMD3<Float> = .zero) {

        self.id       = id
        self.type     = type
        self.label    = label
        self.children = children
        self.metadata = metadata

        t00 = t.columns.0.x; t01 = t.columns.0.y; t02 = t.columns.0.z; t03 = t.columns.0.w
        t10 = t.columns.1.x; t11 = t.columns.1.y; t12 = t.columns.1.z; t13 = t.columns.1.w
        t20 = t.columns.2.x; t21 = t.columns.2.y; t22 = t.columns.2.z; t23 = t.columns.2.w
        t30 = t.columns.3.x; t31 = t.columns.3.y; t32 = t.columns.3.z; t33 = t.columns.3.w

        minX = boundingMin.x; minY = boundingMin.y; minZ = boundingMin.z
        maxX = boundingMax.x; maxY = boundingMax.y; maxZ = boundingMax.z
    }
}

// MARK: - SceneGraph

struct SceneGraph: Codable {
    var rootId:    UUID?
    var nodes:     [UUID: SceneNode]
    var createdAt: Date
    var updatedAt: Date
    var projectId: UUID?

    init(projectId: UUID? = nil) {
        self.rootId    = nil
        self.nodes     = [:]
        self.createdAt = Date()
        self.updatedAt = Date()
        self.projectId = projectId
    }

    // Devuelve nodo raíz (tipo .room) si existe
    var rootNode: SceneNode? {
        guard let rootId = rootId else { return nil }
        return nodes[rootId]
    }

    // Hijos directos de un nodo
    func children(of node: SceneNode) -> [SceneNode] {
        node.children.compactMap { nodes[$0] }
    }

    // Todos los nodos de un tipo
    func nodes(ofType type: SceneNodeType) -> [SceneNode] {
        nodes.values.filter { $0.type == type }
    }
}

// MARK: - SceneGraphManager

class SceneGraphManager {

    static let shared = SceneGraphManager()

    private(set) var graph = SceneGraph()
    private var projectId: UUID?

    private var graphURL: URL? {
        guard let id = projectId else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs
            .appendingPathComponent("projects")
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent("sceneGraph.json")
    }

    // MARK: - Configurar proyecto activo

    func configure(projectId: UUID) {
        self.projectId = projectId
        graph = SceneGraph(projectId: projectId)
    }

    // MARK: - buildGraph desde ARMeshAnchor

    /// Construye el grafo desde anchors ARKit clasificados semánticamente.
    func buildGraph(from anchors: [ARMeshAnchor]) {
        graph = SceneGraph(projectId: projectId)

        // Nodo raíz de habitación
        let roomNode = SceneNode(
            type:     .room,
            label:    "habitación",
            metadata: [
                "floorArea": String(format: "%.2f", MeshManager.shared.surfaces.floor),
                "volume":    String(format: "%.2f", VolumeCalculator.shared.totalVolume()),
                "anchorCount": "\(anchors.count)"
            ]
        )
        graph.nodes[roomNode.id] = roomNode
        graph.rootId = roomNode.id

        var childIds: [UUID] = []

        for anchor in anchors {
            let node = buildNode(from: anchor)
            graph.nodes[node.id] = node
            childIds.append(node.id)
        }

        // Actualizar hijos del nodo raíz
        graph.nodes[roomNode.id]?.children = childIds
        graph.updatedAt = Date()

        print("[SceneGraphManager] grafo construido: \(graph.nodes.count) nodos")
    }

    // MARK: - buildGraph desde RoomPlan (iOS 16+)

    @available(iOS 16.0, *)
    func buildGraph(from roomPlan: CapturedRoom) {
        graph = SceneGraph(projectId: projectId)

        let surfaces = MeshManager.shared.surfaces
        let roomNode = SceneNode(
            type:  .room,
            label: "habitación",
            metadata: [
                "floorArea": String(format: "%.2f", surfaces.floor),
                "wallArea":  String(format: "%.2f", surfaces.wall),
                "volume":    String(format: "%.2f", VolumeCalculator.shared.totalVolume()),
                "wallCount": "\(roomPlan.walls.count)",
                "doorCount": "\(roomPlan.doors.count)",
                "windowCount": "\(roomPlan.windows.count)",
                "objectCount": "\(roomPlan.objects.count)"
            ]
        )
        graph.nodes[roomNode.id] = roomNode
        graph.rootId = roomNode.id

        var childIds: [UUID] = []

        // Paredes
        for wall in roomPlan.walls {
            let node = SceneNode(
                type:     .wall,
                label:    "pared",
                transform: wall.transform,
                metadata: [
                    "width":     String(format: "%.2f", wall.dimensions.x),
                    "height":    String(format: "%.2f", wall.dimensions.y),
                    "thickness": String(format: "%.2f", wall.dimensions.z)
                ],
                boundingMin: SIMD3(-wall.dimensions.x / 2, 0, -wall.dimensions.z / 2),
                boundingMax: SIMD3( wall.dimensions.x / 2, wall.dimensions.y,
                                    wall.dimensions.z / 2)
            )
            graph.nodes[node.id] = node
            childIds.append(node.id)
        }

        // Puertas
        for door in roomPlan.doors {
            let node = SceneNode(
                type:     .door,
                label:    "puerta",
                transform: door.transform,
                metadata: [
                    "width":  String(format: "%.2f", door.dimensions.x),
                    "height": String(format: "%.2f", door.dimensions.y)
                ],
                boundingMin: SIMD3(-door.dimensions.x / 2, 0, -0.05),
                boundingMax: SIMD3( door.dimensions.x / 2, door.dimensions.y, 0.05)
            )
            graph.nodes[node.id] = node
            childIds.append(node.id)
        }

        // Ventanas
        for window in roomPlan.windows {
            let node = SceneNode(
                type:     .window,
                label:    "ventana",
                transform: window.transform,
                metadata: [
                    "width":  String(format: "%.2f", window.dimensions.x),
                    "height": String(format: "%.2f", window.dimensions.y)
                ],
                boundingMin: SIMD3(-window.dimensions.x / 2, -window.dimensions.y / 2, -0.05),
                boundingMax: SIMD3( window.dimensions.x / 2,  window.dimensions.y / 2,  0.05)
            )
            graph.nodes[node.id] = node
            childIds.append(node.id)
        }

        // Objetos / muebles
        for object in roomPlan.objects {
            let node = SceneNode(
                type:     .furniture,
                label:    String(describing: object.category),
                transform: object.transform,
                metadata: [
                    "category": String(describing: object.category),
                    "width":    String(format: "%.2f", object.dimensions.x),
                    "height":   String(format: "%.2f", object.dimensions.y),
                    "depth":    String(format: "%.2f", object.dimensions.z)
                ],
                boundingMin: -(object.dimensions / 2),
                boundingMax:   object.dimensions / 2
            )
            graph.nodes[node.id] = node
            childIds.append(node.id)
        }

        graph.nodes[roomNode.id]?.children = childIds
        graph.updatedAt = Date()

        print("[SceneGraphManager] grafo RoomPlan: \(graph.nodes.count) nodos")
    }

    // MARK: - Guardar grafo

    func saveGraph(completion: ((Bool) -> Void)? = nil) {
        guard let url = graphURL else {
            print("[SceneGraphManager] saveGraph: projectId no configurado")
            completion?(false)
            return
        }

        let graphToSave = graph
        DispatchQueue.global(qos: .utility).async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting     = .prettyPrinted
                let data = try encoder.encode(graphToSave)
                try data.write(to: url, options: .atomic)
                print("[SceneGraphManager] grafo guardado → sceneGraph.json "
                      + "(\(data.count / 1024) KB, \(graphToSave.nodes.count) nodos)")
                DispatchQueue.main.async { completion?(true) }
            } catch {
                print("[SceneGraphManager] saveGraph error: \(error)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    // MARK: - Cargar grafo

    func loadGraph(projectId: UUID, completion: ((Bool) -> Void)? = nil) {
        self.projectId = projectId

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url  = docs
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("sceneGraph.json")

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[SceneGraphManager] sceneGraph.json no encontrado para \(projectId)")
            completion?(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let data    = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let loaded  = try decoder.decode(SceneGraph.self, from: data)

                DispatchQueue.main.async {
                    self?.graph = loaded
                    print("[SceneGraphManager] grafo cargado ← sceneGraph.json "
                          + "(\(loaded.nodes.count) nodos)")
                    completion?(true)
                }
            } catch {
                print("[SceneGraphManager] loadGraph error: \(error)")
                DispatchQueue.main.async { completion?(false) }
            }
        }
    }

    // MARK: - Mutación del grafo

    func addNode(_ node: SceneNode, parentId: UUID? = nil) {
        graph.nodes[node.id] = node
        if let pid = parentId ?? graph.rootId {
            graph.nodes[pid]?.children.append(node.id)
        }
        graph.updatedAt = Date()
    }

    func removeNode(id: UUID) {
        graph.nodes.removeValue(forKey: id)
        // Limpiar referencias huérfanas
        for key in graph.nodes.keys {
            graph.nodes[key]?.children.removeAll { $0 == id }
        }
        graph.updatedAt = Date()
    }

    func updateNode(id: UUID, update: (inout SceneNode) -> Void) {
        guard var node = graph.nodes[id] else { return }
        update(&node)
        graph.nodes[id] = node
        graph.updatedAt = Date()
    }

    // MARK: - Serialización para Capacitor / JavaScript

    func toDictionary() -> [String: Any] {
        var nodeList: [[String: Any]] = []
        for node in graph.nodes.values {
            nodeList.append([
                "id":       node.id.uuidString,
                "type":     node.type.rawValue,
                "label":    node.label,
                "children": node.children.map { $0.uuidString },
                "metadata": node.metadata,
                "position": ["x": node.position.x,
                             "y": node.position.y,
                             "z": node.position.z],
                "size":     ["x": node.boundingSize.x,
                             "y": node.boundingSize.y,
                             "z": node.boundingSize.z]
            ] as [String: Any])
        }
        return [
            "rootId":    graph.rootId?.uuidString ?? "",
            "nodeCount": graph.nodes.count,
            "nodes":     nodeList
        ]
    }

    // MARK: - Helpers privados

    private func buildNode(from anchor: ARMeshAnchor) -> SceneNode {
        let type  = nodeType(for: anchor)
        let label = type.rawValue

        // Bounding box en espacio local del anchor
        let geo    = anchor.geometry
        let vBuf   = geo.vertices
        let vPtr   = vBuf.buffer.contents()
            .advanced(by: vBuf.offset)
            .assumingMemoryBound(to: Float.self)
        let stride = vBuf.stride / MemoryLayout<Float>.stride

        var minP = SIMD3<Float>(repeating:  Float.greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for i in 0..<vBuf.count {
            let v = SIMD3<Float>(vPtr[i*stride], vPtr[i*stride+1], vPtr[i*stride+2])
            minP = simd_min(minP, v)
            maxP = simd_max(maxP, v)
        }

        return SceneNode(
            type:        type,
            label:       label,
            transform:   anchor.transform,
            metadata:    ["anchorId": anchor.identifier.uuidString,
                          "faceCount": "\(anchor.geometry.faces.count)"],
            boundingMin: minP,
            boundingMax: maxP
        )
    }

    /// Infiere el tipo de nodo desde la clasificación mayoritaria del anchor.
    private func nodeType(for anchor: ARMeshAnchor) -> SceneNodeType {
        var counts: [ARMeshClassification: Int] = [:]
        let geo = anchor.geometry
        for f in 0..<geo.faces.count {
            let cls = geo.faceClassification(at: f)
            counts[cls, default: 0] += 1
        }
        guard let dominant = counts.max(by: { $0.value < $1.value })?.key else {
            return .unknown
        }
        switch dominant {
        case .wall:    return .wall
        case .floor:   return .floor
        case .ceiling: return .ceiling
        case .door:    return .door
        case .window:  return .window
        case .table, .seat: return .furniture
        default:       return .object
        }
    }
}

