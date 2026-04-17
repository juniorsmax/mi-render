// MultiRoomMergeManager.swift
// Fusiona múltiples habitaciones RoomPlan en una estructura unificada.
//
// Flujo completo:
//   1. Escanear sala A  → saveRoomMap("sala",  session:, roomPlan:, projectId:)
//   2. Escanear cocina B → saveRoomMap("cocina", session:, roomPlan:, projectId:)
//   3. mergeToSceneGraph(["sala","cocina"], projectId:) →
//        • Calcula transforms de alineación entre habitaciones (ARWorldMap + floor-plane)
//        • Fusiona paredes / puertas / ventanas / objetos en SceneGraph unificado
//        • Exporta Documents/projects/{uuid}/sceneGraph.json
//
// La alineación usa:
//   • ARPlaneAnchor horizontales → empareja altura de suelo entre sesiones
//   • Centroides de anchors del ARWorldMap → alineación XZ si el escaneo fue continuo
//   • Desplazamiento acumulado de bounding box → fallback para escaneos independientes

import ARKit
import ModelIO
import MetalKit
import RoomPlan
import simd

// MARK: - SavedRoom (extendido)

struct SavedRoom: Codable {
    let name:                 String
    let timestamp:            Double
    let meshFileName:         String        // .miremesh
    let mapFileName:          String        // .worldmap
    let nodeCount:            Int
    let floorArea:            Double        // m²
    let volume:               Double        // m³
    // Nuevos campos (opcionales → backward-compatible)
    var roomPlanSnapshotFile: String?       // .roomsnapshot (JSON)
    var linkedProjectId:      String?       // UUID del proyecto Capacitor
}

// MARK: - CapturedSurface
// Representación Codable de una superficie RoomPlan.
// transform manual (t00–t33) para evitar depender de Codable de simd_float4x4.

struct CapturedSurface: Codable {
    let category:  String   // "wall" | "door" | "window" | nombre de objeto
    let widthM:    Float
    let heightM:   Float
    let depthM:    Float
    // Transform column-major
    let t00: Float; let t01: Float; let t02: Float; let t03: Float
    let t10: Float; let t11: Float; let t12: Float; let t13: Float
    let t20: Float; let t21: Float; let t22: Float; let t23: Float
    let t30: Float; let t31: Float; let t32: Float; let t33: Float

    var transform: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(t00, t01, t02, t03),
            SIMD4(t10, t11, t12, t13),
            SIMD4(t20, t21, t22, t23),
            SIMD4(t30, t31, t32, t33)
        ))
    }

    var position: SIMD3<Float> { SIMD3(t30, t31, t32) }
}

// MARK: - CapturedRoomSnapshot
// Instantánea Codable de una CapturedRoom (RoomPlan).
// Se guarda en .roomsnapshot junto al .worldmap.

struct CapturedRoomSnapshot: Codable {
    let roomName:   String
    let capturedAt: Date
    var walls:      [CapturedSurface]
    var doors:      [CapturedSurface]
    var windows:    [CapturedSurface]
    var objects:    [CapturedSurface]
}

// MARK: CapturedSurface init desde RoomPlan (iOS 16+)

@available(iOS 16.0, *)
private extension CapturedSurface {

    init(surface: CapturedRoom.Surface, category: String) {
        let d = surface.dimensions
        let t = surface.transform
        self.init(
            category: category,
            widthM:  d.x, heightM: d.y, depthM: d.z,
            t00: t.columns.0.x, t01: t.columns.0.y,
            t02: t.columns.0.z, t03: t.columns.0.w,
            t10: t.columns.1.x, t11: t.columns.1.y,
            t12: t.columns.1.z, t13: t.columns.1.w,
            t20: t.columns.2.x, t21: t.columns.2.y,
            t22: t.columns.2.z, t23: t.columns.2.w,
            t30: t.columns.3.x, t31: t.columns.3.y,
            t32: t.columns.3.z, t33: t.columns.3.w
        )
    }

