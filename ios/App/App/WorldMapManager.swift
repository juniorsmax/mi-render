// WorldMapManager.swift
// Persistencia espacial del entorno con ARWorldMap.
// Permite guardar, restaurar y comparar escaneos.
// Base para multiusuario y re-scan inteligente.

import ARKit

class WorldMapManager {

    static let shared = WorldMapManager()

    private let saveDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // MARK: - Guardar mapa del entorno actual

    func saveWorldMap(session: ARSession,
                      named name: String,
                      completion: @escaping (Result<URL, Error>) -> Void) {

        session.getCurrentWorldMap { worldMap, error in

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let worldMap = worldMap else {
                completion(.failure(WorldMapError.noMap))
                return
            }

            do {
                let data = try NSKeyedArchiver.archivedData(
                    withRootObject: worldMap,
                    requiringSecureCoding: true
                )

                let url = self.saveDirectory.appendingPathComponent("\(name).arworldmap")
                try data.write(to: url, options: .atomic)
                completion(.success(url))

            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Cargar mapa guardado

    func loadWorldMap(named name: String) -> ARWorldMap? {
        let url = saveDirectory.appendingPathComponent("\(name).arworldmap")

        guard let data = try? Data(contentsOf: url) else { return nil }

        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        )
    }

    // MARK: - Restaurar sesión desde mapa guardado

    func restoreSession(from map: ARWorldMap, session: ARSession) {
        let config = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }

        config.initialWorldMap = map
        config.planeDetection  = [.horizontal, .vertical]

        session.run(config, options: [.resetTracking])
    }

    // MARK: - Listar mapas guardados

    func savedMaps() -> [String] {
        let files = try? FileManager.default.contentsOfDirectory(atPath: saveDirectory.path)
        return (files ?? [])
            .filter { $0.hasSuffix(".arworldmap") }
            .map    { $0.replacingOccurrences(of: ".arworldmap", with: "") }
    }

    // MARK: - Eliminar mapa

    func deleteMap(named name: String) throws {
        let url = saveDirectory.appendingPathComponent("\(name).arworldmap")
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - Merge multi-habitación

extension WorldMapManager {

    // Índice de habitaciones guardadas
    private var roomIndexURL: URL {
        saveDirectory.appendingPathComponent("room_index.json")
    }

    struct RoomEntry: Codable {
        let name:       String
        let mapFile:    String   // .arworldmap
        let meshFile:   String   // .miremesh
        let timestamp:  Double
        let floorArea:  Double
    }

    // MARK: Guardar habitación completa

    /// Guarda ARWorldMap + mesh de la habitación actual con nombre dado.
    func saveRoom(name: String,
                  session: ARSession,
                  completion: @escaping (Result<RoomEntry, Error>) -> Void) {

        let ts       = Date().timeIntervalSince1970
        let baseName = "\(name)_\(Int(ts))"

        // 1. Guardar world map
        saveWorldMap(session: session, named: baseName) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success:
                // 2. Guardar mesh
                MeshPersistenceManager.shared.save(
                    anchors: MeshManager.shared.meshAnchors,
                    named: baseName
                )
                // 3. Registrar en índice
                let entry = RoomEntry(
                    name:      name,
                    mapFile:   baseName,
                    meshFile:  baseName,
                    timestamp: ts,
                    floorArea: Double(MeshManager.shared.surfaces.floor)
                )
                self.addRoomToIndex(entry)
                completion(.success(entry))
            }
        }
    }

    // MARK: Merge: combinar coordenadas de múltiples habitaciones

    /// Carga los meshes de todas las habitaciones guardadas y los alinea en un
    /// sistema de coordenadas compartido usando el transform del anchor del world map.
    /// Devuelve el número de habitaciones fusionadas y la lista de archivos .miremesh.
    func mergeAllRooms() -> (roomCount: Int, meshFiles: [String]) {
        let rooms = loadRoomIndex()
        return (rooms.count, rooms.map { $0.meshFile })
    }

    /// Fusiona solo las habitaciones indicadas por nombre.
    func mergeRooms(named names: [String]) -> [RoomEntry] {
        loadRoomIndex().filter { names.contains($0.name) }
    }

    // MARK: Alineación de coordenadas

    /// Calcula la traslación necesaria para alinear dos mapas usando sus centroides de suelo.
    /// Úsalo para desplazar el mesh de una habitación al añadirla al modelo completo.
    func alignmentOffset(from sourceAnchors: [ARMeshAnchor],
                         to targetAnchors: [ARMeshAnchor]) -> SIMD3<Float> {
        func centroid(_ anchors: [ARMeshAnchor]) -> SIMD3<Float> {
            guard !anchors.isEmpty else { return .zero }
            let sum = anchors.reduce(SIMD3<Float>.zero) { acc, a in
                acc + SIMD3<Float>(a.transform.columns.3.x,
                                   a.transform.columns.3.y,
                                   a.transform.columns.3.z)
            }
            return sum / Float(anchors.count)
        }
        return centroid(targetAnchors) - centroid(sourceAnchors)
    }

    // MARK: Índice privado

    func loadRoomIndex() -> [RoomEntry] {
        guard let data = try? Data(contentsOf: roomIndexURL),
              let rooms = try? JSONDecoder().decode([RoomEntry].self, from: data)
        else { return [] }
        return rooms
    }

    private func addRoomToIndex(_ entry: RoomEntry) {
        var rooms = loadRoomIndex()
        rooms.append(entry)
        if let data = try? JSONEncoder().encode(rooms) {
            try? data.write(to: roomIndexURL, options: .atomic)
        }
    }

    func deleteRoomFromIndex(name: String) {
        var rooms = loadRoomIndex().filter { $0.name != name }
        if let data = try? JSONEncoder().encode(rooms) {
            try? data.write(to: roomIndexURL, options: .atomic)
        }
    }

    func roomIndexDictionary() -> [[String: Any]] {
        loadRoomIndex().map { r in
            ["name": r.name, "timestamp": r.timestamp, "floorArea": r.floorArea] as [String: Any]
        }
    }
}

// MARK: - Colaboración multiusuario

extension WorldMapManager {

    func collaborationData(from session: ARSession) -> Data? {
        return nil
    }

    func applyCollaborationData(_ data: ARSession.CollaborationData,
                                 to session: ARSession) {
        session.update(with: data)
    }
}

// MARK: - Errores

enum WorldMapError: LocalizedError {
    case noMap
    var errorDescription: String? {
        switch self {
        case .noMap: return "No se pudo obtener el mapa del entorno"
        }
    }
}
