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

// MARK: - Colaboración multiusuario

extension WorldMapManager {

    func collaborationData(from session: ARSession) -> Data? {
        // ARCollaborationData se obtiene vía ARSessionDelegate
        // en func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData)
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
