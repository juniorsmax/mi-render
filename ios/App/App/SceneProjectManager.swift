// SceneProjectManager.swift
// Sistema de persistencia de proyectos de escaneo.
// Cada sesión de escaneo se guarda como un proyecto en Documents/Projects/<UUID>/
//
// Estructura de carpeta por proyecto:
//   metadata.json      — id, name, createdAt
//   mesh.miremesh      — malla serializada (PersistedMeshAnchor[])
//   floorplan.json     — FloorPlan 2D
//   semantic.json      — SemanticMeshResult
//   cameraPath.json    — nodos de NavigationManager
//   materials.json     — preferencias de MaterialLibraryManager
//   preview.png        — imagen de previsualización

import UIKit
import Foundation

// MARK: - SceneProject

struct SceneProject: Codable, Identifiable, Hashable {
    let id:               UUID
    let name:             String
    let createdAt:        Date
    let meshFileURL:      URL
    let floorplanFileURL: URL
    let semanticFileURL:  URL
    let cameraPathFileURL:URL
    let materialsFileURL: URL
    let previewImageURL:  URL

    // MARK: Hashable & Equatable
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: SceneProject, rhs: SceneProject) -> Bool { lhs.id == rhs.id }

    // MARK: Acceso rápido a la preview como UIImage
    var previewImage: UIImage? { UIImage(contentsOfFile: previewImageURL.path) }
}

// MARK: - Metadata (solo para JSON interno)

private struct SceneProjectMetadata: Codable {
    let id:        UUID
    let name:      String
    let createdAt: Date
}

// MARK: - CameraNodeRecord (serializable)

private struct CameraNodeRecord: Codable {
    let index:    Int
    let x: Float; let y: Float; let z: Float
    let fx: Float; let fy: Float; let fz: Float
}

// MARK: - MaterialPreferencesRecord

private struct MaterialPreferencesRecord: Codable {
    let categoryMaterials: [String: String]   // MeshCategory.rawValue → material.name
}

// MARK: - SceneProjectManager

class SceneProjectManager {

    static let shared = SceneProjectManager()

    private let fm = FileManager.default

    // MARK: Directorios

