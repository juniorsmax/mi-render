// ExportManager.swift
// Exportación multiformato profesional.
// Soporta: OBJ, USDZ, PLY, STL, DXF (vía pipeline externo).
// No depende de ARKit — recibe datos ya procesados.

import UIKit
import ModelIO
import RoomPlan

class ExportManager {

    static let shared = ExportManager()

    private let exportDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }()

    init() {
        try? FileManager.default.createDirectory(at: exportDirectory,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Exportar OBJ

    func exportOBJ(mesh: MDLMesh, named name: String) -> URL? {
        let url = exportDirectory.appendingPathComponent("\(name).obj")
        let asset = MDLAsset()
        asset.add(mesh)
        do {
            try asset.export(to: url)
            return url
        } catch {
            print("Export OBJ error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar PLY

    func exportPLY(mesh: MDLMesh, named name: String) -> URL? {
        let url = exportDirectory.appendingPathComponent("\(name).ply")
        let asset = MDLAsset()
        asset.add(mesh)
        do {
            try asset.export(to: url)
            return url
        } catch {
            print("Export PLY error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar STL (para impresión 3D)

    func exportSTL(mesh: MDLMesh, named name: String) -> URL? {
        let url = exportDirectory.appendingPathComponent("\(name).stl")
        let asset = MDLAsset()
        asset.add(mesh)
        do {
            try asset.export(to: url)
            return url
        } catch {
            print("Export STL error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar asset completo (múltiples meshes)

    func exportAsset(_ asset: MDLAsset, format: ExportFormat, named name: String) -> URL? {
        let url = exportDirectory.appendingPathComponent("\(name).\(format.extension)")
        do {
            try asset.export(to: url)
            return url
        } catch {
            print("Export \(format) error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar USDZ desde RoomPlan

    @available(iOS 16.0, *)
    func exportUSDZ(room: CapturedRoom, named name: String) -> URL? {
        let url = exportDirectory.appendingPathComponent("\(name).usdz")
        do {
            try room.export(to: url)
            return url
        } catch {
            print("Export USDZ error: \(error)")
            return nil
        }
    }

    // MARK: - Compartir archivo exportado

    func shareFile(at url: URL, from viewController: UIViewController) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        viewController.present(activityVC, animated: true)
    }

    // MARK: - Listar archivos exportados

    func listExports() -> [URL] {
        let files = try? FileManager.default.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )
        return (files ?? []).sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return d1 > d2
        }
    }

    // MARK: - Generar DXF desde paredes (pipeline)

    @available(iOS 16.0, *)
    func generateDXF(from walls: [CapturedRoom.Wall], named name: String) -> URL? {

        var dxfLines = "0\nSECTION\n2\nENTITIES\n"

        for wall in walls {
            let t = wall.transform
            let w = wall.dimensions.x

            let x1 = t.columns.3.x
            let z1 = t.columns.3.z
            let x2 = x1 + w
            let z2 = z1

            dxfLines += "0\nLINE\n8\n0\n10\n\(x1)\n20\n\(z1)\n30\n0.0\n11\n\(x2)\n21\n\(z2)\n31\n0.0\n"
        }

        dxfLines += "0\nENDSEC\n0\nEOF\n"

        let url = exportDirectory.appendingPathComponent("\(name).dxf")
        do {
            try dxfLines.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("DXF export error: \(error)")
            return nil
        }
    }
}

// MARK: - Formatos soportados

enum ExportFormat: String {
    case obj  = "obj"
    case ply  = "ply"
    case stl  = "stl"
    case usdz = "usdz"

    var `extension`: String { rawValue }
}
