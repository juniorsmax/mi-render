// MultiRoomMergeManager.swift
// Fusiona múltiples habitaciones escaneadas en un único modelo 3D.
// Usa ARWorldMap para alinear coordenadas entre sesiones.
//
// Flujo:
//   1. Escanear habitación A → saveRoomMap("sala")
//   2. Escanear habitación B → saveRoomMap("cocina")
//   3. mergeRooms(["sala","cocina"]) → devuelve MDLAsset unificado

import ARKit
import ModelIO
import MetalKit
import simd

// MARK: - Datos de una habitación guardada

struct SavedRoom: Codable {
    let name:         String
    let timestamp:    Double
    let meshFileName: String        // .miremesh
    let mapFileName:  String        // .worldmap
    let nodeCount:    Int
    let floorArea:    Double        // m²
    let volume:       Double        // m³
}

// MARK: - MultiRoomMergeManager

class MultiRoomMergeManager {

    static let shared = MultiRoomMergeManager()

    private let docsDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    private(set) var savedRooms: [SavedRoom] = []
    private(set) var mergedAsset: MDLAsset?

    // MARK: - Guardar habitación actual

    /// Guarda el ARWorldMap + mesh + panorama de la sesión actual.
    func saveRoomMap(name: String,
                     session: ARSession,
                     completion: @escaping (Result<SavedRoom, Error>) -> Void) {

        session.getCurrentWorldMap { [weak self] worldMap, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(error))
                return
            }
            guard let worldMap = worldMap else {
                completion(.failure(MergeError.noWorldMap))
                return
            }

            let ts       = Date().timeIntervalSince1970
            let baseName = "\(name)_\(Int(ts))"

            // 1. Guardar world map
            let mapURL = self.docsDir.appendingPathComponent("\(baseName).worldmap")
            do {
                let mapData = try NSKeyedArchiver.archivedData(
                    withRootObject: worldMap, requiringSecureCoding: true)
                try mapData.write(to: mapURL, options: .atomic)
            } catch {
                completion(.failure(error))
                return
            }

            // 2. Guardar mesh
            let meshURL = MeshPersistenceManager.shared.save(
                anchors: MeshManager.shared.meshAnchors,
                named: baseName
            )
            guard meshURL != nil else {
                completion(.failure(MergeError.meshSaveFailed))
                return
            }

            // 3. Guardar panorama
            PanoramaCaptureManager.shared.save(named: baseName)

            // 4. Registrar habitación
            let surfaces = MeshManager.shared.surfaces
            let volume   = Double(VolumeCalculator.shared.totalVolume())
            let room = SavedRoom(
                name:         name,
                timestamp:    ts,
                meshFileName: baseName,
                mapFileName:  baseName,
                nodeCount:    PanoramaCaptureManager.shared.nodes.count,
                floorArea:    Double(surfaces.floor),
                volume:       volume
            )

            self.savedRooms.append(room)
            self.persistRoomIndex()
            completion(.success(room))
        }
    }

    // MARK: - Fusionar habitaciones

    /// Fusiona los meshes de las habitaciones indicadas en un único MDLAsset.
    /// Alineación: traslada cada habitación por el centroide de su bounding box.
    func mergeRooms(_ names: [String]) -> MDLAsset {
        let asset = MDLAsset()

        // Filtrar habitaciones que existen
        let rooms = names.isEmpty
            ? savedRooms
            : savedRooms.filter { names.contains($0.name) }

        guard !rooms.isEmpty else { return asset }

        var offsetX: Float = 0  // Desplazamiento acumulado en X para cada habitación

        for room in rooms {
            guard let persisted = MeshPersistenceManager.shared.load(named: room.meshFileName),
                  !persisted.isEmpty else { continue }

            // Calcular bbox del conjunto de vértices de esta habitación
            var minP = SIMD3<Float>(repeating:  Float.greatestFiniteMagnitude)
            var maxP = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
            for p in persisted {
                let verts = p.vertices
                for i in stride(from: 0, to: verts.count - 2, by: 3) {
                    let v = SIMD3<Float>(verts[i], verts[i+1], verts[i+2])
                    minP = simd_min(minP, v)
                    maxP = simd_max(maxP, v)
                }
            }
            let center = (minP + maxP) * 0.5
            let width  = maxP.x - minP.x

            // Trasladar vértices: centrar en Y/Z y desplazar en X
            let tx = offsetX - center.x
            let ty = -center.y
            let tz = -center.z

            for p in persisted {
                var verts = p.vertices
                for i in stride(from: 0, to: verts.count - 2, by: 3) {
                    verts[i]     += tx
                    verts[i + 1] += ty
                    verts[i + 2] += tz
                }
                if let mesh = buildMDLMesh(vertices: verts, indices: p.faceIndices) {
                    asset.add(mesh)
                }
            }

            offsetX += width + 0.5   // 0.5 m de margen entre habitaciones
        }

        mergedAsset = asset
        return asset
    }

    /// Fusiona TODAS las habitaciones guardadas.
    func mergeAll() -> MDLAsset {
        mergeRooms([])
    }

    // MARK: - Listar habitaciones

    func loadRoomIndex() {
        let url = docsDir.appendingPathComponent("rooms_index.json")
        guard let data = try? Data(contentsOf: url),
              let rooms = try? JSONDecoder().decode([SavedRoom].self, from: data) else { return }
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
        try? FileManager.default.removeItem(
            at: docsDir.appendingPathComponent("\(room.meshFileName).miremesh"))
        try? FileManager.default.removeItem(
            at: docsDir.appendingPathComponent("\(room.mapFileName).worldmap"))
        savedRooms.removeAll { $0.name == name }
        persistRoomIndex()
    }

    // MARK: - Serialización para Capacitor

    func toDictionary() -> [String: Any] {
        [
            "roomCount": savedRooms.count,
            "rooms": savedRooms.map { r in
                [
                    "name":      r.name,
                    "timestamp": r.timestamp,
                    "floorArea": r.floorArea,
                    "volume":    r.volume,
                    "nodeCount": r.nodeCount,
                ] as [String: Any]
            }
        ]
    }

    // MARK: - Helper MDLMesh

    private func buildMDLMesh(vertices: [Float], indices: [UInt32]) -> MDLMesh? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let allocator = MTKMeshBufferAllocator(device: device)

        let vData = Data(bytes: vertices, count: vertices.count * MemoryLayout<Float>.size)
        let iData = Data(bytes: indices,  count: indices.count  * MemoryLayout<UInt32>.size)
        let vBuf  = allocator.newBuffer(with: vData, type: .vertex)
        let iBuf  = allocator.newBuffer(with: iData, type: .index)

        let desc = MDLVertexDescriptor()
        desc.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

        let sub  = MDLSubmesh(indexBuffer: iBuf, indexCount: indices.count,
                              indexType: .uInt32, geometryType: .triangles, material: nil)
        return MDLMesh(vertexBuffer: vBuf,
                       vertexCount: vertices.count / 3,
                       descriptor: desc,
                       submeshes: [sub])
    }

    // MARK: - Errores

    enum MergeError: Error {
        case noWorldMap
        case meshSaveFailed
        case alignmentFailed
    }
}