    var projectsDir: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }

    private func folder(for id: UUID) -> URL {
        projectsDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: - Init

    private init() {
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
    }

    // MARK: - API principal

    /// Copia los archivos de escena indicados a una nueva carpeta de proyecto.
    @discardableResult
    func saveCurrentScene(
        meshURL:       URL,
        floorplanURL:  URL,
        semanticURL:   URL,
        cameraPathURL: URL,
        materialsURL:  URL,
        previewImage:  UIImage,
        name:          String = ""
    ) -> SceneProject? {
        let id      = UUID()
        let projName = name.isEmpty ? "Scan \(formattedDate(Date()))" : name
        let folder  = self.folder(for: id)

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)

            // Archivos de datos
            try copyIfExists(from: meshURL,        to: folder.appendingPathComponent("mesh.miremesh"))
            try copyIfExists(from: floorplanURL,   to: folder.appendingPathComponent("floorplan.json"))
            try copyIfExists(from: semanticURL,    to: folder.appendingPathComponent("semantic.json"))
            try copyIfExists(from: cameraPathURL,  to: folder.appendingPathComponent("cameraPath.json"))
            try copyIfExists(from: materialsURL,   to: folder.appendingPathComponent("materials.json"))

            // Preview PNG
            if let png = previewImage.pngData() {
                try png.write(to: folder.appendingPathComponent("preview.png"), options: .atomic)
            }

            // Metadata
            let meta = SceneProjectMetadata(id: id, name: projName, createdAt: Date())
            let metaData = try JSONEncoder().encode(meta)
            try metaData.write(to: folder.appendingPathComponent("metadata.json"), options: .atomic)

            let project = buildProject(from: meta, folder: folder)
            print("[SceneProjectManager] guardado → \(id.uuidString)")
            NotificationCenter.default.post(name: .sceneProjectListDidChange, object: project)
            return project
        } catch {
            print("[SceneProjectManager] error saveCurrentScene: \(error)")
            try? fm.removeItem(at: folder)
            return nil
        }
    }

    /// Convenience: reúne los archivos de todos los managers y guarda el proyecto.
    @discardableResult
    func saveCurrentState(named name: String = "", previewImage: UIImage) -> SceneProject? {
        // 1. Mesh
        let meshURL = MeshPersistenceManager.shared.saveCurrentMesh()

        // 2. Plano 2D — usa el archivo ya guardado en disco
        let floorplanURL = FloorPlan2DGenerator.shared.savedFloorplanURL

        // 3. Malla semántica — usa la ruta canónica de SemanticMeshResult
        let semanticURL = SemanticMeshResult.saveURL

        // 4. Trayectoria de cámara → JSON temporal
        let cameraPathURL = writeCameraPathJSON()

        // 5. Preferencias de material → JSON temporal
        let materialsURL = writeMaterialPrefsJSON()

        return saveCurrentScene(
            meshURL:       meshURL ?? URL(fileURLWithPath: "/dev/null"),
            floorplanURL:  floorplanURL,
            semanticURL:   semanticURL,
            cameraPathURL: cameraPathURL ?? URL(fileURLWithPath: "/dev/null"),
            materialsURL:  materialsURL ?? URL(fileURLWithPath: "/dev/null"),
            previewImage:  previewImage,
            name:          name
        )
    }

    /// Carga un proyecto: restaura todos los managers y notifica a SceneViewer.
    func loadProject(id: UUID) {
        guard let project = project(for: id) else {
            print("[SceneProjectManager] proyecto no encontrado: \(id)")
            return
        }

        // Restaurar plano 2D
        restoreFloorplan(from: project.floorplanFileURL)

        // Restaurar trayectoria de cámara
        restoreCameraPath(from: project.cameraPathFileURL)

        // Restaurar preferencias de material
        restoreMaterialPrefs(from: project.materialsFileURL)

        // Notificar a SceneViewer (y cualquier observer)
        NotificationCenter.default.post(name: .sceneProjectDidLoad, object: project)
        print("[SceneProjectManager] cargado → \(id.uuidString)")
    }

    func listProjects() -> [SceneProject] {
        let contents = (try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        return contents
            .filter { $0.hasDirectoryPath }
            .compactMap { project(at: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteProject(id: UUID) {
        let folder = self.folder(for: id)
        do {
            try fm.removeItem(at: folder)
            NotificationCenter.default.post(name: .sceneProjectListDidChange, object: id)
            print("[SceneProjectManager] eliminado → \(id.uuidString)")
        } catch {
            print("[SceneProjectManager] error deleteProject: \(error)")
        }
    }

    // MARK: - Acceso a proyecto individual

    func project(for id: UUID) -> SceneProject? {
        project(at: folder(for: id))
    }

    private func project(at folder: URL) -> SceneProject? {
        let metaURL = folder.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(SceneProjectMetadata.self, from: data)
        else { return nil }
        return buildProject(from: meta, folder: folder)
    }

    private func buildProject(from meta: SceneProjectMetadata, folder: URL) -> SceneProject {
        SceneProject(
            id:                meta.id,
            name:              meta.name,
            createdAt:         meta.createdAt,
            meshFileURL:       folder.appendingPathComponent("mesh.miremesh"),
            floorplanFileURL:  folder.appendingPathComponent("floorplan.json"),
            semanticFileURL:   folder.appendingPathComponent("semantic.json"),
            cameraPathFileURL: folder.appendingPathComponent("cameraPath.json"),
            materialsFileURL:  folder.appendingPathComponent("materials.json"),
            previewImageURL:   folder.appendingPathComponent("preview.png")
        )
    }

    // MARK: - Serialización de trayectoria de cámara

    private func writeCameraPathJSON() -> URL? {
        let nodes = NavigationManager.shared.cameraNodes
        guard !nodes.isEmpty else { return nil }

        let records = nodes.map { n in
            CameraNodeRecord(
                index: n.index,
                x: n.position.x, y: n.position.y, z: n.position.z,
                fx: n.forward.x,  fy: n.forward.y,  fz: n.forward.z
            )
        }
        let tempURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("cameraPath_\(Int(Date().timeIntervalSince1970)).json")
        guard let data = try? JSONEncoder().encode(records) else { return nil }
        try? data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    // MARK: - Serialización de preferencias de material

    private func writeMaterialPrefsJSON() -> URL? {
        let lib = MaterialLibraryManager.shared
        var prefs: [String: String] = [:]
        for cat in MeshCategory.allCases {
            if let mat = lib.material(for: cat) {
                prefs[cat.rawValue] = mat.name
            }
        }
        guard !prefs.isEmpty else { return nil }
        let record = MaterialPreferencesRecord(categoryMaterials: prefs)
        let tempURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("materialPrefs_\(Int(Date().timeIntervalSince1970)).json")
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        try? data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    // MARK: - Restauración

    private func restoreFloorplan(from url: URL) {
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let plan = try? JSONDecoder().decode(FloorPlan.self, from: data)
        else { return }
        FloorPlan2DGenerator.shared.save(plan)
    }

    private func restoreCameraPath(from url: URL) {
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([CameraNodeRecord].self, from: data)
        else { return }

        let nodes = records.map { r in
            NavigationManager.CameraNode(
                index:     r.index,
                position:  SIMD3<Float>(r.x, r.y, r.z),
                forward:   SIMD3<Float>(r.fx, r.fy, r.fz),
                transform: simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))  // approx
            )
        }
        NavigationManager.shared.cameraNodes = nodes
    }

    private func restoreMaterialPrefs(from url: URL) {
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(MaterialPreferencesRecord.self, from: data)
        else { return }

        let lib = MaterialLibraryManager.shared
        for (catRaw, matName) in record.categoryMaterials {
            guard let cat = MeshCategory(rawValue: catRaw),
                  let mat = lib.materials.first(where: { $0.name == matName })
            else { continue }
            lib.setMaterial(mat, for: cat)
        }
    }

    // MARK: - Helpers

    private func copyIfExists(from source: URL, to dest: URL) throws {
        guard fm.fileExists(atPath: source.path) else { return }
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: source, to: dest)
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - Notification.Name

extension Notification.Name {
    static let sceneProjectDidLoad      = Notification.Name("mi_render_sceneProjectDidLoad")
    static let sceneProjectListDidChange = Notification.Name("mi_render_sceneProjectListDidChange")
}
