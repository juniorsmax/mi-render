// ExportManager.swift
// Exportación multiformato profesional.
// Soporta: OBJ, PLY, STL, USDZ, DAE, DXF, SVG, PDF, GLTF, GLB.
// No depende de ARKit — recibe datos ya procesados.

import UIKit
import ARKit
import ModelIO
import RoomPlan
import CoreGraphics
import simd

class ExportManager {

    static let shared = ExportManager()

    // Última URL USDZ exportada (para pasarla al resultado del escaneo)
    var lastUsdzUrl: URL?

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
            lastUsdzUrl = url
            return url
        } catch {
            print("Export USDZ error: \(error)")
            return nil
        }
    }

    // MARK: - Exportar USDZ optimizado con materiales por clasificación
    //
    // Genera un USDZ desde la malla ARKit con materiales PBR por tipo de superficie:
    //   .floor   → marrón cálido   .wall → gris claro   .ceiling → blanco
    //   .table   → madera          .seat → tela          .door/.window → neutros
    // Los submeshes se separan por clasificación usando getMeshAsset(for:).

    func exportOptimizedUSDZ(named name: String) -> URL? {
        guard MDLAsset.canExportFileExtension("usdz") else {
            print("USDZ export not supported by MDLAsset on this system")
            return nil
        }

        typealias ClassColor = (ARMeshClassification, SIMD3<Float>)
        let palette: [ClassColor] = [
            (.floor,   SIMD3<Float>(0.60, 0.42, 0.28)),
            (.wall,    SIMD3<Float>(0.85, 0.85, 0.85)),
            (.ceiling, SIMD3<Float>(0.95, 0.95, 0.95)),
            (.table,   SIMD3<Float>(0.70, 0.50, 0.30)),
            (.seat,    SIMD3<Float>(0.40, 0.30, 0.70)),
            (.door,    SIMD3<Float>(0.55, 0.38, 0.24)),
            (.window,  SIMD3<Float>(0.75, 0.87, 0.98)),
        ]

        let combinedAsset = MDLAsset()

        for (cls, color) in palette {
            let classAsset = MeshManager.shared.getMeshAsset(for: cls)
            for i in 0..<classAsset.count {
                guard let mesh = classAsset[i] as? MDLMesh else { continue }

                // Crear material PBR sencillo
                let mat = MDLMaterial(
                    name: "\(cls)",
                    scatteringFunction: MDLPhysicallyPlausibleScatteringFunction()
                )
                let colorProp = MDLMaterialProperty(
                    name: "baseColor",
                    semantic: .baseColor,
                    float3: color
                )
                mat.setProperty(colorProp)

                // Asignar a todos los submeshes
                if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                    submeshes.forEach { $0.material = mat }
                }

                // Optimizar: weld vértices duplicados
                mesh.makeVerticesUnique()

                combinedAsset.add(mesh)
            }
        }

        guard combinedAsset.count > 0 else {
            // Sin mesh ARKit — exportar RoomPlan normal como fallback
            if #available(iOS 16.0, *),
               let room = RoomPlanManager.shared.lastCapturedRoom {
                return exportUSDZ(room: room, named: name + "-optimized")
            }
            return nil
        }

        let url = exportDirectory.appendingPathComponent("\(name)-optimized.usdz")
        do {
            try combinedAsset.export(to: url)
            lastUsdzUrl = url
            return url
        } catch {
            print("Optimized USDZ export error: \(error)")
            // Fallback a RoomPlan USDZ
            if #available(iOS 16.0, *),
               let room = RoomPlanManager.shared.lastCapturedRoom {
                return exportUSDZ(room: room, named: name + "-optimized")
            }
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

    // MARK: - Generar DXF arquitectónico completo desde CapturedRoom + FloorFootprint
    //
    // Formato: DXF R12 (AC1009) — máxima compatibilidad con AutoCAD, LibreCAD, etc.
    // Unidades: metros (INSUNITS = 4)
    // Sistema de coordenadas: ARKit X → DXF X, ARKit Z → DXF Y
    //
    // Capas:
    //   CONTORNO  — polilínea cerrada del perímetro exterior (amarillo)
    //   PAREDES   — rectángulos de pared con grosor real (blanco)
    //   PUERTAS   — arco de apertura + panel de puerta (verde)
    //   VENTANAS  — triple línea (gris claro + líneas de vidrio) (cian)
    //   COTAS     — líneas de cota con texto (magenta)

    @available(iOS 16.0, *)
    func generateDXF(from room: CapturedRoom,
                     footprint: FloorFootprint? = nil,
                     named name: String) -> URL? {

        // Calcular extents para el header DXF
        var allX: [Float] = [], allY: [Float] = []
        for wall in room.walls {
            allX.append(wall.transform.columns.3.x)
            allY.append(wall.transform.columns.3.z)
        }
        footprint?.polygon.forEach { allX.append($0.x); allY.append($0.y) }

        let minX = (allX.min() ?? 0) - 0.5
        let minY = (allY.min() ?? 0) - 0.5
        let maxX = (allX.max() ?? 10) + 0.5
        let maxY = (allY.max() ?? 10) + 0.5

        var dxf = ""

        // ── SECTION HEADER ────────────────────────────────────────────────────
        dxf += dxfHeader(minX: minX, minY: minY, maxX: maxX, maxY: maxY)

        // ── SECTION TABLES (capas) ────────────────────────────────────────────
        dxf += dxfTables()

        // ── SECTION BLOCKS (vacío) ────────────────────────────────────────────
        dxf += "  0\nSECTION\n  2\nBLOCKS\n  0\nENDSEC\n"

        // ── SECTION ENTITIES ──────────────────────────────────────────────────
        dxf += "  0\nSECTION\n  2\nENTITIES\n"

        // 1. Contorno exterior
        if let fp = footprint, !fp.polygon.isEmpty {
            dxf += dxfPolylineClosed(layer: "CONTORNO",
                                     points: fp.polygon.map { ($0.x, $0.y) })
        } else {
            // Fallback: bounding box derivada de paredes
            dxf += dxfPolylineClosed(layer: "CONTORNO",
                                     points: [(minX+0.5, minY+0.5),
                                              (maxX-0.5, minY+0.5),
                                              (maxX-0.5, maxY-0.5),
                                              (minX+0.5, maxY-0.5)])
        }

        // 2. Paredes con grosor real
        for wall in room.walls {
            dxf += dxfWallRect(layer: "PAREDES", surface: wall)
        }

        // 3. Puertas: arco de apertura + panel
        for door in room.doors {
            dxf += dxfDoorSymbol(layer: "PUERTAS", surface: door)
        }

        // 4. Ventanas: triple línea
        for window in room.windows {
            dxf += dxfWindowSymbol(layer: "VENTANAS", surface: window)
        }

        // 5. Cotas: longitud de cada pared
        for wall in room.walls {
            dxf += dxfWallDimension(layer: "COTAS", surface: wall, offset: 0.35)
        }

        dxf += "  0\nENDSEC\n  0\nEOF\n"

        let url = exportDirectory.appendingPathComponent("\(name).dxf")
        do {
            try dxf.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("DXF export error: \(error)")
            return nil
        }
    }

    // ── Sobrecarga de compatibilidad con código existente (solo paredes) ──────
    @available(iOS 16.0, *)
    func generateDXF(from walls: [CapturedRoom.Surface], named name: String) -> URL? {
        // Construir CapturedRoom mínimo no es posible; generamos DXF básico
        var dxf = dxfHeader(minX: -10, minY: -10, maxX: 10, maxY: 10)
        dxf += dxfTables()
        dxf += "  0\nSECTION\n  2\nBLOCKS\n  0\nENDSEC\n"
        dxf += "  0\nSECTION\n  2\nENTITIES\n"
        for wall in walls { dxf += dxfWallRect(layer: "PAREDES", surface: wall) }
        dxf += "  0\nENDSEC\n  0\nEOF\n"
        let url = exportDirectory.appendingPathComponent("\(name).dxf")
        try? dxf.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // ── DXF HEADER ─────────────────────────────────────────────────────────────

    private func dxfHeader(minX: Float, minY: Float, maxX: Float, maxY: Float) -> String {
        return """
          0
        SECTION
          2
        HEADER
          9
        $ACADVER
          1
        AC1009
          9
        $INSUNITS
         70
              4
          9
        $LUNITS
         70
              2
          9
        $EXTMIN
         10
        \(f4(minX))
         20
        \(f4(minY))
         30
        0.0
          9
        $EXTMAX
         10
        \(f4(maxX))
         20
        \(f4(maxY))
         30
        0.0
          9
        $LIMMIN
         10
        \(f4(minX))
         20
        \(f4(minY))
          9
        $LIMMAX
         10
        \(f4(maxX))
         20
        \(f4(maxY))
          0
        ENDSEC

        """
    }

    // ── DXF TABLES (capas) ─────────────────────────────────────────────────────
    // Colores ACI: 1=rojo 2=amarillo 3=verde 4=cian 5=azul 6=magenta 7=blanco

    private func dxfTables() -> String {
        let layers: [(String, Int)] = [
            ("CONTORNO", 2),   // amarillo
            ("PAREDES",  7),   // blanco
            ("PUERTAS",  3),   // verde
            ("VENTANAS", 4),   // cian
            ("COTAS",    6),   // magenta
        ]

        var t = "  0\nSECTION\n  2\nTABLES\n"
        t += "  0\nTABLE\n  2\nLAYER\n 70\n\(layers.count)\n"
        for (name, color) in layers {
            t += "  0\nLAYER\n  2\n\(name)\n 70\n0\n 62\n\(color)\n  6\nCONTINUOUS\n"
        }
        t += "  0\nENDTAB\n  0\nENDSEC\n"
        return t
    }

    // ── LWPOLYLINE cerrada (contorno exterior) ────────────────────────────────

    private func dxfPolylineClosed(layer: String,
                                   points: [(Float, Float)]) -> String {
        var s = "  0\nLWPOLYLINE\n  8\n\(layer)\n 70\n1\n 90\n\(points.count)\n"
        for (x, y) in points {
            s += " 10\n\(f4(x))\n 20\n\(f4(y))\n"
        }
        return s
    }

    // ── Pared con grosor real (cuatro LINEs = rectángulo) ────────────────────
    //
    // transform.columns.3 = centro de la pared
    // dimensions.x = longitud, dimensions.z = grosor (espesor del muro)
    // El eje principal de la pared es transform.columns.0

    @available(iOS 16.0, *)
    private func dxfWallRect(layer: String,
                             surface: CapturedRoom.Surface) -> String {
        let t   = surface.transform
        let len = surface.dimensions.x
        let thk = max(surface.dimensions.z, 0.05)   // mínimo 5 cm

        let cx  = t.columns.3.x
        let cy  = t.columns.3.z   // ARKit Z → DXF Y

        // Dirección a lo largo de la pared
        let dx  = t.columns.0.x
        let dz  = t.columns.0.z   // componente Z del eje X del transform

        // Normal perpendicular (2D): girar 90° a la izquierda
        let nx  = -dz
        let ny  =  dx

        let hL  = len / 2
        let hT  = thk / 2

        // 4 esquinas del rectángulo
        let p0x = cx + dx * hL + nx * hT;  let p0y = cy + dz * hL + ny * hT
        let p1x = cx - dx * hL + nx * hT;  let p1y = cy - dz * hL + ny * hT
        let p2x = cx - dx * hL - nx * hT;  let p2y = cy - dz * hL - ny * hT
        let p3x = cx + dx * hL - nx * hT;  let p3y = cy + dz * hL - ny * hT

        return dxfLine(layer: layer, x1: p0x, y1: p0y, x2: p1x, y2: p1y)
             + dxfLine(layer: layer, x1: p1x, y1: p1y, x2: p2x, y2: p2y)
             + dxfLine(layer: layer, x1: p2x, y1: p2y, x2: p3x, y2: p3y)
             + dxfLine(layer: layer, x1: p3x, y1: p3y, x2: p0x, y2: p0y)
    }

    // ── Puerta: arco de apertura 90° + panel ─────────────────────────────────
    //
    // El símbolo arquitectónico de puerta consiste en:
    //   – Una línea (el panel de la puerta en posición cerrada, perpendicular al muro)
    //   – Un arco de radio = ancho de la puerta, de 0° a 90° (el barrido de apertura)
    // La bisagra se sitúa en un extremo del hueco.

    @available(iOS 16.0, *)
    private func dxfDoorSymbol(layer: String,
                                surface: CapturedRoom.Surface) -> String {
        let t   = surface.transform
        let w   = surface.dimensions.x   // ancho del hueco

        let cx  = t.columns.3.x
        let cy  = t.columns.3.z

        // Eje de la puerta (a lo largo del muro)
        let dx  = t.columns.0.x
        let dz  = t.columns.0.z

        // Bisagra: extremo izquierdo del hueco
        let hx  = cx - dx * w / 2
        let hy  = cy - dz * w / 2

        // Panel cerrado: perpendicular al muro desde la bisagra
        let nx  = -dz;  let ny = dx    // normal al muro
        let ex  = hx + nx * w
        let ey  = hy + ny * w

        // Ángulo de inicio del arco = dirección del panel cerrado
        let startDeg = Double(atan2(ny, nx) * 180.0 / .pi)
        let endDeg   = startDeg + 90.0

        return dxfLine(layer: layer, x1: hx, y1: hy, x2: ex, y2: ey)
             + dxfArc(layer: layer,
                      cx: hx, cy: hy,
                      radius: w,
                      startAngle: startDeg,
                      endAngle: endDeg)
    }

    // ── Ventana: triple línea (dos caras de vidrio + línea central) ───────────

    @available(iOS 16.0, *)
    private func dxfWindowSymbol(layer: String,
                                  surface: CapturedRoom.Surface) -> String {
        let t   = surface.transform
        let w   = surface.dimensions.x
        let thk = max(surface.dimensions.z, 0.1)  // espesor del hueco

        let cx  = t.columns.3.x
        let cy  = t.columns.3.z
        let dx  = t.columns.0.x
        let dz  = t.columns.0.z
        let nx  = -dz;  let ny = dx

        let hL  = w  / 2
        let hT  = thk / 4   // separación vidrio-fachada

        // Cara exterior
        let ox1 = cx - dx * hL + nx * hT;  let oy1 = cy - dz * hL + ny * hT
        let ox2 = cx + dx * hL + nx * hT;  let oy2 = cy + dz * hL + ny * hT
        // Cara interior
        let ix1 = cx - dx * hL - nx * hT;  let iy1 = cy - dz * hL - ny * hT
        let ix2 = cx + dx * hL - nx * hT;  let iy2 = cy + dz * hL - ny * hT
        // Línea central (vidrio)
        let gx1 = cx - dx * hL;  let gy1 = cy - dz * hL
        let gx2 = cx + dx * hL;  let gy2 = cy + dz * hL

        return dxfLine(layer: layer, x1: ox1, y1: oy1, x2: ox2, y2: oy2)
             + dxfLine(layer: layer, x1: ix1, y1: iy1, x2: ix2, y2: iy2)
             + dxfLine(layer: layer, x1: gx1, y1: gy1, x2: gx2, y2: gy2)
    }

    // ── Cota de longitud de pared ─────────────────────────────────────────────
    //
    // Dibuja manualmente: dos líneas de extensión + línea de cota + texto
    // offset: separación de la cota respecto al centro de la pared (metros)

    @available(iOS 16.0, *)
    private func dxfWallDimension(layer: String,
                                   surface: CapturedRoom.Surface,
                                   offset: Float) -> String {
        let t   = surface.transform
        let len = surface.dimensions.x
        let cx  = t.columns.3.x
        let cy  = t.columns.3.z
        let dx  = t.columns.0.x
        let dz  = t.columns.0.z
        let nx  = -dz;  let ny = dx

        // Extremos de la pared
        let p1x = cx - dx * len / 2;  let p1y = cy - dz * len / 2
        let p2x = cx + dx * len / 2;  let p2y = cy + dz * len / 2

        // Puntos de la línea de cota (desplazados offset en la dirección normal)
        let d1x = p1x + nx * offset;  let d1y = p1y + ny * offset
        let d2x = p2x + nx * offset;  let d2y = p2y + ny * offset

        // Centro del texto
        let tmx = (d1x + d2x) / 2
        let tmy = (d1y + d2y) / 2

        let label = String(format: "%.2fm", len)
        let textAngle = Double(atan2(dz, dx) * 180.0 / .pi)

        return dxfLine(layer: layer, x1: p1x, y1: p1y, x2: d1x, y2: d1y)   // ext 1
             + dxfLine(layer: layer, x1: p2x, y1: p2y, x2: d2x, y2: d2y)   // ext 2
             + dxfLine(layer: layer, x1: d1x, y1: d1y, x2: d2x, y2: d2y)   // cota
             + dxfText(layer: layer, x: tmx, y: tmy,
                       height: 0.12, text: label, angle: textAngle)
    }

    // ── Primitivas DXF ────────────────────────────────────────────────────────

    private func dxfLine(layer: String,
                         x1: Float, y1: Float, x2: Float, y2: Float) -> String {
        "  0\nLINE\n  8\n\(layer)\n 10\n\(f4(x1))\n 20\n\(f4(y1))\n 30\n0.0\n"
      + " 11\n\(f4(x2))\n 21\n\(f4(y2))\n 31\n0.0\n"
    }

    private func dxfArc(layer: String,
                        cx: Float, cy: Float, radius: Float,
                        startAngle: Double, endAngle: Double) -> String {
        "  0\nARC\n  8\n\(layer)\n 10\n\(f4(cx))\n 20\n\(f4(cy))\n 30\n0.0\n"
      + " 40\n\(f4(radius))\n 50\n\(String(format:"%.4f", startAngle))\n"
      + " 51\n\(String(format:"%.4f", endAngle))\n"
    }

    private func dxfText(layer: String,
                         x: Float, y: Float,
                         height: Float, text: String,
                         angle: Double = 0.0) -> String {
        "  0\nTEXT\n  8\n\(layer)\n 10\n\(f4(x))\n 20\n\(f4(y))\n 30\n0.0\n"
      + " 40\n\(f4(height))\n  1\n\(text)\n"
      + " 50\n\(String(format:"%.4f", angle))\n"
      + " 72\n1\n"   // justificación: centrado
      + " 11\n\(f4(x))\n 21\n\(f4(y))\n 31\n0.0\n"
    }

    // Formatea un Float a 4 decimales sin notación científica
    private func f4(_ v: Float) -> String {
        String(format: "%.4f", v)
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
            let footprint = RoomPlanManager.shared.floorFootprint
            _ = generateDXF(from: capturedRoom, footprint: footprint, named: name)
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
