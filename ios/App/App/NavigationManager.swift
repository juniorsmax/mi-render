// NavigationManager.swift
// Navegación indoor sin GPS usando GameplayKit + mesh reconstruido.
// Genera grafos de rutas interiores desde puntos del suelo.

import ARKit
import GameplayKit

class NavigationManager {

    static let shared = NavigationManager()

    private var graph: GKGraph?
    private var floorPoints: [GKGraphNode3D] = []

    // MARK: - Construir grafo de navegación desde puntos

    func createPathGraph(points: [vector_float3]) -> GKGraph {
        let nodes = points.map { GKGraphNode3D(point: $0) }

        for i in 0..<nodes.count {
            var connections: [GKGraphNode3D] = []
            for j in 0..<nodes.count where i != j {
                let dx = nodes[i].position.x - nodes[j].position.x
                let dz = nodes[i].position.z - nodes[j].position.z
                let dist = sqrt(dx*dx + dz*dz)
                if dist < 0.5 {
                    connections.append(nodes[j])
                }
            }
            nodes[i].addConnections(to: connections, bidirectional: true)
        }

        let newGraph = GKGraph(nodes)
        self.graph = newGraph
        return newGraph
    }

    // MARK: - Encontrar ruta entre dos puntos

    func findPath(from start: vector_float3,
                  to end: vector_float3) -> [vector_float3] {

        guard let graph = graph else { return [] }

        let startNode = GKGraphNode3D(point: start)
        let endNode   = GKGraphNode3D(point: end)

        graph.add([startNode, endNode])

        if let nodes = graph.nodes as? [GKGraphNode3D] {
            for node in nodes where node !== startNode && node !== endNode {
                let dx = startNode.position.x - node.position.x
                let dz = startNode.position.z - node.position.z
                if sqrt(dx*dx + dz*dz) < 1.0 {
                    startNode.addConnections(to: [node], bidirectional: true)
                }
                let dx2 = endNode.position.x - node.position.x
                let dz2 = endNode.position.z - node.position.z
                if sqrt(dx2*dx2 + dz2*dz2) < 1.0 {
                    endNode.addConnections(to: [node], bidirectional: true)
                }
            }
        }

        let pathNodes = graph.findPath(from: startNode, to: endNode)
        graph.remove([startNode, endNode])

        return pathNodes.compactMap { ($0 as? GKGraphNode3D)?.position }
    }

    // MARK: - Extraer puntos del suelo desde mesh clasificado

    func extractFloorPoints(from anchors: [ARMeshAnchor]) -> [vector_float3] {
        var points: [vector_float3] = []

        for anchor in anchors {
            let geometry = anchor.geometry

            for i in 0..<geometry.faces.count {
                guard geometry.faceClassification(at: i) == .floor else { continue }

                let indices = geometry.faces
                let stride  = geometry.faces.indexCountPerPrimitive

                for k in 0..<stride {
                    let vertexIndex = indices.buffer.contents()
                        .advanced(by: (i * stride + k) * MemoryLayout<UInt32>.size)
                        .load(as: UInt32.self)

                    let vertexPtr = geometry.vertices.buffer.contents()
                        .advanced(by: Int(vertexIndex) * geometry.vertices.stride)
                    let localVertex = vertexPtr.load(as: SIMD3<Float>.self)

                    let worldPos = anchor.transform * SIMD4<Float>(localVertex, 1)
                    points.append(vector_float3(worldPos.x, worldPos.y, worldPos.z))
                }
            }
        }

        return points
    }

    // MARK: - Limpiar grafo

    func clearGraph() {
        graph = nil
        floorPoints.removeAll()
        cameraNodes.removeAll()
    }
}

// MARK: - Registro de posiciones de cámara por frame

extension NavigationManager {

    // Nodos registrados durante el escaneo (posición + orientación)
    struct CameraNode {
        let index:    Int
        let position: SIMD3<Float>
        let forward:  SIMD3<Float>   // dirección -Z del transform
        let transform: simd_float4x4
    }

    private static var _cameraNodes: [CameraNode] = []
    var cameraNodes: [CameraNode] {
        get { NavigationManager._cameraNodes }
        set { NavigationManager._cameraNodes = newValue }
    }

    /// Llama este método en ARSessionDelegate.session(_:didUpdate:frame:).
    /// Registra la posición solo si la cámara se movió minDistance metros.
    @discardableResult
    func registerFrame(_ frame: ARFrame, minDistance: Float = 0.4) -> CameraNode? {
        let t = frame.camera.transform
        let pos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        // Dirección -Z (hacia donde apunta la cámara)
        let forward = -SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)

        // Solo añadir si hay movimiento suficiente
        if let last = cameraNodes.last {
            guard simd_distance(pos, last.position) >= minDistance else { return nil }
        }

