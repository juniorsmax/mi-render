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

        let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!)

        let vertexBuffer = allocator.newBuffer(
            with: Data(bytes: geometry.vertices.buffer.contents(),
                       count: geometry.vertices.buffer.length),
            type: .vertex
        )

        let indexBuffer = allocator.newBuffer(
            with: Data(bytes: geometry.faces.buffer.contents(),
                       count: geometry.faces.buffer.length),
            type: .index
        )

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(
            stride: geometry.vertices.stride
        )

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: geometry.faces.count * 3,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: geometry.vertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mesh
    }

    // MARK: - Acumular anchors durante el escaneo

    func addAnchor(_ anchor: ARMeshAnchor) {
        meshAnchors.append(anchor)
    }

    // MARK: - Reemplazar todos los anchors (para ObjectScanViewController)

    func setMeshAnchors(_ anchors: [ARMeshAnchor]) {
        meshAnchors = anchors
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
        return anchor.geometry.faceClassification(at: faceIndex)
    }

    // MARK: - Filtrar mesh por clasificación (ej: solo paredes)

    func anchorsMatching(classification: ARMeshClassification) -> [ARMeshAnchor] {
        return meshAnchors.filter { anchor in
            for i in 0..<anchor.geometry.faces.count {
                if anchor.geometry.faceClassification(at: i) == classification {
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - ARMeshGeometry helper

extension ARMeshGeometry {
    func faceClassification(at index: Int) -> ARMeshClassification {
        guard let src = classification else { return .none }
        let byteOffset = index * src.stride + src.offset
        let rawValue = src.buffer.contents()
            .advanced(by: byteOffset)
            .load(as: UInt8.self)
        return ARMeshClassification(rawValue: Int(rawValue)) ?? .none
    }
}
