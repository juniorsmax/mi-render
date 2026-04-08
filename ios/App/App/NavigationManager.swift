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
    }
}