    init(object: CapturedRoom.Object) {
        let d = object.dimensions
        let t = object.transform
        self.init(
            category: String(describing: object.category),
            widthM:  d.x, heightM: d.y, depthM: d.z,
            t00: t.columns.0.x, t01: t.columns.0.y,
            t02: t.columns.0.z, t03: t.columns.0.w,
            t10: t.columns.1.x, t11: t.columns.1.y,
            t12: t.columns.1.z, t13: t.columns.1.w,
            t20: t.columns.2.x, t21: t.columns.2.y,
            t22: t.columns.2.z, t23: t.columns.2.w,
            t30: t.columns.3.x, t31: t.columns.3.y,
            t32: t.columns.3.z, t33: t.columns.3.w
        )
    }
}

// MARK: - RoomAlignment

struct RoomAlignment {
    let roomName:  String
    /// Transform a aplicar a las coordenadas de esta habitación para
    /// colocarla en el sistema de coordenadas de referencia.
    let transform: simd_float4x4

    var translation: SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}

// MARK: - MultiRoomMergeManager

class MultiRoomMergeManager {

    static let shared = MultiRoomMergeManager()

    private let docsDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()
    private let fm = FileManager.default

    private(set) var savedRooms:  [SavedRoom] = []
    private(set) var mergedAsset: MDLAsset?

    // MARK: - Guardar habitación (API pública mejorada)

