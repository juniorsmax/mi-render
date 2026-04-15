// MeshManager.swift
// Extrae, gestiona y mide la geometría 3D capturada por LiDAR.
// Convierte ARMeshAnchor → MDLMesh para exportación.
// Calcula superficies por clasificación ARMeshClassification.
// Genera proyección 2D de suelo para floorplan automático.

import ARKit
import ModelIO
import MetalKit
import simd

// ── Resultado de cálculo de superficies ──────────────────────────────────────

struct MeshSurfaces {
    var floor:   Float = 0   // m²
    var wall:    Float = 0   // m²
    var ceiling: Float = 0   // m²
    var table:   Float = 0   // m²
    var seat:    Float = 0   // m²
    var window:  Float = 0   // m²
    var door:    Float = 0   // m²
    var other:   Float = 0   // m² — .none + sin clasificar

    var total: Float { floor + wall + ceiling + table + seat + window + door + other }

    /// Devuelve un diccionario listo para resolver en un CAPPluginCall
    func toDictionary() -> [String: Any] {
        [
            "floorArea":    Double(floor),
            "wallArea":     Double(wall),
            "ceilingArea":  Double(ceiling),
            "tableArea":    Double(table),
            "seatArea":     Double(seat),
            "windowArea":   Double(window),
            "doorArea":     Double(door),
            "otherArea":    Double(other),
            "totalArea":    Double(total),
        ]
    }
}

// ── MeshManager ───────────────────────────────────────────────────────────────

class MeshManager {

    static let shared = MeshManager()

    // internal para que MeasurementManager pueda leer el snapshot
    var meshAnchors: [ARMeshAnchor] = []

    // Cache de superficies recalculada cada vez que cambian los anchors
    private(set) var surfaces = MeshSurfaces()

    // Vértices del suelo proyectados al plano XZ — para floorplan 2D
    private(set) var floorVertices2D: [SIMD2<Float>] = []

    // Callback invocado en el hilo principal cuando las superficies cambian
    var onSurfacesUpdated: ((MeshSurfaces) -> Void)?

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

