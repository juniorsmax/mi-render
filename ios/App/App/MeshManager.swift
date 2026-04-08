// MeshManager.swift
// Extrae y gestiona la geometría 3D capturada por LiDAR.
// Convierte ARMeshAnchor → MDLMesh para exportación.
// Gestiona limpieza de anchors para evitar crashes en sesiones largas.

import ARKit
import ModelIO
import MetalKit

class MeshManager {

    static let shared = MeshManager()

    private var meshAnchors: [ARMeshAnchor] = []

    // MARK: - Extracción de mesh desde anchor

    func extractMesh(from anchor: ARMeshAnchor) -> MDLMesh {

        let geometry = anchor.geometry

        let vertexBuffer = geometry.vertices.buffer
        let vertexCount  = geometry.vertices.count

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: geometry.vertices.stride)

        let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!)

        let mdlVertexBuffer = allocator.newBuffer(
            with: Data(bytes: vertexBuffer.contents(),
                       count: vertexBuffer.length),
            type: .vertex
        )

        let mesh = MDLMesh(
            vertexBuffer: mdlVertexBuffer,
            vertexCount: vertexCount,
            descriptor: vertexDescriptor,
            submeshes: nil
        )

        return mesh
    }

    // MARK: - Acumular anchors durante el escaneo

    func addAnchor(_ anchor: ARMeshAnchor) {
        meshAnchors.append(anchor)
    }

    // MARK: - Obtener todos los meshes acumulados

    func getAllMeshes() -> [MDLMesh] {
        return meshAnchors.map { extractMesh(from: $0) }
    }

    // MARK: - Limpiar anchors antiguos (evita crash de memoria en sesiones largas)

    func removeOldAnchors(session: ARSession, keepLast count: Int = 50) {
        guard meshAnchors.count > count else { return }
        let toRemove = Array(meshAnchors.prefix(meshAnchors.count - count))
        toRemove.forEach { session.remove(anchor: $0) }
        meshAnchors = Array(meshAnchors.suffix(count))
    }

    // MARK: - Limpiar todo

    func clearAll(session: ARSession) {
        meshAnchors.forEach { session.remove(anchor: $0) }
        meshAnchors.removeAll()
    }

    // MARK: - Combinar todos los meshes en uno solo (para exportación)

    func combinedMesh() -> MDLAsset {
        let asset = MDLAsset()
        getAllMeshes().forEach { asset.add($0) }
        return asset
    }

    // MARK: - Extraer clasificación de una cara del mesh

    func classification(of faceIndex: Int, in anchor: ARMeshAnchor) -> ARMeshClassification {
        return anchor.geometry.classificationOf(faceWithIndex: faceIndex)
    }

    // MARK: - Filtrar mesh por clasificación (ej: solo paredes)

    func anchorsMatching(classification: ARMeshClassification) -> [ARMeshAnchor] {
        return meshAnchors.filter { anchor in
            for i in 0..<anchor.geometry.faces.count {
                if anchor.geometry.classificationOf(faceWithIndex: i) == classification {
                    return true
                }
            }
            return false
        }
    }
}