    /// Guarda ARWorldMap + mesh + snapshot RoomPlan + panorama de la sesión activa.
    /// - Parameters:
    ///   - name:      Nombre descriptivo de la habitación.
    ///   - session:   ARSession activa.
    ///   - roomPlan:  CapturedRoom de RoomPlan (nil en iOS < 16 o si no se usa).
    ///   - projectId: UUID del proyecto Capacitor para vincular la habitación.
    func saveRoomMap(name: String,
                     session: ARSession,
                     roomPlan: Any? = nil,
                     projectId: UUID? = nil,
                     completion: @escaping (Result<SavedRoom, Error>) -> Void) {

        session.getCurrentWorldMap { [weak self] worldMap, error in
            guard let self = self else { return }

            if let error = error { completion(.failure(error)); return }
            guard let worldMap = worldMap else {
                completion(.failure(MergeError.noWorldMap)); return
            }

            let ts       = Date().timeIntervalSince1970
            let baseName = "\(name)_\(Int(ts))"

            // 1. WorldMap
            let mapURL = self.docsDir.appendingPathComponent("\(baseName).worldmap")
            do {
                let data = try NSKeyedArchiver.archivedData(
                    withRootObject: worldMap, requiringSecureCoding: true)
                try data.write(to: mapURL, options: .atomic)
            } catch {
                completion(.failure(error)); return
            }

            // 2. Mesh
            guard MeshPersistenceManager.shared.save(
                anchors: MeshManager.shared.meshAnchors,
                named: baseName) != nil
            else {
                completion(.failure(MergeError.meshSaveFailed)); return
            }

            // 3. RoomPlan snapshot (iOS 16+)
            var snapshotFile: String? = nil
            if #available(iOS 16.0, *), let captured = roomPlan as? CapturedRoom {
                let snap = CapturedRoomSnapshot(
                    roomName:   name,
                    capturedAt: Date(),
                    walls:    captured.walls.map    { CapturedSurface(surface: $0, category: "wall") },
                    doors:    captured.doors.map    { CapturedSurface(surface: $0, category: "door") },
                    windows:  captured.windows.map  { CapturedSurface(surface: $0, category: "window") },
                    objects:  captured.objects.map  { CapturedSurface(object: $0) }
                )
                snapshotFile = self.saveRoomPlanSnapshot(snap, baseName: baseName)
            }

            // 4. Panorama
            PanoramaCaptureManager.shared.saveNodes()

            // 5. Registrar en índice
            let surfaces = MeshManager.shared.surfaces
            let room = SavedRoom(
                name:                 name,
                timestamp:            ts,
                meshFileName:         baseName,
                mapFileName:          baseName,
                nodeCount:            PanoramaCaptureManager.shared.nodes.count,
                floorArea:            Double(surfaces.floor),
                volume:               Double(VolumeCalculator.shared.totalVolume()),
                roomPlanSnapshotFile: snapshotFile,
                linkedProjectId:      projectId?.uuidString
            )
            self.savedRooms.append(room)
            self.persistRoomIndex()
            completion(.success(room))
        }
    }

    // MARK: - mergeToSceneGraph (API principal nueva)

    /// Fusiona habitaciones en un SceneGraph unificado y lo guarda como
    /// `Documents/projects/{projectId}/sceneGraph.json`.
    ///
    /// - Parameters:
    ///   - roomNames: nombres de habitaciones a fusionar (vacío = todas).
    ///   - projectId: UUID del proyecto de destino.
    ///   - completion: true si el JSON se guardó correctamente.
    func mergeToSceneGraph(roomNames: [String],
                           projectId: UUID,
                           completion: @escaping (Bool) -> Void) {

        let rooms = roomNames.isEmpty
            ? savedRooms
            : savedRooms.filter { roomNames.contains($0.name) }

        guard !rooms.isEmpty else {
            print("[MultiRoomMerge] mergeToSceneGraph: no hay habitaciones")
            completion(false)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Calcular alineaciones (habitación[0] = referencia)
            let alignments = self.computeAlignments(rooms: rooms)

            // 2. Construir SceneGraph unificado
            let graph = self.buildUnifiedSceneGraph(rooms:      rooms,
                                                    alignments: alignments,
                                                    projectId:  projectId)

            // 3. Guardar JSON
            self.saveSceneGraphJSON(graph, projectId: projectId, completion: completion)
        }
    }

    // MARK: - Alineación de transforms

    /// Calcula el RoomAlignment de cada habitación respecto a la primera (referencia).
    private func computeAlignments(rooms: [SavedRoom]) -> [String: RoomAlignment] {
        var result: [String: RoomAlignment] = [:]
        guard let reference = rooms.first else { return result }

        // Habitación de referencia: transform identidad
        result[reference.name] = RoomAlignment(
            roomName:  reference.name,
            transform: matrix_identity_float4x4
        )

        // Bounding box acumulado en X para colocación por defecto
        var accumulatedOffsetX: Float = boundingBoxWidth(room: reference) + 0.3

        for room in rooms.dropFirst() {
            let t = computeAlignmentTransform(room: room, reference: reference,
                                              fallbackOffsetX: accumulatedOffsetX)
            result[room.name] = RoomAlignment(roomName: room.name, transform: t)
            accumulatedOffsetX += boundingBoxWidth(room: room) + 0.3
        }
        return result
    }

    /// Calcula el transform de alineación para `room` respecto a `reference`.
    ///
    /// Estrategia (en orden de prioridad):
    ///   1. ARPlaneAnchor Y → empareja altura de suelo (requiere .worldmap en disco)
    ///   2. ARWorldMap feature-point centroid → alineación XZ si mismo coord system
    ///   3. Fallback: sólo offset X acumulado (habitaciones yuxtapuestas)
    private func computeAlignmentTransform(room: SavedRoom,
                                            reference: SavedRoom,
                                            fallbackOffsetX: Float) -> simd_float4x4 {
        var deltaY:  Float = 0
        var deltaX:  Float = fallbackOffsetX
        var deltaZ:  Float = 0
        var usedWorldMap = false

#if !targetEnvironment(simulator)
        if let mapRef  = loadWorldMap(named: reference.mapFileName),
           let mapRoom = loadWorldMap(named: room.mapFileName) {

            // — Alineación Y: emparejar suelo —
            let floorRef  = floorY(from: mapRef)
            let floorRoom = floorY(from: mapRoom)
            if let fr = floorRef, let fm = floorRoom {
                deltaY = fr - fm
            } else {
                print("[MultiRoomMerge] Warning: no floor reference found, deltaY = 0")
            }

            // — Alineación XZ: centroide de anchors —
            // Si ambos mapas comparten muchos anchors en posiciones similares,
            // están en el mismo sistema de coordenadas → no desplazar XZ.
            let centRef  = anchorCentroid(from: mapRef)
            let centRoom = anchorCentroid(from: mapRoom)
            let xzDist   = simd_length(centRef - centRoom)

            if xzDist < 0.5 {
                // Mismo sistema de coordenadas (escaneo continuo o re-localizado)
                deltaX = 0
                deltaZ = 0
            } else if xzDist < 15.0 {
                // Habitaciones adyacentes: usar delta de centroides proyectado en XZ
                deltaX = centRef.x - centRoom.x
                deltaZ = centRef.y - centRoom.y   // SIMD2: .x = worldX, .y = worldZ
            }
            // else: más de 15 m aparte → escaneos independientes, usar fallback X

            usedWorldMap = true
        }
#endif

        print("[MultiRoomMerge] align '\(room.name)' → "
              + "dx=\(String(format:"%.2f",deltaX)) "
              + "dy=\(String(format:"%.2f",deltaY)) "
              + "dz=\(String(format:"%.2f",deltaZ)) "
              + "(worldMap=\(usedWorldMap))")

        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(deltaX, deltaY, deltaZ, 1)
        return t
    }

    // MARK: - Construcción del SceneGraph unificado

    private func buildUnifiedSceneGraph(rooms: [SavedRoom],
                                         alignments: [String: RoomAlignment],
                                         projectId: UUID) -> SceneGraph {
        var graph = SceneGraph(projectId: projectId)

        // Nodo raíz: edificio completo
        var rootMeta: [String: String] = [
            "roomCount": "\(rooms.count)",
            "mergedAt":  ISO8601DateFormatter().string(from: Date()),
            "totalFloorArea": String(format: "%.2f",
                                     rooms.reduce(0.0) { $0 + $1.floorArea })
        ]
        let rootNode = SceneNode(
            type:     .room,
            label:    "edificio",
            metadata: rootMeta
        )
        graph.nodes[rootNode.id] = rootNode
        graph.rootId = rootNode.id

        var buildingChildIds: [UUID] = []

        for room in rooms {
            let alignment = alignments[room.name] ?? RoomAlignment(
                roomName: room.name, transform: matrix_identity_float4x4)

            // Nodo habitación
            var roomMeta: [String: String] = [
                "originalName": room.name,
                "floorArea":    String(format: "%.2f", room.floorArea),
                "volume":       String(format: "%.2f", room.volume),
                "timestamp":    "\(room.timestamp)"
            ]
            let roomNode = SceneNode(
                type:      .room,
                label:     room.name,
                transform: alignment.transform,
                metadata:  roomMeta
            )
            graph.nodes[roomNode.id] = roomNode
            buildingChildIds.append(roomNode.id)

            var roomChildIds: [UUID] = []

            // Añadir superficies RoomPlan si existe snapshot
            if let snapFile  = room.roomPlanSnapshotFile,
               let snapshot  = loadRoomPlanSnapshot(baseName: snapFile) {

                roomChildIds += addSurfaces(snapshot.walls,    type: .wall,    alignment: alignment.transform, to: &graph)
                roomChildIds += addSurfaces(snapshot.doors,    type: .door,    alignment: alignment.transform, to: &graph)
                roomChildIds += addSurfaces(snapshot.windows,  type: .window,  alignment: alignment.transform, to: &graph)
                roomChildIds += addSurfaces(snapshot.objects,  type: .furniture, alignment: alignment.transform, to: &graph)
            }

            // Añadir anchors de mesh como nodos .object
            if let anchors = MeshPersistenceManager.shared.load(named: room.meshFileName) {
                for anchor in anchors {
                    let localT  = anchor.transformMatrix
                    let worldT  = alignment.transform * localT   // aplica alineación
                    let domType = dominantType(classifications: anchor.classifications)
                    let node = SceneNode(
                        type:     domType,
                        label:    domType.rawValue,
                        transform: worldT,
                        metadata: [
                            "anchorId":  anchor.id,
                            "faceCount": "\(anchor.faceIndices.count / 3)",
                            "source":    "mesh"
                        ]
                    )
                    graph.nodes[node.id] = node
                    roomChildIds.append(node.id)
                }
            }

            graph.nodes[roomNode.id]?.children = roomChildIds
        }

        graph.nodes[rootNode.id]?.children = buildingChildIds
        graph.updatedAt = Date()
        print("[MultiRoomMerge] SceneGraph unificado: \(graph.nodes.count) nodos, "
              + "\(rooms.count) habitaciones")
        return graph
    }

    /// Inserta superficies en el grafo y devuelve sus IDs.
    private func addSurfaces(_ surfaces: [CapturedSurface],
                              type: SceneNodeType,
                              alignment: simd_float4x4,
                              to graph: inout SceneGraph) -> [UUID] {
        surfaces.map { surface in
            let worldT = alignment * surface.transform
            let node = SceneNode(
                type:      type,
                label:     surface.category,
                transform: worldT,
                metadata: [
                    "width":    String(format: "%.2f", surface.widthM),
                    "height":   String(format: "%.2f", surface.heightM),
                    "depth":    String(format: "%.2f", surface.depthM),
                    "category": surface.category,
                    "source":   "roomplan"
                ],
                boundingMin: SIMD3(-surface.widthM / 2, 0, -surface.depthM / 2),
                boundingMax: SIMD3( surface.widthM / 2,  surface.heightM, surface.depthM / 2)
            )
            graph.nodes[node.id] = node
            return node.id
        }
    }

    // MARK: - Persistencia SceneGraph JSON

    private func saveSceneGraphJSON(_ graph: SceneGraph,
                                     projectId: UUID,
                                     completion: @escaping (Bool) -> Void) {
        let dir = docsDir
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
        let url = dir.appendingPathComponent("sceneGraph.json")

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting     = .prettyPrinted
            let data = try encoder.encode(graph)
            try data.write(to: url, options: .atomic)
            print("[MultiRoomMerge] sceneGraph.json → "
                  + "\(data.count / 1024) KB, \(graph.nodes.count) nodos")
            DispatchQueue.main.async { completion(true) }
        } catch {
            print("[MultiRoomMerge] saveSceneGraphJSON error: \(error)")
            DispatchQueue.main.async { completion(false) }
        }
    }

    // MARK: - Persistencia snapshots RoomPlan

    @discardableResult
    private func saveRoomPlanSnapshot(_ snapshot: CapturedRoomSnapshot,
                                       baseName: String) -> String? {
        let fileName = "\(baseName).roomsnapshot"
        let url      = docsDir.appendingPathComponent(fileName)
        let encoder  = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot),
              (try? data.write(to: url, options: .atomic)) != nil
        else { return nil }
        return fileName.replacingOccurrences(of: ".roomsnapshot", with: "")
    }

    private func loadRoomPlanSnapshot(baseName: String) -> CapturedRoomSnapshot? {
        let url = docsDir.appendingPathComponent("\(baseName).roomsnapshot")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CapturedRoomSnapshot.self, from: data)
    }

    // MARK: - Fusión de mesh (legacy — se mantiene)

    func mergeRooms(_ names: [String]) -> MDLAsset {
        let asset = MDLAsset()
        let rooms = names.isEmpty ? savedRooms : savedRooms.filter { names.contains($0.name) }
        guard !rooms.isEmpty else { return asset }

        var offsetX: Float = 0
        for room in rooms {
            guard let persisted = MeshPersistenceManager.shared.load(named: room.meshFileName),
                  !persisted.isEmpty else { continue }

            var minP = SIMD3<Float>(repeating:  Float.greatestFiniteMagnitude)
            var maxP = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
            for p in persisted {
                for i in stride(from: 0, to: p.vertices.count - 2, by: 3) {
                    let v = SIMD3<Float>(p.vertices[i], p.vertices[i+1], p.vertices[i+2])
                    minP = simd_min(minP, v); maxP = simd_max(maxP, v)
                }
            }
            let center = (minP + maxP) * 0.5
            let width  = maxP.x - minP.x
            let tx = offsetX - center.x; let ty = -center.y; let tz = -center.z

            for p in persisted {
                var verts = p.vertices
                for i in stride(from: 0, to: verts.count - 2, by: 3) {
                    verts[i] += tx; verts[i+1] += ty; verts[i+2] += tz
                }
                if let mesh = buildMDLMesh(vertices: verts, indices: p.faceIndices) {
                    asset.add(mesh)
                }
            }
            offsetX += width + 0.5
        }
        mergedAsset = asset
        return asset
    }

    func mergeAll() -> MDLAsset { mergeRooms([]) }

    // MARK: - Índice de habitaciones

    func loadRoomIndex() {
        let url = docsDir.appendingPathComponent("rooms_index.json")
        guard let data  = try? Data(contentsOf: url),
              let rooms = try? JSONDecoder().decode([SavedRoom].self, from: data)
        else { return }
        savedRooms = rooms
    }

    private func persistRoomIndex() {
        let url = docsDir.appendingPathComponent("rooms_index.json")
        if let data = try? JSONEncoder().encode(savedRooms) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func deleteRoom(named name: String) {
        guard let room = savedRooms.first(where: { $0.name == name }) else { return }
        try? fm.removeItem(at: docsDir.appendingPathComponent("\(room.meshFileName).miremesh"))
        try? fm.removeItem(at: docsDir.appendingPathComponent("\(room.mapFileName).worldmap"))
        if let sf = room.roomPlanSnapshotFile {
            try? fm.removeItem(at: docsDir.appendingPathComponent("\(sf).roomsnapshot"))
        }
        savedRooms.removeAll { $0.name == name }
        persistRoomIndex()
    }

    // MARK: - Serialización Capacitor

    func toDictionary() -> [String: Any] {
        [
            "roomCount": savedRooms.count,
            "rooms": savedRooms.map { r in
                ["name":      r.name,
                 "timestamp": r.timestamp,
                 "floorArea": r.floorArea,
                 "volume":    r.volume,
                 "nodeCount": r.nodeCount,
                 "hasRoomPlan": r.roomPlanSnapshotFile != nil
                ] as [String: Any]
            }
        ]
    }

    // MARK: - Helpers ARWorldMap

#if !targetEnvironment(simulator)
    private func loadWorldMap(named name: String) -> ARWorldMap? {
        let url = docsDir.appendingPathComponent("\(name).worldmap")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
    }

    /// Y mínima de los ARPlaneAnchor horizontales del mapa (altura del suelo).
    private func floorY(from map: ARWorldMap) -> Float? {
        let planes = map.anchors
            .compactMap { $0 as? ARPlaneAnchor }
            .filter { $0.alignment == .horizontal }
        guard !planes.isEmpty else { return nil }
        return planes.map { $0.transform.columns.3.y }.min()
    }

    /// Centroide XZ de todos los anchors del mapa.
    private func anchorCentroid(from map: ARWorldMap) -> SIMD2<Float> {
        let positions = map.anchors.map {
            SIMD2<Float>($0.transform.columns.3.x, $0.transform.columns.3.z)
        }
        guard !positions.isEmpty else { return .zero }
        let sum = positions.reduce(SIMD2<Float>.zero, +)
        return sum / Float(positions.count)
    }
#endif

    // MARK: - Helpers de bounding box

    private func boundingBoxWidth(room: SavedRoom) -> Float {
        guard let anchors = MeshPersistenceManager.shared.load(named: room.meshFileName),
              !anchors.isEmpty else { return 3.0 }
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        for anchor in anchors {
            let t = anchor.transformMatrix
            for i in stride(from: 0, to: anchor.vertices.count - 2, by: 3) {
                let lv = SIMD4<Float>(anchor.vertices[i],
                                      anchor.vertices[i+1],
                                      anchor.vertices[i+2], 1)
                let wv = t * lv
                minX = Swift.min(minX, wv.x)
                maxX = Swift.max(maxX, wv.x)
            }
        }
        return maxX - minX > 0 ? maxX - minX : 3.0
    }

    /// Infiere SceneNodeType a partir de las clasificaciones de las caras.
    private func dominantType(classifications: [UInt8]) -> SceneNodeType {
        guard !classifications.isEmpty else { return .object }
        var counts: [UInt8: Int] = [:]
        for c in classifications { counts[c, default: 0] += 1 }
        guard let dom = counts.max(by: { $0.value < $1.value })?.key else { return .object }
        switch dom {
        case 1: return .wall
        case 2: return .floor
        case 3: return .ceiling
        case 4: return .door
        case 5: return .window
        case 6, 7: return .furniture
        default: return .object
        }
    }

    // MARK: - Helper MDLMesh

    private func buildMDLMesh(vertices: [Float], indices: [UInt32]) -> MDLMesh? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let alloc  = MTKMeshBufferAllocator(device: device)
        let vData  = Data(bytes: vertices, count: vertices.count * MemoryLayout<Float>.size)
        let iData  = Data(bytes: indices,  count: indices.count  * MemoryLayout<UInt32>.size)
        let vBuf   = alloc.newBuffer(with: vData, type: .vertex)
        let iBuf   = alloc.newBuffer(with: iData, type: .index)
        let desc   = MDLVertexDescriptor()
        desc.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)
        let sub = MDLSubmesh(indexBuffer: iBuf, indexCount: indices.count,
                             indexType: .uInt32, geometryType: .triangles, material: nil)
        return MDLMesh(vertexBuffer: vBuf, vertexCount: vertices.count / 3,
                       descriptor: desc, submeshes: [sub])
    }

    // MARK: - Errores

    enum MergeError: Error {
        case noWorldMap
        case meshSaveFailed
        case alignmentFailed
        case noRoomsFound
    }
}