        return MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: geometry.vertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )
    }

    // MARK: - Acumular anchors durante el escaneo

    func addAnchor(_ anchor: ARMeshAnchor) {
        // Reemplaza si ya existe (actualización de anchor)
        if let idx = meshAnchors.firstIndex(where: { $0.identifier == anchor.identifier }) {
            meshAnchors[idx] = anchor
        } else {
            meshAnchors.append(anchor)
        }
        recalculateSurfaces()
    }

    /// Alias para ScanManager delegate — upsert de un anchor.
    func update(anchor: ARMeshAnchor) { addAnchor(anchor) }

    /// Elimina un anchor por identificador.
    func remove(anchor: ARMeshAnchor) {
        meshAnchors.removeAll { $0.identifier == anchor.identifier }
        recalculateSurfaces()
    }

    // MARK: - Reemplazar todos los anchors (para ObjectScanViewController)

    func setMeshAnchors(_ anchors: [ARMeshAnchor]) {
        meshAnchors = anchors
        recalculateSurfaces()
    }

    // MARK: - Obtener todos los meshes acumulados

    func getAllMeshes() -> [MDLMesh] {
        return meshAnchors.map { extractMesh(from: $0) }
    }

    // MARK: - Obtener mesh filtrado por clasificación (para exportación selectiva)

    func getMeshAsset(for classification: ARMeshClassification) -> MDLAsset {
        let asset = MDLAsset()
        for anchor in meshAnchors {
            if let mesh = extractMesh(from: anchor, filterBy: classification) {
                asset.add(mesh)
            }
        }
        return asset
    }

    // Extrae solo los triángulos de un anchor que coincidan con una clasificación
    private func extractMesh(from anchor: ARMeshAnchor,
                             filterBy cls: ARMeshClassification) -> MDLMesh? {
        let geometry = anchor.geometry
        let fBuf = geometry.faces
        let vBuf = geometry.vertices
        let faceCount = fBuf.count

        let iPtr = fBuf.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)

        // Recopila índices de caras que coinciden con la clasificación
        var matchingFaces: [UInt32] = []
        for f in 0..<faceCount {
            if geometry.faceClassification(at: f) == cls {
                let base = f * 3
                matchingFaces.append(contentsOf: [iPtr[base], iPtr[base+1], iPtr[base+2]])
            }
        }
        guard !matchingFaces.isEmpty else { return nil }

        let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!)

        let vertexBuffer = allocator.newBuffer(
            with: Data(bytes: vBuf.buffer.contents(), count: vBuf.buffer.length),
            type: .vertex
        )
        let indexData = matchingFaces.withUnsafeBytes { Data($0) }
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: vBuf.stride)

        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: matchingFaces.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        return MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vBuf.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )
    }

    // MARK: - Limpiar anchors antiguos

    func removeOldAnchors(session: ARSession, keepLast count: Int = 50) {
        guard meshAnchors.count > count else { return }
        let toRemove = Array(meshAnchors.prefix(meshAnchors.count - count))
        toRemove.forEach { session.remove(anchor: $0) }
        meshAnchors = Array(meshAnchors.suffix(count))
        recalculateSurfaces()
    }

    // MARK: - Limpiar todo

    func clearAll(session: ARSession) {
        meshAnchors.forEach { session.remove(anchor: $0) }
        meshAnchors.removeAll()
        surfaces = MeshSurfaces()
        floorVertices2D = []
        DispatchQueue.main.async { self.onSurfacesUpdated?(self.surfaces) }
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

    // MARK: - Filtrar mesh por clasificación

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

    // MARK: - Vértices del suelo proyectados al plano XZ para floorplan 2D
    //
    // Retorna todos los vértices de caras clasificadas como .floor
    // proyectados al plano XZ (Y=0). Útil para calcular contorno/outline
    // del suelo y generar un plano 2D automático.

    func getFloorVertices2D() -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        for anchor in meshAnchors {
            let geometry  = anchor.geometry
            let transform = anchor.transform
            let vBuf      = geometry.vertices
            let fBuf      = geometry.faces

            let vPtr = vBuf.buffer.contents()
                .advanced(by: vBuf.offset)
                .assumingMemoryBound(to: Float.self)
            let iPtr = fBuf.buffer.contents()
                .assumingMemoryBound(to: UInt32.self)

            let vStride = vBuf.stride / MemoryLayout<Float>.stride

            for f in 0..<fBuf.count {
                guard geometry.faceClassification(at: f) == .floor else { continue }
                let base = f * 3
                for k in 0..<3 {
                    let idx = Int(iPtr[base + k])
                    let lp = SIMD3<Float>(vPtr[idx*vStride],
                                         vPtr[idx*vStride + 1],
                                         vPtr[idx*vStride + 2])
                    let wp = (transform * SIMD4<Float>(lp, 1)).xyz
                    points.append(SIMD2<Float>(wp.x, wp.z))
                }
            }
        }
        return points
    }

    // MARK: - Bounding box del suelo (para escala del floorplan)

    func floorBoundingBox() -> (min: SIMD2<Float>, max: SIMD2<Float>)? {
        let pts = getFloorVertices2D()
        guard !pts.isEmpty else { return nil }
        var minPt = pts[0]
        var maxPt = pts[0]
        for p in pts {
            minPt = simd_min(minPt, p)
            maxPt = simd_max(maxPt, p)
        }
        return (minPt, maxPt)
    }

    // MARK: - ── Cálculo de superficies ──────────────────────────────────────
    //
    // Itera cada triángulo de cada ARMeshAnchor, extrae los tres vértices
    // en coordenadas mundo, calcula el área con producto vectorial y acumula
    // por clasificación ARMeshClassification (todos los 7 tipos explícitos).

    func recalculateSurfaces() {
        let anchorsSnapshot = meshAnchors   // copia local, hilo-segura para lectura
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var result = MeshSurfaces()

            for anchor in anchorsSnapshot {
                self.accumulateSurfaces(from: anchor, into: &result)
            }

            // Redondear a 4 decimales para evitar ruido flotante
            result.floor   = (result.floor   * 10000).rounded() / 10000
            result.wall    = (result.wall    * 10000).rounded() / 10000
            result.ceiling = (result.ceiling * 10000).rounded() / 10000
            result.table   = (result.table   * 10000).rounded() / 10000
            result.seat    = (result.seat    * 10000).rounded() / 10000
            result.window  = (result.window  * 10000).rounded() / 10000
            result.door    = (result.door    * 10000).rounded() / 10000
            result.other   = (result.other   * 10000).rounded() / 10000

            DispatchQueue.main.async {
                self.surfaces = result
                self.onSurfacesUpdated?(result)
            }
        }
    }

    // ── Acumula el área de un anchor sumándola al resultado por clasificación

    private func accumulateSurfaces(from anchor: ARMeshAnchor,
                                    into result: inout MeshSurfaces) {

        let geometry  = anchor.geometry
        let transform = anchor.transform          // simd_float4x4 — world space

        let vBuf     = geometry.vertices
        let fBuf     = geometry.faces
        let faceCount = fBuf.count

        // Puntero al buffer de vértices (float3)
        let vPtr = vBuf.buffer.contents()
            .advanced(by: vBuf.offset)
            .assumingMemoryBound(to: Float.self)

        // Puntero al buffer de índices (UInt32)
        let iPtr = fBuf.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)

        let vStride = vBuf.stride / MemoryLayout<Float>.stride   // pasos en floats
        let iStride = 3   // triángulo = 3 índices

        for f in 0..<faceCount {

            // Índices de los tres vértices del triángulo
            let base = f * iStride
            let i0 = Int(iPtr[base + 0])
            let i1 = Int(iPtr[base + 1])
            let i2 = Int(iPtr[base + 2])

            // Posiciones en espacio local del anchor (float3)
            let lp0 = SIMD3<Float>(vPtr[i0 * vStride],
                                   vPtr[i0 * vStride + 1],
                                   vPtr[i0 * vStride + 2])
            let lp1 = SIMD3<Float>(vPtr[i1 * vStride],
                                   vPtr[i1 * vStride + 1],
                                   vPtr[i1 * vStride + 2])
            let lp2 = SIMD3<Float>(vPtr[i2 * vStride],
                                   vPtr[i2 * vStride + 1],
                                   vPtr[i2 * vStride + 2])

            // Transformar a coordenadas mundo
            let wp0 = (transform * SIMD4<Float>(lp0, 1)).xyz
            let wp1 = (transform * SIMD4<Float>(lp1, 1)).xyz
            let wp2 = (transform * SIMD4<Float>(lp2, 1)).xyz

            // Área del triángulo = 0.5 * |AB × AC|
            let ab   = wp1 - wp0
            let ac   = wp2 - wp0
            let area = 0.5 * simd_length(simd_cross(ab, ac))   // m²

            // Clasificación completa de la cara
            let cls = geometry.faceClassification(at: f)

            switch cls {
            case .floor:   result.floor   += area
            case .wall:    result.wall    += area
            case .ceiling: result.ceiling += area
            case .table:   result.table   += area
            case .seat:    result.seat    += area
            case .window:  result.window  += area
            case .door:    result.door    += area
            default:       result.other   += area   // .none y futuros casos
            }
        }
    }

    // MARK: - Anchors filtrados por clasificación (alias por claro)

    func anchorsMatching(_ cls: ARMeshClassification) -> [ARMeshAnchor] {
        return anchorsMatching(classification: cls)
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

// MARK: - simd_float4 → xyz helper

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
