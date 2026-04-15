// IFCExporter.swift
// Exporta a IFC 2x3 Step Physical File Format (.ifc)
// Compatible con: ArchiCAD, Revit, FreeCAD, BIMvision, Solibri
//
// Coordenadas:  ARKit Y-up → IFC Z-up
//   ARKit.x  →  IFC.x
//   ARKit.y  →  IFC.z   (altura)
//   ARKit.-z →  IFC.y   (profundidad)

import UIKit
import RoomPlan
import simd

// MARK: - IFCBuilder (estado interno)

private final class IFCBuilder {

    private(set) var lines: [(id: Int, body: String)] = []
    private var counter = 0

    // ── Asignadores de entidad ────────────────────────────────────────────────

    @discardableResult
    func add(_ body: String) -> Int {
        counter += 1
        lines.append((counter, body))
        return counter
    }

    // ── Geometría primitiva ───────────────────────────────────────────────────

    func pt3(_ x: Float, _ y: Float, _ z: Float) -> Int {
        add("IFCCARTESIANPOINT((\(f(x)),\(f(y)),\(f(z))))")
    }
    func pt2(_ x: Float, _ y: Float) -> Int {
        add("IFCCARTESIANPOINT((\(f(x)),\(f(y))))")
    }
    func dir3(_ x: Float, _ y: Float, _ z: Float) -> Int {
        add("IFCDIRECTION((\(f(x)),\(f(y)),\(f(z))))")
    }
    func ax2d(_ ptId: Int) -> Int {
        add("IFCAXIS2PLACEMENT2D(#\(ptId),$)")
    }
    func ax3d(_ ptId: Int, axis: Int? = nil, refDir: Int? = nil) -> Int {
        let a = axis.map   { "#\($0)" } ?? "$"
        let r = refDir.map { "#\($0)" } ?? "$"
        return add("IFCAXIS2PLACEMENT3D(#\(ptId),\(a),\(r))")
    }
    func localPlac(rel: Int?, ax: Int) -> Int {
        let r = rel.map { "#\($0)" } ?? "$"
        return add("IFCLOCALPLACEMENT(\(r),#\(ax))")
    }
    func rectProfile(origin2d: Int, w: Float, h: Float) -> Int {
        let ax = ax2d(origin2d)
        return add("IFCRECTANGLEPROFILEDEF(.AREA.,$,#\(ax),\(f(w)),\(f(h)))")
    }
    func extrude(profileId: Int, placAx: Int, dirId: Int, depth: Float) -> Int {
        add("IFCEXTRUDEDAREASOLID(#\(profileId),#\(placAx),#\(dirId),\(f(depth)))")
    }
    func shapeRep(ctxId: Int, solidId: Int) -> Int {
        add("IFCSHAPEREPRESENTATION(#\(ctxId),'Body','SweptSolid',(#\(solidId)))")
    }
    func prodDef(repId: Int) -> Int {
        add("IFCPRODUCTDEFINITIONSHAPE($,$,(#\(repId)))")
    }

    // ── Formato numérico ──────────────────────────────────────────────────────

    func f(_ v: Float)  -> String { String(format: "%.4f", v) }
    func f(_ v: Double) -> String { String(format: "%.4f", v) }

    // ── GUID determinista (22 chars, conjunto IFC) ────────────────────────────
    // IFC GUID: base64 con charset personalizado. Derivado del id de entidad.

    func guid(_ seed: Int) -> String {
        let chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$"
        var r = ""
        var v = UInt64(bitPattern: Int64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 0x9E3779B9))
        for _ in 0..<22 {
            v = v &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            r.append(chars[chars.index(chars.startIndex, offsetBy: Int(v & 63))])
        }
        return r
    }
}

// MARK: - IFCExporter

@available(iOS 16.0, *)
class IFCExporter {

    static let shared = IFCExporter()

