// ScanProject.swift
// Modelo de persistencia para proyectos de escaneo.
// Cada proyecto se guarda en Documents/projects/<uuid>/
//   metadata.json      — ScanProject codificado
//   worldmap.arworldmap
//   mesh.miremesh
//   model.usdz
//   thumbnail.jpg

import ARKit
import ModelIO
import MetalKit
import UIKit

// MARK: - ScanProject

struct ScanProject: Codable, Identifiable {
    let id:                UUID
    var name:              String
    let createdAt:         Date
    var updatedAt:         Date
    var worldMapFileName:  String?          // "worldmap.arworldmap"
    var meshFileName:      String?          // "mesh.miremesh"
    var usdzFileName:      String?          // "model.usdz"
    var thumbnailFileName: String?          // "thumbnail.jpg"
    var metadataFileName:  String           // "metadata.json"
    var floorArea:         Double           // m²
    var volume:            Double           // m³
    var meshAnchorCount:   Int
    var sessionDuration:   TimeInterval     // segundos
}

// MARK: - ScanProjectManager

class ScanProjectManager {

    static let shared = ScanProjectManager()

    private(set) var projects: [ScanProject] = []

    private var projectsRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("projects")
    }

    private func folder(for project: ScanProject) -> URL {
        projectsRoot.appendingPathComponent(project.id.uuidString)
    }

    // MARK: - Crear

    func createProject(name: String) -> ScanProject {
        let now = Date()
        let project = ScanProject(
            id:                UUID(),
            name:              name,
            createdAt:         now,
            updatedAt:         now,
            worldMapFileName:  nil,
            meshFileName:      nil,
            usdzFileName:      nil,
            thumbnailFileName: nil,
            metadataFileName:  "metadata.json",
            floorArea:         0,
            volume:            0,
            meshAnchorCount:   0,
            sessionDuration:   0
        )
        projects.append(project)
        return project
    }

    // MARK: - Guardar

    func saveProject(_ project: ScanProject,
                     worldMap: ARWorldMap?,
                     meshAnchors: [ARMeshAnchor],
                     thumbnail: UIImage?,
                     completion: @escaping (Bool) -> Void) {

        var updated = project
        updated.updatedAt      = Date()
        updated.meshAnchorCount = meshAnchors.count
        updated.floorArea      = Double(MeshManager.shared.surfaces.floor)
        updated.volume         = Double(VolumeCalculator.shared.totalVolume())

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { completion(false); return }

            let dir = self.folder(for: updated)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            // 1. WorldMap
            if let wm = worldMap,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: wm, requiringSecureCoding: true) {
                let url = dir.appendingPathComponent("worldmap.arworldmap")
                try? data.write(to: url, options: .atomic)
                updated.worldMapFileName = "worldmap.arworldmap"
            }

            // 2. Mesh
            if !meshAnchors.isEmpty {
                let meshURL = dir.appendingPathComponent("mesh.miremesh")
                if let data = try? JSONEncoder().encode(meshAnchors.map { self.encode($0) }) {
                    try? data.write(to: meshURL, options: .atomic)
                    updated.meshFileName = "mesh.miremesh"
                }
            }

            // 3. Thumbnail
            if let img = thumbnail,
               let jpegData = img.jpegData(compressionQuality: 0.75) {
                let url = dir.appendingPathComponent("thumbnail.jpg")
                try? jpegData.write(to: url, options: .atomic)
                updated.thumbnailFileName = "thumbnail.jpg"
            }

            // 4. Metadata
            let metaURL = dir.appendingPathComponent("metadata.json")
            if let data = try? JSONEncoder().encode(updated) {
                try? data.write(to: metaURL, options: .atomic)
            }

            // 5. Actualizar lista en memoria
            DispatchQueue.main.async {
                if let idx = self.projects.firstIndex(where: { $0.id == updated.id }) {
                    self.projects[idx] = updated
                }
                completion(true)
            }
        }
    }

    // MARK: - Exportar USDZ

    func exportUSDZ(for project: ScanProject,
                    anchors: [ARMeshAnchor],
                    completion: @escaping (URL?) -> Void) {

        guard !anchors.isEmpty else { completion(nil); return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { completion(nil); return }

            let asset = self.buildMDLAsset(from: anchors)
            let dir   = self.folder(for: project)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let usdzURL = dir.appendingPathComponent("model.usdz")

            do {
                try asset.export(to: usdzURL)
                // Actualizar metadata
                var updated = project
                updated.usdzFileName = "model.usdz"
                updated.updatedAt    = Date()
                let metaURL = dir.appendingPathComponent("metadata.json")
                if let data = try? JSONEncoder().encode(updated) {
                    try? data.write(to: metaURL, options: .atomic)
                }
                if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                    DispatchQueue.main.async { self.projects[idx] = updated }
                }
                completion(usdzURL)
            } catch {
                print("[ScanProjectManager] exportUSDZ error: \(error)")
                completion(nil)
            }
        }
    }

    // MARK: - Cargar

    func loadProject(_ project: ScanProject,
                     completion: @escaping (ARWorldMap?, [PersistedMeshAnchor]) -> Void) {

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { completion(nil, []); return }
            let dir = self.folder(for: project)

            // WorldMap
            var worldMap: ARWorldMap?
            if let fileName = project.worldMapFileName {
                let url = dir.appendingPathComponent(fileName)
                if let data = try? Data(contentsOf: url) {
                    worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
                }
            }

            // Mesh
            var anchors: [PersistedMeshAnchor] = []
            if let fileName = project.meshFileName {
                let url = dir.appendingPathComponent(fileName)
                if let data = try? Data(contentsOf: url),
                   let decoded = try? JSONDecoder().decode([PersistedMeshAnchor].self, from: data) {
                    anchors = decoded
                }
            }

            DispatchQueue.main.async { completion(worldMap, anchors) }
        }
    }

    // MARK: - Thumbnail

    func loadThumbnail(for project: ScanProject) -> UIImage? {
        guard let fileName = project.thumbnailFileName else { return nil }
        let url = folder(for: project).appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func thumbnailFrom(frame: ARFrame, size: CGSize = CGSize(width: 512, height: 512)) -> UIImage? {
        let ciImage  = CIImage(cvPixelBuffer: frame.capturedImage)
        let context  = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Eliminar

    func deleteProject(_ project: ScanProject) {
        try? FileManager.default.removeItem(at: folder(for: project))
        projects.removeAll { $0.id == project.id }
    }

    // MARK: - Cargar todos los proyectos

    func loadAllProjects() {
        let fm = FileManager.default
        try? fm.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        let dirs = (try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        var loaded: [ScanProject] = []
        for dir in dirs {
            let metaURL = dir.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metaURL),
               let project = try? JSONDecoder().decode(ScanProject.self, from: data) {
                loaded.append(project)
            }
        }
        projects = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Helpers privados

    private func buildMDLAsset(from anchors: [ARMeshAnchor]) -> MDLAsset {
        let asset = MDLAsset()
        guard let device = MTLCreateSystemDefaultDevice() else { return asset }
        let allocator = MTKMeshBufferAllocator(device: device)

        for anchor in anchors {
            let geo       = anchor.geometry
            let transform = anchor.transform
            let vBuf      = geo.vertices
            let fBuf      = geo.faces

            let vPtr    = vBuf.buffer.contents().advanced(by: vBuf.offset).assumingMemoryBound(to: Float.self)
            let vStride = vBuf.stride / MemoryLayout<Float>.stride
            let iPtr    = fBuf.buffer.contents().assumingMemoryBound(to: UInt32.self)
            let iCount  = fBuf.indexCountPerPrimitive

            // Transformar vértices a espacio mundo
            var worldVerts = [Float]()
            worldVerts.reserveCapacity(vBuf.count * 3)
            for i in 0..<vBuf.count {
                let local = SIMD3<Float>(vPtr[i*vStride], vPtr[i*vStride+1], vPtr[i*vStride+2])
                let world = (transform * SIMD4<Float>(local, 1))
                worldVerts.append(world.x)
                worldVerts.append(world.y)
                worldVerts.append(world.z)
            }

            var indices = [UInt32]()
            indices.reserveCapacity(fBuf.count * iCount)
            for f in 0..<fBuf.count {
                for k in 0..<iCount { indices.append(iPtr[f * iCount + k]) }
            }

            guard !worldVerts.isEmpty, !indices.isEmpty else { continue }

            let vData = Data(bytes: worldVerts, count: worldVerts.count * MemoryLayout<Float>.size)
            let iData = Data(bytes: indices,    count: indices.count    * MemoryLayout<UInt32>.size)
            let vBufMDL = allocator.newBuffer(with: vData, type: .vertex)
            let iBufMDL = allocator.newBuffer(with: iData, type: .index)

            let desc = MDLVertexDescriptor()
            desc.attributes[0] = MDLVertexAttribute(
                name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
            desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

            let sub  = MDLSubmesh(indexBuffer: iBufMDL, indexCount: indices.count,
                                  indexType: .uInt32, geometryType: .triangles, material: nil)
            let mesh = MDLMesh(vertexBuffer: vBufMDL,
                               vertexCount: vBuf.count,
                               descriptor: desc,
                               submeshes: [sub])
            asset.add(mesh)
        }
        return asset
    }

    private func encode(_ anchor: ARMeshAnchor) -> PersistedMeshAnchor {
        let geo = anchor.geometry
        let t   = anchor.transform
        let tf: [Float] = [
            t.columns.0.x, t.columns.0.y, t.columns.0.z, t.columns.0.w,
            t.columns.1.x, t.columns.1.y, t.columns.1.z, t.columns.1.w,
            t.columns.2.x, t.columns.2.y, t.columns.2.z, t.columns.2.w,
            t.columns.3.x, t.columns.3.y, t.columns.3.z, t.columns.3.w,
        ]
        let vPtr    = geo.vertices.buffer.contents().advanced(by: geo.vertices.offset).assumingMemoryBound(to: Float.self)
        let vStride = geo.vertices.stride / MemoryLayout<Float>.stride
        var verts = [Float](); verts.reserveCapacity(geo.vertices.count * 3)
        for i in 0..<geo.vertices.count {
            verts.append(vPtr[i*vStride]); verts.append(vPtr[i*vStride+1]); verts.append(vPtr[i*vStride+2])
        }
        let iPtr   = geo.faces.buffer.contents().assumingMemoryBound(to: UInt32.self)
        let iCount = geo.faces.indexCountPerPrimitive
        var indices = [UInt32](); indices.reserveCapacity(geo.faces.count * iCount)
        for f in 0..<geo.faces.count { for k in 0..<iCount { indices.append(iPtr[f*iCount+k]) } }
        let nPtr    = geo.normals.buffer.contents().advanced(by: geo.normals.offset).assumingMemoryBound(to: Float.self)
        let nStride = geo.normals.stride / MemoryLayout<Float>.stride
        var norms = [Float](); norms.reserveCapacity(geo.normals.count * 3)
        for i in 0..<geo.normals.count {
            norms.append(nPtr[i*nStride]); norms.append(nPtr[i*nStride+1]); norms.append(nPtr[i*nStride+2])
        }
        var classes = [UInt8]()
        if let cls = geo.classification {
            let cPtr    = cls.buffer.contents().advanced(by: cls.offset).assumingMemoryBound(to: UInt8.self)
            let cStride = cls.stride
            for f in 0..<geo.faces.count { classes.append(cPtr[f * cStride]) }
        }
        return PersistedMeshAnchor(id: anchor.identifier.uuidString, transform: tf,
                                   vertices: verts, normals: norms,
                                   faceIndices: indices, classifications: classes)
    }
}
