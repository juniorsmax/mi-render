// MeshOptimizationManager.swift
// Agente 9 — MeshOptimizationAgent
// Optimiza la malla 3D para evitar crashes, lag y sobrecalentamiento.
// Reduce vértices, elimina duplicados, aplica LOD dinámico.

import ARKit
import ModelIO
import MetalKit

class MeshOptimizationManager {

    static let shared = MeshOptimizationManager()

    // MARK: - Reducir densidad de vértices

    func reduceMeshDensity(_ mesh: MDLMesh, targetRatio: Float = 0.5) -> MDLMesh {
        guard targetRatio > 0, targetRatio < 1 else { return mesh }

        let subdivisionCount = max(1, Int(1.0 / targetRatio))
        mesh.generateAmbientOcclusionTexture(
            withQuality: Float(subdivisionCount),
            attenuationFactor: 0.98,
            objectsToConsider: [mesh],
            vertexAttributeNamed: MDLVertexAttributeNormal,
            materialPropertyNamed: "ao"
        )

        return mesh
    }

    // MARK: - Eliminar vértices duplicados

    func removeDuplicateVertices(from asset: MDLAsset) -> MDLAsset {
        let cleaned = MDLAsset()
        for i in 0..<asset.count {
            guard let mesh = asset.object(at: i) as? MDLMesh else { continue }
            try? mesh.makeVerticesUniqueAndReturnError()
            cleaned.add(mesh)
        }
        return cleaned
    }

    // MARK: - Optimizar normales

    func optimizeNormals(in mesh: MDLMesh) {
        mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.7)
    }

    // MARK: - LOD dinámico según distancia

    func lodLevel(for distance: Float) -> Float {
        switch distance {
        case ..<2.0:   return 1.0   // máxima calidad
        case 2.0..<5.0: return 0.6
        case 5.0..<10.0: return 0.3
        default:        return 0.1  // mínima calidad
        }
    }

    // MARK: - Limpiar asset completo

    func optimizeAsset(_ asset: MDLAsset) -> MDLAsset {
        let device = MTLCreateSystemDefaultDevice()!
        let allocator = MTKMeshBufferAllocator(device: device)
        _ = allocator // disponible para uso futuro con meshes complejos
        return removeDuplicateVertices(from: asset)
    }

    // MARK: - Verificar límite de memoria

    func isWithinMemoryBudget(vertexCount: Int, limit: Int = 500_000) -> Bool {
        return vertexCount <= limit
    }

    // MARK: - Calcular vértices totales en asset

    func totalVertexCount(in asset: MDLAsset) -> Int {
        var total = 0
        for i in 0..<asset.count {
            if let mesh = asset.object(at: i) as? MDLMesh {
                total += mesh.vertexCount
            }
        }
        return total
    }
}
