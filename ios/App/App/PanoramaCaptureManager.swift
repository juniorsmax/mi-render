// PanoramaCaptureManager.swift
// Registra la posición de la cámara durante el escaneo para crear nodos de navegación.
// Genera una trayectoria navegable para recorrido virtual posterior.
//
// Uso:
//   - Llamar captureNode(from: frame) en cada ARFrame relevante
//   - Al terminar: getTrajectory() devuelve todos los nodos
//   - Los nodos se pueden usar para panoramas esféricos o recorridos virtuales

import ARKit
import simd

// MARK: - Nodo de navegación

struct PanoramaNode: Codable {
    let id:         Int
    let timestamp:  Double          // segundos desde epoch
    let position:   [Float]         // SIMD3<Float> [x, y, z]
    let rotation:   [Float]         // quaternion [x, y, z, w]
    let transform:  [Float]         // float4x4 columna-mayor (16 floats)

    // Posición como SIMD3
    var simdPosition: SIMD3<Float> {
        SIMD3<Float>(position[0], position[1], position[2])
    }

    // Transform como float4x4
    var simdTransform: float4x4 {
        float4x4(columns: (
            SIMD4<Float>(transform[0],  transform[1],  transform[2],  transform[3]),
            SIMD4<Float>(transform[4],  transform[5],  transform[6],  transform[7]),
            SIMD4<Float>(transform[8],  transform[9],  transform[10], transform[11]),
            SIMD4<Float>(transform[12], transform[13], transform[14], transform[15])
        ))
    }
}

// MARK: - PanoramaCaptureManager

class PanoramaCaptureManager {

    static let shared = PanoramaCaptureManager()

    // Nodos capturados durante la sesión actual
    private(set) var nodes: [PanoramaNode] = []

    // Distancia mínima entre nodos (metros) — evita nodos redundantes
    var minNodeDistance: Float = 0.5

    // Intervalo mínimo entre capturas (segundos)
    var minCaptureInterval: Double = 1.0

    private var lastCaptureTime: Double = 0
    private var nodeCounter: Int = 0

    private let docsDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // MARK: - Capturar nodo desde ARFrame

    /// Llama a este método en session(_:didUpdate:) para registrar posiciones.
    /// Solo crea nodo si han pasado minCaptureInterval segundos Y
    /// la cámara se movió más de minNodeDistance metros.
    @discardableResult
    func captureNode(from frame: ARFrame) -> PanoramaNode? {
        let now = Date().timeIntervalSince1970
        guard now - lastCaptureTime >= minCaptureInterval else { return nil }

        let transform = frame.camera.transform
        let position  = SIMD3<Float>(transform.columns.3.x,
                                     transform.columns.3.y,
                                     transform.columns.3.z)

        // Distancia al nodo anterior
        if let last = nodes.last {
            let dist = simd_distance(position, last.simdPosition)
            guard dist >= minNodeDistance else { return nil }
        }

        // Quaternion desde la matriz de rotación
        let q = simd_quatf(transform)

        let node = PanoramaNode(
            id:        nodeCounter,
            timestamp: now,
            position:  [position.x, position.y, position.z],
            rotation:  [q.vector.x, q.vector.y, q.vector.z, q.vector.w],
            transform: [
                transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w,
                transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w,
                transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w,
                transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w,
            ]
        )

        nodes.append(node)
        nodeCounter      += 1
        lastCaptureTime   = now
        return node
    }

    // MARK: - Trayectoria

    /// Devuelve la trayectoria como array de posiciones en orden cronológico.
    func getTrajectory() -> [SIMD3<Float>] {
        nodes.map { $0.simdPosition }
    }

    /// Distancia total recorrida (metros).
    var totalPathLength: Float {
        guard nodes.count > 1 else { return 0 }
        var total: Float = 0
        for i in 1..<nodes.count {
            total += simd_distance(nodes[i].simdPosition, nodes[i-1].simdPosition)
        }
        return total
    }

    /// Bounding box de la trayectoria — útil para centrar la vista.
    var trajectoryBounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard !nodes.isEmpty else { return nil }
        var minP = nodes[0].simdPosition
        var maxP = nodes[0].simdPosition
        for n in nodes {
            minP = simd_min(minP, n.simdPosition)
            maxP = simd_max(maxP, n.simdPosition)
        }
        return (minP, maxP)
    }

    // MARK: - Persistencia

    /// Guarda los nodos en disco.
    @discardableResult
    func save(named name: String) -> URL? {
        let url = docsDir.appendingPathComponent("\(name).panorama")
        do {
            let data = try JSONEncoder().encode(nodes)
            try data.write(to: url, options: .atomic)
            print("[PanoramaCapture] \(nodes.count) nodos guardados → \(url.lastPathComponent)")
            return url
        } catch {
            print("[PanoramaCapture] error guardando: \(error)")
            return nil
        }
    }

    /// Carga nodos desde disco.
    @discardableResult
    func load(named name: String) -> [PanoramaNode]? {
        let url = docsDir.appendingPathComponent("\(name).panorama")
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([PanoramaNode].self, from: data)
            nodes        = loaded
            nodeCounter  = (loaded.last?.id ?? -1) + 1
            print("[PanoramaCapture] \(loaded.count) nodos cargados")
            return loaded
        } catch {
            print("[PanoramaCapture] error cargando: \(error)")
            return nil
        }
    }

    // MARK: - Reset

    func reset() {
        nodes           = []
        nodeCounter     = 0
        lastCaptureTime = 0
    }

    // MARK: - Serialización para Capacitor bridge

    func toDictionary() -> [String: Any] {
        [
            "nodeCount":       nodes.count,
            "totalPathLength": Double(totalPathLength),
            "nodes": nodes.map { n in
                [
                    "id":        n.id,
                    "timestamp": n.timestamp,
                    "x":         Double(n.position[0]),
                    "y":         Double(n.position[1]),
                    "z":         Double(n.position[2]),
                ] as [String: Any]
            }
        ]
    }
}