        let node = CameraNode(
            index:     cameraNodes.count,
            position:  pos,
            forward:   forward,
            transform: t
        )
        cameraNodes.append(node)
        return node
    }

    /// Devuelve la trayectoria como array de posiciones ordenadas.
    func trajectory() -> [SIMD3<Float>] {
        cameraNodes.map { $0.position }
    }

    /// Distancia total recorrida en metros.
    var trajectoryLength: Float {
        guard cameraNodes.count > 1 else { return 0 }
        var total: Float = 0
        for i in 1..<cameraNodes.count {
            total += simd_distance(cameraNodes[i].position, cameraNodes[i-1].position)
        }
        return total
    }

    /// Nodo más cercano a una posición dada (para navegación entre nodos).
    func nearestNode(to position: SIMD3<Float>) -> CameraNode? {
        cameraNodes.min(by: {
            simd_distance($0.position, position) < simd_distance($1.position, position)
        })
    }

    /// Serialización para Capacitor bridge.
    func trajectoryDictionary() -> [String: Any] {
        [
            "nodeCount":      cameraNodes.count,
            "totalLength":    Double(trajectoryLength),
            "nodes": cameraNodes.map { n in
                ["index": n.index,
                 "x": Double(n.position.x),
                 "y": Double(n.position.y),
                 "z": Double(n.position.z)] as [String: Any]
            }
        ]
    }
}

// MARK: - Cálculo de progreso de escaneo guiado ───────────────────────────────

extension NavigationManager {

    struct ScanProgress {
        var percentage:      Float        // 0.0 – 1.0
        var guidanceMessage: String
        var missingDirections: [String]   // p.ej. ["Norte", "Este"]
        var wallsCovered:    Int
        var totalFaces:      Int
    }

    /// Calcula progreso combinando cobertura de mesh, paredes y footprint.
    /// Hilo-seguro — puede llamarse desde background.
    func calculateScanProgress() -> ScanProgress {
        let anchors   = MeshManager.shared.meshAnchors
        let surfaces  = MeshManager.shared.surfaces
        let walls     = MeasurementManager.shared.wallPlanes
        let floorPts  = MeshManager.shared.getFloorVertices2D()

        // Componente 1: densidad de faces (ref: 20 000 faces = habitación completa)
        let totalFaces    = anchors.reduce(0) { $0 + $1.geometry.faces.count }
        let faceProgress  = min(1.0, Float(totalFaces) / 20_000.0)

        // Componente 2: paredes detectadas (ref: 4 paredes para habitación cuadrada)
        let wallProgress  = min(1.0, Float(walls.count) / 4.0)

        // Componente 3: área del footprint (ref: 12 m² típico)
        let footprintArea = min(1.0, surfaces.floor / 12.0)

        // Ponderado: faces 40%, paredes 30%, suelo 30%
        let combined = faceProgress * 0.4 + wallProgress * 0.3 + footprintArea * 0.3

        // Zonas faltantes
        let missing = detectMissingZones(from: floorPts)

        // Mensaje de guía
        let message = guidanceMessage(progress: combined,
                                      missingZones: missing,
                                      walls: walls,
                                      totalFaces: totalFaces)

        return ScanProgress(
            percentage:       combined,
            guidanceMessage:  message,
            missingDirections: missing,
            wallsCovered:     walls.count,
            totalFaces:       totalFaces
        )
    }

    // ── Detección de zonas no cubiertas ──────────────────────────────────────
    //
    // Divide el espacio XZ en 8 sectores (45° cada uno) alrededor del centroide.
    // Sectores con menos del 6% de los puntos totales se marcan como faltantes.

    private func detectMissingZones(from pts: [SIMD2<Float>]) -> [String] {
        guard pts.count > 30 else {
            return pts.isEmpty ? ["Mueve la cámara por la habitación"] : []
        }

        let cx = pts.reduce(0) { $0 + $1.x } / Float(pts.count)
        let cy = pts.reduce(0) { $0 + $1.y } / Float(pts.count)

        var sectors = [Int](repeating: 0, count: 8)
        for pt in pts {
            let angle  = atan2(pt.y - cy, pt.x - cx)                // -π … π
            let sector = Int((angle + .pi) / (.pi / 4)) % 8
            sectors[sector] += 1
        }

        let threshold = pts.count / 16   // mínimo ~6% por sector
        // Nombres en orden: sector 0 = aprox. Este, girando antihorario
        let names = ["Este", "NorEste", "Norte", "NorOeste",
                     "Oeste", "SurOeste", "Sur", "SurEste"]

        return sectors.enumerated()
            .filter { $0.element < threshold }
            .map    { "Mueve hacia el \(names[$0.offset])" }
    }

    // ── Mensaje de guía según estado del escaneo ─────────────────────────────

    private func guidanceMessage(progress: Float,
                                  missingZones: [String],
                                  walls: [WallPlane],
                                  totalFaces: Int) -> String {
        switch progress {
        case 0..<0.10:
            return "Apunta al suelo y muévete lentamente"
        case 0.10..<0.30:
            return "Continúa escaneando. Cubre suelo y paredes"
        case 0.30..<0.60:
            if let first = missingZones.first { return first }
            if walls.count < 3 { return "Enfoca las paredes para detectarlas" }
            return "Escanea los rincones de la habitación"
        case 0.60..<0.85:
            if let first = missingZones.first { return first }
            return "Casi listo. Revisa zonas que falten"
        default:
            return "Cobertura completa — pulsa Hecho cuando estés listo"
        }
    }
}
