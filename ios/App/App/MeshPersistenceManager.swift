// MeshPersistenceManager.swift
// Serializa y guarda en disco los ARMeshAnchor capturados durante el escaneo.
// Permite reconstruir la malla sin repetir el escaneo.
//
// Formato de archivo: .miremesh (binario)
//   Header  : "MIREMESH" (8 bytes) + versión UInt32
//   N anchors: por cada anchor:
//     - UUID (16 bytes)
//     - transform (float4x4, 64 bytes)
//     - vertexCount UInt32 + datos de vértices (SIMD3<Float>)
//     - faceCount UInt32 + datos de índices (UInt32 × 3 por cara)
//     - classificationCount UInt32 + clasificaciones (UInt8 por cara)

import ARKit
import simd

// MARK: - Struct serializable de un anchor

struct PersistedMeshAnchor: Codable {
    let id:              String           // UUID
    let transform:       [Float]          // 16 floats (column-major float4x4)
    let vertices:        [Float]          // tripletes XYZ (espacio local del anchor)
    let normals:         [Float]          // tripletes XYZ normales (mismo orden que vértices)
    let faceIndices:     [UInt32]         // tripletes por triángulo
    let classifications: [UInt8]          // 1 por cara

    /// Reconstruye la simd_float4x4 del transform guardado.
    var transformMatrix: simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(transform[0],  transform[1],  transform[2],  transform[3]),
            SIMD4<Float>(transform[4],  transform[5],  transform[6],  transform[7]),
            SIMD4<Float>(transform[8],  transform[9],  transform[10], transform[11]),
            SIMD4<Float>(transform[12], transform[13], transform[14], transform[15])
        ))
    }
}

// MARK: - MeshPersistenceManager

class MeshPersistenceManager {

    static let shared = MeshPersistenceManager()

    private let docsDir: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }()

    // MARK: - Guardar

    /// Serializa todos los ARMeshAnchor actuales y los guarda en disco.
    /// - Parameter name: nombre del archivo sin extensión
    /// - Returns: URL del archivo guardado o nil si falla
    @discardableResult
    func save(anchors: [ARMeshAnchor], named name: String) -> URL? {
        let persisted = anchors.map { encode($0) }
        let url = docsDir.appendingPathComponent("\(name).miremesh")
        do {
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: url, options: .atomic)
            print("[MeshPersistence] guardado \(persisted.count) anchors → \(url.lastPathComponent)")
            return url
        } catch {
            print("[MeshPersistence] error guardando: \(error)")
            return nil
        }
    }

    /// Guarda el estado actual de MeshManager con timestamp automático.
    @discardableResult
    func saveCurrentMesh() -> URL? {
        let name = "mesh_\(Int(Date().timeIntervalSince1970))"
        return save(anchors: MeshManager.shared.meshAnchors, named: name)
    }

    // MARK: - Cargar

    /// Carga un archivo .miremesh y devuelve los datos serializados.
    func load(named name: String) -> [PersistedMeshAnchor]? {
        let url = docsDir.appendingPathComponent("\(name).miremesh")
        return load(from: url)
    }

    func load(from url: URL) -> [PersistedMeshAnchor]? {
        do {
            let data = try Data(contentsOf: url)
            let anchors = try JSONDecoder().decode([PersistedMeshAnchor].self, from: data)
            print("[MeshPersistence] cargados \(anchors.count) anchors desde \(url.lastPathComponent)")
            return anchors
        } catch {
            print("[MeshPersistence] error cargando: \(error)")
            return nil
        }
    }

    // MARK: - Listar archivos guardados

    func listSavedMeshes() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: docsDir, includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return urls
            .filter { $0.pathExtension == "miremesh" }
            .sorted { url1, url2 in
                let d1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }
    }

    // MARK: - Eliminar

    func delete(named name: String) {
        let url = docsDir.appendingPathComponent("\(name).miremesh")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Codificación privada

    private func encode(_ anchor: ARMeshAnchor) -> PersistedMeshAnchor {
        let geo = anchor.geometry

        // transform — float4x4 → array de 16 floats (column-major)
        let t = anchor.transform
        let transformArr: [Float] = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w,
        ]

        // vértices
        var verts = [Float]()
        verts.reserveCapacity(geo.vertices.count * 3)
        let vPtr = geo.vertices.buffer.contents()
            .advanced(by: geo.vertices.offset)
            .assumingMemoryBound(to: Float.self)
        let vStride = geo.vertices.stride / MemoryLayout<Float>.stride
        for i in 0..<geo.vertices.count {
            verts.append(vPtr[i * vStride])
            verts.append(vPtr[i * vStride + 1])
            verts.append(vPtr[i * vStride + 2])
        }

        // índices de caras
        var indices = [UInt32]()
        indices.reserveCapacity(geo.faces.count * 3)
        let iPtr = geo.faces.buffer.contents()
            .assumingMemoryBound(to: UInt32.self)
        let iStride = geo.faces.indexCountPerPrimitive
        for f in 0..<geo.faces.count {
            for k in 0..<iStride {
                indices.append(iPtr[f * iStride + k])
            }
        }

        // normales
        var norms = [Float]()
        norms.reserveCapacity(geo.normals.count * 3)
        let nPtr = geo.normals.buffer.contents()
            .advanced(by: geo.normals.offset)
            .assumingMemoryBound(to: Float.self)
        let nStride = geo.normals.stride / MemoryLayout<Float>.stride
        for i in 0..<geo.normals.count {
            norms.append(nPtr[i * nStride])
            norms.append(nPtr[i * nStride + 1])
            norms.append(nPtr[i * nStride + 2])
        }

        // clasificaciones (1 UInt8 por cara)
        var classes = [UInt8]()
        if let cls = geo.classification {
            classes.reserveCapacity(geo.faces.count)
            let cPtr = cls.buffer.contents()
                .advanced(by: cls.offset)
                .assumingMemoryBound(to: UInt8.self)
            let cStride = cls.stride
            for f in 0..<geo.faces.count {
                classes.append(cPtr[f * cStride])
            }
        }

        return PersistedMeshAnchor(
            id:              anchor.identifier.uuidString,
            transform:       transformArr,
            vertices:        verts,
            normals:         norms,
            faceIndices:     indices,
            classifications: classes
        )
    }
}
