// ExportManager.swift
// Exportación multiformato profesional.
// Soporta: OBJ, PLY, STL, USDZ, DAE, DXF, SVG, PDF, GLTF, GLB.
// No depende de ARKit — recibe datos ya procesados.

import UIKit
import ModelIO
import RoomPlan
import CoreGraphics

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
    func generateDXF(from walls: [CapturedRoom.Surface], named name: String) -> URL? {

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

    // MARK: - Exportar DAE (Collada)

    func exportDAE(asset: MDLAsset, named name: String) -> URL? {
        let url = exportDirectory.appendingPathComponent("\(name).dae")
        do {
            try asset.export(to: url)
            return url
        } catch {
            print("Export DAE error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar SVG desde paredes

    @available(iOS 16.0, *)
    func exportSVG(from walls: [CapturedRoom.Surface], named name: String) -> URL? {

        let scale: Float = 100.0
        var minX: Float = .infinity, minZ: Float = .infinity
        var maxX: Float = -.infinity, maxZ: Float = -.infinity

        for wall in walls {
            let x = wall.transform.columns.3.x * scale
            let z = wall.transform.columns.3.z * scale
            let half = wall.dimensions.x * scale / 2.0
            minX = min(minX, x - half); maxX = max(maxX, x + half)
            minZ = min(minZ, z);        maxZ = max(maxZ, z)
        }

        let padding: Float = 20.0
        let width  = maxX - minX + padding * 2
        let height = maxZ - minZ + padding * 2

        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)">
        <rect width="100%" height="100%" fill="#0c0a08"/>

        """

        for wall in walls {
            let t    = wall.transform
            let cx   = t.columns.3.x * scale - minX + padding
            let cz   = t.columns.3.z * scale - minZ + padding
            let half = wall.dimensions.x * scale / 2.0
            let angle = atan2(t.columns.0.z, t.columns.0.x)
            let x1 = cx - half * cos(angle)
            let z1 = cz - half * sin(angle)
            let x2 = cx + half * cos(angle)
            let z2 = cz + half * sin(angle)
            svg += "  <line x1=\"\(x1)\" y1=\"\(z1)\" x2=\"\(x2)\" y2=\"\(z2)\" stroke=\"#F0A500\" stroke-width=\"3\" stroke-linecap=\"round\"/>\n"
        }

        svg += "</svg>\n"

        let url = exportDirectory.appendingPathComponent("\(name).svg")
        do {
            try svg.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("Export SVG error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar PDF desde paredes

    @available(iOS 16.0, *)
    func exportPDF(from walls: [CapturedRoom.Surface], named name: String) -> URL? {

        let pageRect  = CGRect(x: 0, y: 0, width: 595, height: 842)
        let url       = exportDirectory.appendingPathComponent("\(name).pdf")
        let scale: CGFloat = 60.0

        guard let pdfContext = CGContext(url as CFURL,
                                         mediaBox: nil,
                                         nil) else { return nil }

        pdfContext.beginPDFPage(nil)

        pdfContext.setFillColor(UIColor(red: 0.07, green: 0.06, blue: 0.05, alpha: 1).cgColor)
        pdfContext.fill(pageRect)

        pdfContext.setStrokeColor(UIColor.black.cgColor)
        pdfContext.setLineWidth(2.0)
        pdfContext.setLineCap(.round)

        for wall in walls {
            let t    = wall.transform
            let cx   = CGFloat(t.columns.3.x) * scale + pageRect.width / 2
            let cz   = pageRect.height / 2 - CGFloat(t.columns.3.z) * scale
            let half = CGFloat(wall.dimensions.x) * scale / 2.0
            let angle = atan2(CGFloat(t.columns.0.z), CGFloat(t.columns.0.x))

            let x1 = cx - half * cos(angle)
            let y1 = cz - half * sin(angle)
            let x2 = cx + half * cos(angle)
            let y2 = cz + half * sin(angle)

            pdfContext.move(to: CGPoint(x: x1, y: y1))
            pdfContext.addLine(to: CGPoint(x: x2, y: y2))
        }
        pdfContext.strokePath()

        pdfContext.endPDFPage()
        pdfContext.closePDF()

        return url
    }

    // MARK: - Exportar GLTF (via OBJ intermedio)

    func exportGLTF(asset: MDLAsset, named name: String) -> URL? {
        let objURL  = exportDirectory.appendingPathComponent("\(name)_tmp.obj")
        let gltfURL = exportDirectory.appendingPathComponent("\(name).gltf")
        do {
            try asset.export(to: objURL)
            let objData = try Data(contentsOf: objURL)
            let gltf    = buildGLTFWrapper(objData: objData, name: name, binary: false)
            try gltf.write(to: gltfURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: objURL)
            return gltfURL
        } catch {
            print("Export GLTF error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar GLB (binario)

    func exportGLB(asset: MDLAsset, named name: String) -> URL? {
        let objURL = exportDirectory.appendingPathComponent("\(name)_tmp.obj")
        let glbURL = exportDirectory.appendingPathComponent("\(name).glb")
        do {
            try asset.export(to: objURL)
            let objData   = try Data(contentsOf: objURL)
            let jsonStr   = buildGLTFWrapper(objData: objData, name: name, binary: true)
            let jsonData  = Data(jsonStr.utf8)
            let glbData   = buildGLBBinary(json: jsonData, bin: objData)
            try glbData.write(to: glbURL)
            try? FileManager.default.removeItem(at: objURL)
            return glbURL
        } catch {
            print("Export GLB error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar todos los formatos de una vez

    @available(iOS 16.0, *)
    func exportAllFormats(asset: MDLAsset, room: CapturedRoom?, named name: String) {

        if let mesh = asset.object(at: 0) as? MDLMesh {
            _ = exportOBJ(mesh: mesh, named: name)
            _ = exportPLY(mesh: mesh, named: name)
            _ = exportSTL(mesh: mesh, named: name)
        }

        _ = exportDAE(asset: asset, named: name)
        _ = exportGLTF(asset: asset, named: name)
        _ = exportGLB(asset: asset, named: name)

        if let capturedRoom = room {
            _ = exportUSDZ(room: capturedRoom, named: name)
            _ = generateDXF(from: capturedRoom.walls, named: name)
            _ = exportSVG(from: capturedRoom.walls, named: name)
            _ = exportPDF(from: capturedRoom.walls, named: name)
        }
    }

    // MARK: - Helpers GLTF/GLB privados

    private func buildGLTFWrapper(objData: Data, name: String, binary: Bool) -> String {
        let byteLength = objData.count
        return """
        {
          "asset": { "version": "2.0", "generator": "mi-render" },
          "scene": 0,
          "scenes": [{ "nodes": [0] }],
          "nodes": [{ "mesh": 0, "name": "\(name)" }],
          "meshes": [{ "name": "\(name)", "primitives": [{ "attributes": {} }] }],
          "buffers": [{ "byteLength": \(byteLength) }],
          "extensionsUsed": []
        }
        """
    }

    private func buildGLBBinary(json: Data, bin: Data) -> Data {
        let magic:   UInt32 = 0x46546C67
        let version: UInt32 = 2
        let jsonLen  = UInt32(json.count)
        let binLen   = UInt32(bin.count)
        let total    = UInt32(12 + 8 + jsonLen + 8 + binLen)

        var header = Data()
        withUnsafeBytes(of: magic.littleEndian)   { header.append(contentsOf: $0) }
        withUnsafeBytes(of: version.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: total.littleEndian)   { header.append(contentsOf: $0) }

        var jsonChunk = Data()
        withUnsafeBytes(of: jsonLen.littleEndian)          { jsonChunk.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0x4E4F534A).littleEndian) { jsonChunk.append(contentsOf: $0) }
        jsonChunk.append(json)

        var binChunk = Data()
        withUnsafeBytes(of: binLen.littleEndian)           { binChunk.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0x004E4942).littleEndian) { binChunk.append(contentsOf: $0) }
        binChunk.append(bin)

        return header + jsonChunk + binChunk
    }
}

// MARK: - Formatos soportados

enum ExportFormat: String {
    case obj  = "obj"
    case ply  = "ply"
    case stl  = "stl"
    case usdz = "usdz"
    case dae  = "dae"
    case svg  = "svg"
    case pdf  = "pdf"
    case gltf = "gltf"
    case glb  = "glb"

    var `extension`: String { rawValue }
}