    private let exportDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }()

    // MARK: Exportar

    func exportIFC(from room: CapturedRoom,
                   segments: [RoomSegment] = [],
                   projectName: String = "mi-render",
                   named name: String) -> URL? {
        try? FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url = exportDirectory.appendingPathComponent("\(name).ifc")

        let content = buildIFC(room: room, segments: segments, projectName: projectName, name: name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            print("IFC export error: \(error)")
            return nil
        }
    }

    // MARK: Construcción del archivo IFC

    private func buildIFC(room: CapturedRoom,
                          segments: [RoomSegment],
                          projectName: String,
                          name: String) -> String {

        let b = IFCBuilder()

        // ── Propietario + aplicación ──────────────────────────────────────────
        let personId = b.add("IFCPERSON($,'mi-render',$,$,$,$,$,$)")
        let orgId    = b.add("IFCORGANIZATION($,'Zerbitecni',$,$,$)")
        let poId     = b.add("IFCPERSONANDORGANIZATION(#\(personId),#\(orgId),$)")
        let appId    = b.add("IFCAPPLICATION(#\(orgId),'1.0','mi-render','mi-render')")
        let ohId     = b.add("IFCOWNERHISTORY(#\(poId),#\(appId),$,.NOTDEFINED.,$,$,$,0)")

        // ── Unidades SI ───────────────────────────────────────────────────────
        let uLen  = b.add("IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.)")
        let uArea = b.add("IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.)")
        let uVol  = b.add("IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.)")
        let uAng  = b.add("IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.)")
        let uAsgn = b.add("IFCUNITASSIGNMENT((#\(uLen),#\(uArea),#\(uVol),#\(uAng)))")

        // ── Contexto geométrico ───────────────────────────────────────────────
        let worldPt  = b.pt3(0, 0, 0)
        let worldAx  = b.ax3d(worldPt)
        let geoCtxId = b.add("IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#\(worldAx),$)")
        let bodyCtxId = b.add("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#\(geoCtxId),$,.MODEL_VIEW.,$)")

        // ── Estructura espacial ───────────────────────────────────────────────
        let projId = b.add("IFCPROJECT('\(b.guid(1))',#\(ohId),'\(projectName)',$,$,$,$,(#\(geoCtxId)),#\(uAsgn))")

        let sitePlac = b.localPlac(rel: nil, ax: worldAx)
        let siteId   = b.add("IFCSITE('\(b.guid(2))',#\(ohId),'Sitio',$,$,#\(sitePlac),$,$,.ELEMENT.,$,$,$,$,$)")

        let bldPlac  = b.localPlac(rel: sitePlac, ax: worldAx)
        let bldId    = b.add("IFCBUILDING('\(b.guid(3))',#\(ohId),'Edificio',$,$,#\(bldPlac),$,$,.ELEMENT.,$,$,$)")

        let stPlac   = b.localPlac(rel: bldPlac, ax: worldAx)
        let storeyId = b.add("IFCBUILDINGSTOREY('\(b.guid(4))',#\(ohId),'Planta Baja',$,$,#\(stPlac),$,$,.ELEMENT.,0.)")

        // Agregaciones
        let ra1 = b.add("IFCRELAGGREGATES('\(b.guid(10))',#\(ohId),$,$,#\(projId),(#\(siteId)))")
        let ra2 = b.add("IFCRELAGGREGATES('\(b.guid(11))',#\(ohId),$,$,#\(siteId),(#\(bldId)))")
        let ra3 = b.add("IFCRELAGGREGATES('\(b.guid(12))',#\(ohId),$,$,#\(bldId),(#\(storeyId)))")
        _ = (ra1, ra2, ra3)

        // ── Espacios (habitaciones) ───────────────────────────────────────────
        var contained = [Int]()
        let zUp = b.dir3(0, 0, 1)

        if !segments.isEmpty {
            for (i, seg) in segments.enumerated() {
                let h   = max(0.5, seg.avgHeight > 0.1 ? seg.avgHeight : 2.4)
                let bw  = seg.bboxMax.x - seg.bboxMin.x
                let bd  = seg.bboxMax.y - seg.bboxMin.y

                // Posición del espacio (ARKit→IFC)
                let spt  = b.pt3(seg.centroid.x, 0, -seg.centroid.y)
                let sax  = b.ax3d(spt, axis: zUp)
                let splc = b.localPlac(rel: stPlac, ax: sax)

                // Geometría extruida
                let pOrig  = b.pt2(-bw/2, -bd/2)
                let prof   = b.rectProfile(origin2d: pOrig, w: bw, h: bd)
                let extAx  = b.ax3d(b.pt3(0, 0, 0))
                let solid  = b.extrude(profileId: prof, placAx: extAx, dirId: zUp, depth: h)
                let srep   = b.shapeRep(ctxId: bodyCtxId, solidId: solid)
                let pdef   = b.prodDef(repId: srep)

                let spId = b.add(
                    "IFCSPACE('\(b.guid(100 + i))',#\(ohId),'\(seg.label)',$,'Espacio \(i+1)',#\(splc),#\(pdef),$,.ELEMENT.,.INTERNAL.,0.)"
                )
                contained.append(spId)
            }
        } else {
            // Espacio único sin geometría
            let spt  = b.pt3(0, 0, 0)
            let sax  = b.ax3d(spt, axis: zUp)
            let splc = b.localPlac(rel: stPlac, ax: sax)
            let spId = b.add(
                "IFCSPACE('\(b.guid(100))',#\(ohId),'Habitacion',$,'Espacio principal',#\(splc),$,$,.ELEMENT.,.INTERNAL.,0.)"
            )
            contained.append(spId)
        }

        // ── Paredes ────────────────────────────────────────────────────────────
        for (i, wall) in room.walls.enumerated() {
            let t  = wall.transform
            let wL = wall.dimensions.x  // longitud
            let wH = wall.dimensions.y  // altura
            let wT = max(0.05, wall.dimensions.z)  // grosor

            // Centro pared en IFC
            let cx = t.columns.3.x
            let cy = t.columns.3.y          // IFC Z (altura)
            let cz = -t.columns.3.z         // IFC Y

            // Dirección longitudinal (IFC XY plane)
            let lx = t.columns.0.x
            let ly = -t.columns.0.z

            let wpt  = b.pt3(cx, cz, cy)   // (IFC x, IFC y, IFC z)
            let xRef = b.dir3(lx, ly, 0)
            let wax  = b.ax3d(wpt, axis: zUp, refDir: xRef)
            let wplc = b.localPlac(rel: stPlac, ax: wax)

            // Perfil centrado en origen, extruido en Z (altura)
            let pOrig = b.pt2(-wL/2, -wT/2)
            let prof  = b.rectProfile(origin2d: pOrig, w: wL, h: wT)
            let extAx = b.ax3d(b.pt3(0, 0, 0))
            let solid = b.extrude(profileId: prof, placAx: extAx, dirId: zUp, depth: wH)
            let srep  = b.shapeRep(ctxId: bodyCtxId, solidId: solid)
            let pdef  = b.prodDef(repId: srep)

            let wId = b.add(
                "IFCWALLSTANDARDCASE('\(b.guid(200 + i))',#\(ohId),'Pared \(i+1)',$,'Muro',#\(wplc),#\(pdef),$)"
            )
            contained.append(wId)
        }

        // ── Puertas ────────────────────────────────────────────────────────────
        for (i, door) in room.doors.enumerated() {
            let t  = door.transform
            let dpt  = b.pt3(t.columns.3.x, -t.columns.3.z, t.columns.3.y)
            let dax  = b.ax3d(dpt, axis: zUp)
            let dplc = b.localPlac(rel: stPlac, ax: dax)
            let W = door.dimensions.x; let H = door.dimensions.y

            let dId = b.add(
                "IFCDOOR('\(b.guid(300 + i))',#\(ohId),'Puerta \(i+1)',$,'Puerta',#\(dplc),$,$,\(b.f(H)),\(b.f(W)))"
            )
            contained.append(dId)
        }

        // ── Ventanas ───────────────────────────────────────────────────────────
        for (i, win) in room.windows.enumerated() {
            let t  = win.transform
            let wpt  = b.pt3(t.columns.3.x, -t.columns.3.z, t.columns.3.y)
            let wax  = b.ax3d(wpt, axis: zUp)
            let wplc = b.localPlac(rel: stPlac, ax: wax)
            let W = win.dimensions.x; let H = win.dimensions.y

            let wiId = b.add(
                "IFCWINDOW('\(b.guid(400 + i))',#\(ohId),'Ventana \(i+1)',$,'Ventana',#\(wplc),$,$,\(b.f(H)),\(b.f(W)))"
            )
            contained.append(wiId)
        }

        // ── Relación ContainedInSpatialStructure ──────────────────────────────
        if !contained.isEmpty {
            let items = contained.map { "#\($0)" }.joined(separator: ",")
            b.add("IFCRELCONTAINEDINSPATIALSTRUCTURE('\(b.guid(500))',#\(ohId),$,$,(\(items)),#\(storeyId))")
        }

        // ── Ensamblar archivo ─────────────────────────────────────────────────
        let dateStr = ISO8601DateFormatter().string(from: Date())
        var out  = "ISO-10303-21;\nHEADER;\n"
        out     += "FILE_DESCRIPTION(('IFC2X3 ViewDefinition [CoordinationView]'),'2;1');\n"
        out     += "FILE_NAME('\(name).ifc','\(dateStr)',(''),'','mi-render 1.0','','');\n"
        out     += "FILE_SCHEMA(('IFC2X3'));\nENDSEC;\n\n"
        out     += "DATA;\n"
        for entry in b.lines.sorted(by: { $0.id < $1.id }) {
            out += "#\(entry.id)=\(entry.body);\n"
        }
        out += "ENDSEC;\nEND-ISO-10303-21;\n"
        return out
    }
}
