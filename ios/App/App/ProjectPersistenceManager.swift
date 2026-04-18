// ProjectPersistenceManager.swift
// Persiste sesiones de escaneo LiDAR en Documents/projects/<uuid>/
//
// Estructura de cada proyecto:
//   metadata.json          — ProjectMetadata codificado
//   mesh.usdz              — modelo 3D exportado
//   worldMap.arexperience  — ARWorldMap serializado
//   sceneGraph.json        — grafo de nodos 3D (anchors + relaciones)
//   thumbnail.png          — captura PNG del escaneo

import ARKit
import ModelIO
import MetalKit
import UIKit
import simd

// MARK: - Metadata del proyecto

struct ProjectMetadata: Codable {
    let id:              UUID
    var name:            String
    let createdAt:       Date
    var updatedAt:       Date
    var floorArea:       Double     // m²
    var volume:          Double     // m³
    var anchorCount:     Int
    var hasMesh:         Bool
    var hasWorldMap:     Bool
    var hasSceneGraph:   Bool
    var hasThumbnail:    Bool
}

// MARK: - ProjectPersistenceManager

class ProjectPersistenceManager {

    static let shared = ProjectPersistenceManager()

    private let fm = FileManager.default

    private var projectsRoot: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("projects")
    }

    private(set) var loadedProjects: [ProjectMetadata] = []

    // MARK: - Crear proyecto

    @discardableResult
    func createProject(name: String) -> ProjectMetadata {
        let now = Date()
        let meta = ProjectMetadata(
            id:            UUID(),
            name:          name,
            createdAt:     now,
            updatedAt:     now,
            floorArea:     0,
            volume:        0,
            anchorCount:   0,
            hasMesh:       false,
            hasWorldMap:   false,
            hasSceneGraph: false,
            hasThumbnail:  false
        )
        let dir = folder(for: meta.id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        writeMetadata(meta)
        loadedProjects.insert(meta, at: 0)
        return meta
    }

    // MARK: - Guardar WorldMap

    func saveWorldMap(id: UUID,
                      session: ARSession,
                      completion: @escaping (Bool) -> Void) {

        session.getCurrentWorldMap { [weak self] worldMap, error in
            guard let self = self else { return }

            if let error = error {
                print("[ProjectPersistence] WorldMap error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }
            guard let worldMap = worldMap else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            DispatchQueue.global(qos: .utility).async {
                do {
                    let data = try NSKeyedArchiver.archivedData(
                        withRootObject: worldMap, requiringSecureCoding: true)
                    let url = self.folder(for: id).appendingPathComponent("worldMap.arexperience")
                    try data.write(to: url, options: .atomic)
                    self.updateMetadata(id: id) { $0.hasWorldMap = true }
                    print("[ProjectPersistence] WorldMap guardado (\(data.count / 1024) KB)")
                    DispatchQueue.main.async { completion(true) }
                } catch {
                    print("[ProjectPersistence] WorldMap write error: \(error)")
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }
    }

    // MARK: - Guardar Mesh (USDZ)

    func saveMesh(id: UUID,
                  anchors: [ARMeshAnchor],
                  completion: @escaping (URL?) -> Void) {

        guard !anchors.isEmpty else { completion(nil); return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let asset   = self.buildMDLAsset(from: anchors)
            let usdzURL = self.folder(for: id).appendingPathComponent("mesh.usdz")

            do {
                try asset.export(to: usdzURL)
                self.updateMetadata(id: id) {
                    $0.hasMesh     = true
                    $0.anchorCount = anchors.count
                    $0.floorArea   = Double(MeshManager.shared.surfaces.floor)
                    $0.volume      = Double(VolumeCalculator.shared.totalVolume())
                }
                print("[ProjectPersistence] mesh.usdz guardado")
                DispatchQueue.main.async { completion(usdzURL) }
            } catch {
                print("[ProjectPersistence] USDZ export error: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Guardar SceneGraph

    func saveSceneGraph(id: UUID,
                        anchors: [ARMeshAnchor],
                        completion: @escaping (Bool) -> Void) {

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            var graph = SceneGraph(projectId: id)
            for anchor in anchors {
                let cls = anchor.geometry.faces.count > 0
                    ? anchor.geometry.faceClassification(at: 0).debugDescription
                    : "unknown"
                var node = SceneNode(
                    type:      .unknown,
                    label:     cls,
                    transform: anchor.transform
                )
                node.metadata["anchorID"] = anchor.identifier.uuidString
                graph.nodes[node.id] = node
            }

            let graphURL = self.folder(for: id).appendingPathComponent("sceneGraph.json")

            do {
                let data = try JSONEncoder().encode(graph)
                try data.write(to: graphURL, options: .atomic)
                self.updateMetadata(id: id) { $0.hasSceneGraph = true }
                print("[ProjectPersistence] sceneGraph.json guardado (\(graph.nodes.count) nodos)")
                DispatchQueue.main.async { completion(true) }
            } catch {
                print("[ProjectPersistence] sceneGraph write error: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - Guardar Thumbnail

    func saveThumbnail(id: UUID,
                       image: UIImage,
                       completion: @escaping (Bool) -> Void) {

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let size     = CGSize(width: 512, height: 512)
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized  = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }

            guard let pngData = resized.pngData() else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let url = self.folder(for: id).appendingPathComponent("thumbnail.png")
            do {
                try pngData.write(to: url, options: .atomic)
                self.updateMetadata(id: id) { $0.hasThumbnail = true }
                DispatchQueue.main.async { completion(true) }
            } catch {
                print("[ProjectPersistence] thumbnail write error: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    // MARK: - Guardar proyecto completo

    func saveProject(id: UUID,
                     session: ARSession,
                     anchors: [ARMeshAnchor],
                     thumbnail: UIImage?,
                     completion: @escaping (Bool) -> Void) {

        let group = DispatchGroup()
        var allOK = true

        group.enter()
        saveWorldMap(id: id, session: session) { ok in
            if !ok { allOK = false }
            group.leave()
        }

        group.enter()
        saveMesh(id: id, anchors: anchors) { url in
            if url == nil { allOK = false }
            group.leave()
        }

        group.enter()
        saveSceneGraph(id: id, anchors: anchors) { ok in
            if !ok { allOK = false }
            group.leave()
        }

        if let thumb = thumbnail {
            group.enter()
            saveThumbnail(id: id, image: thumb) { _ in group.leave() }
        }

        group.notify(queue: .main) { completion(allOK) }
    }

    // MARK: - Cargar proyecto

    func loadProject(id: UUID) -> (metadata: ProjectMetadata?,
                                   worldMap: ARWorldMap?,
                                   sceneGraph: SceneGraph?) {
        let dir = folder(for: id)

        // Metadata
        let meta = readMetadata(from: dir)

        // WorldMap
        var worldMap: ARWorldMap?
        let wmURL = dir.appendingPathComponent("worldMap.arexperience")
        if let data = try? Data(contentsOf: wmURL) {
            worldMap = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data)
        }

        // SceneGraph
        var sceneGraph: SceneGraph?
        let sgURL = dir.appendingPathComponent("sceneGraph.json")
        if let data = try? Data(contentsOf: sgURL) {
            sceneGraph = try? JSONDecoder().decode(SceneGraph.self, from: data)
        }

        return (meta, worldMap, sceneGraph)
    }

    // MARK: - Cargar todos los proyectos

    func loadAllProjects() {
        try? fm.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        let dirs = (try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        loadedProjects = dirs
            .compactMap { readMetadata(from: $0) }
            .sorted { $0.createdAt > $1.createdAt }

        print("[ProjectPersistence] \(loadedProjects.count) proyectos cargados")
    }

    // MARK: - Thumbnail

    func loadThumbnail(id: UUID) -> UIImage? {
        let url = folder(for: id).appendingPathComponent("thumbnail.png")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func loadThumbnail(for id: UUID) -> UIImage? { loadThumbnail(id: id) }

    // MARK: - Exportar USDZ para compartir

    func usdzURL(for id: UUID) -> URL? {
        let url = folder(for: id).appendingPathComponent("mesh.usdz")
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    /// URL pública del directorio de un proyecto — usada en LiDARPlugin para guardar USDZ.
    func projectFolder(for id: UUID) -> URL { folder(for: id) }

    /// Actualiza campos de metadata de un proyecto — versión pública para LiDARPlugin.
    func updateMeta(id: UUID, update: (inout ProjectMetadata) -> Void) {
        updateMetadata(id: id, update: update)
    }

    // MARK: - Eliminar

    func deleteProject(id: UUID) {
        try? fm.removeItem(at: folder(for: id))
        loadedProjects.removeAll { $0.id == id }
    }

    // MARK: - Helpers privados

    private func folder(for id: UUID) -> URL {
        projectsRoot.appendingPathComponent(id.uuidString)
    }

    private func writeMetadata(_ meta: ProjectMetadata) {
        let url = folder(for: meta.id).appendingPathComponent("metadata.json")
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func readMetadata(from dir: URL) -> ProjectMetadata? {
        let url = dir.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProjectMetadata.self, from: data)
    }

    private func updateMetadata(id: UUID, update: (inout ProjectMetadata) -> Void) {
        let dir = folder(for: id)
        guard var meta = readMetadata(from: dir) else { return }
        meta.updatedAt = Date()
        update(&meta)
        writeMetadata(meta)
        DispatchQueue.main.async {
            if let idx = self.loadedProjects.firstIndex(where: { $0.id == id }) {
                self.loadedProjects[idx] = meta
            }
        }
    }

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

            var worldVerts = [Float]()
            worldVerts.reserveCapacity(vBuf.count * 3)
            for i in 0..<vBuf.count {
                let local = SIMD3<Float>(vPtr[i*vStride], vPtr[i*vStride+1], vPtr[i*vStride+2])
                let world = transform * SIMD4<Float>(local, 1)
                worldVerts.append(world.x); worldVerts.append(world.y); worldVerts.append(world.z)
            }

            var indices = [UInt32]()
            indices.reserveCapacity(fBuf.count * iCount)
            for f in 0..<fBuf.count { for k in 0..<iCount { indices.append(iPtr[f*iCount+k]) } }

            guard !worldVerts.isEmpty, !indices.isEmpty else { continue }

            let vData   = Data(bytes: worldVerts, count: worldVerts.count * MemoryLayout<Float>.size)
            let iData   = Data(bytes: indices,    count: indices.count    * MemoryLayout<UInt32>.size)
            let vBufMDL = allocator.newBuffer(with: vData, type: .vertex)
            let iBufMDL = allocator.newBuffer(with: iData, type: .index)

            let desc = MDLVertexDescriptor()
            desc.attributes[0] = MDLVertexAttribute(
                name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
            desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

            let sub  = MDLSubmesh(indexBuffer: iBufMDL, indexCount: indices.count,
                                  indexType: .uInt32, geometryType: .triangles, material: nil)
            let mesh = MDLMesh(vertexBuffer: vBufMDL, vertexCount: vBuf.count,
                               descriptor: desc, submeshes: [sub])
            asset.add(mesh)
        }
        return asset
    }
}

// MARK: - ARMeshClassification debug

private extension ARMeshClassification {
    var debugDescription: String {
        switch self {
        case .ceiling:  return "ceiling"
        case .door:     return "door"
        case .floor:    return "floor"
        case .seat:     return "seat"
        case .table:    return "table"
        case .wall:     return "wall"
        case .window:   return "window"
        default:        return "none"
        }
    }
}
