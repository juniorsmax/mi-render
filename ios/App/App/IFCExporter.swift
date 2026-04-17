// IFCExporter.swift
// Exportador BIM con dos rutas de salida:
//
//   ① STEP (.ifc)       — IFC2X3, generado desde CapturedRoom (RoomPlan, iOS 16+)
//                         Compatible con: ArchiCAD, Revit, FreeCAD, BIMvision, Solibri
//
//   ② JSON (.ifc.json)  — ifcJSON 0.1 / IFC4, generado desde SceneGraph
//                         Compatible con: Blender BIM (ifcOpenShell), Archicad IFC4, Revit IFC4
//                         Ruta: Documents/projects/{projectId}/model.ifc.json
//
// Coordenadas:  ARKit Y-up → IFC Z-up
//   ARKit.x  →  IFC.x
//   ARKit.y  →  IFC.z   (altura)
//   ARKit.-z →  IFC.y   (profundidad)

import UIKit
import RoomPlan
import simd

// MARK: ─── IFCBuilder (generador STEP) ───────────────────────────────────────

private final class IFCBuilder {

    private(set) var lines: [(id: Int, body: String)] = []
    private var counter = 0

    @discardableResult
    func add(_ body: String) -> Int {
        counter += 1
        lines.append((counter, body))
        return counter
    }

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

    func f(_ v: Float)  -> String { String(format: "%.4f", v) }
    func f(_ v: Double) -> String { String(format: "%.4f", v) }

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

// MARK: ─── IFCExporter ────────────────────────────────────────────────────────

class IFCExporter {

    static let shared = IFCExporter()

    private let fm = FileManager.default

    private var exportDirectory: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }

    // MARK: ══════════════════════════════════════════════════════════════════
    // MARK: Ruta ①: IFC STEP (.ifc) desde CapturedRoom (iOS 16+)

    @available(iOS 16.0, *)
    func exportIFC(from room: CapturedRoom,
                   segments: [RoomSegment] = [],
                   projectName: String = "mi-render",
                   named name: String) -> URL? {

        try? fm.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url     = exportDirectory.appendingPathComponent("\(name).ifc")
        let content = buildSTEP(room: room, segments: segments,
                                 projectName: projectName, name: name)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("[IFCExporter] STEP → \(url.lastPathComponent)")
            return url
        } catch {
            print("[IFCExporter] STEP error: \(error)")
            return nil
        }
    }

    // MARK: ══════════════════════════════════════════════════════════════════
    // MARK: Ruta ②: ifcJSON (.ifc.json) desde SceneGraph

    /// Carga el SceneGraph del proyecto desde disco y exporta `model.ifc.json`.
    func exportJSON(projectId: UUID,
                    completion: @escaping (Result<URL, Error>) -> Void) {

        SceneGraphManager.shared.loadGraph(projectId: projectId) { [weak self] ok in
            guard let self = self, ok else {
                completion(.failure(IFCError.noSceneGraph)); return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let doc = self.buildIFCJSON(graph:     SceneGraphManager.shared.graph,
                                             projectId: projectId)
                self.writeJSON(doc, projectId: projectId, completion: completion)
            }
        }
    }

    /// Exporta directamente desde un SceneGraph en memoria.
    func exportJSON(graph: SceneGraph,
                    projectId: UUID,
                    completion: @escaping (Result<URL, Error>) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let doc = self.buildIFCJSON(graph: graph, projectId: projectId)
            self.writeJSON(doc, projectId: projectId, completion: completion)
        }
    }

    // MARK: ══════════════════════════════════════════════════════════════════
    // MARK: Constructor del documento ifcJSON

    private func buildIFCJSON(graph: SceneGraph, projectId: UUID) -> [String: Any] {
        var entities: [[String: Any]] = []

        // ── IDs de jerarquía espacial ────────────────────────────────────
        let projectGid  = ifcGid(projectId)
        let siteGid     = ifcGid()
        let buildingGid = ifcGid()
        let storeyGid   = ifcGid()
        let unitGid     = ifcGid()
        let ctxGid      = ifcGid()

        entities.append(unitAssignment(globalId: unitGid))
        entities.append(geometricContext(globalId: ctxGid))

        // ── Jerarquía espacial ───────────────────────────────────────────
        let rootLabel = graph.nodes[graph.rootId ?? UUID()]?.label ?? "mi-render"
        entities.append(ifcProject(globalId: projectGid, name: rootLabel,
                                    unitGid: unitGid, ctxGid: ctxGid))
        entities.append(ifcSite(globalId: siteGid))
        entities.append(ifcBuilding(globalId: buildingGid, graph: graph))
        entities.append(ifcBuildingStorey(globalId: storeyGid))

        // ── Elementos del modelo ─────────────────────────────────────────
        var storeyGids: [String] = []

        for node in graph.nodes.values {
            guard node.id != graph.rootId else { continue }

            switch node.type {
            case .room:
                let g = jsonSpace(node: node)
                entities.append(g.entity)
                storeyGids.append(g.gid)

            case .wall:
                let g = jsonWall(node: node)
                entities.append(g.entity)
                storeyGids.append(g.gid)

            case .door:
                let g = jsonDoor(node: node)
                entities.append(g.entity)
                storeyGids.append(g.gid)

            case .window:
                let g = jsonWindow(node: node)
                entities.append(g.entity)
                storeyGids.append(g.gid)

            case .floor:
                let g = jsonSlab(node: node, predefinedType: "FLOOR")
                entities.append(g.entity)
                storeyGids.append(g.gid)

            case .ceiling:
                let g = jsonSlab(node: node, predefinedType: "ROOF")
                entities.append(g.entity)
                storeyGids.append(g.gid)

            case .furniture, .object:
                let g = jsonFurnishing(node: node)
                entities.append(g.entity)
                storeyGids.append(g.gid)

            case .unknown:
                break
            }
        }

        // ── Relaciones de agregación ──────────────────────────────────────
        entities.append(relAggregates("ProjectToSite",    relating: projectGid,  related: [siteGid]))
        entities.append(relAggregates("SiteToBuilding",   relating: siteGid,     related: [buildingGid]))
        entities.append(relAggregates("BuildingToStorey", relating: buildingGid, related: [storeyGid]))

        if !storeyGids.isEmpty {
            entities.append(relContained(elements: storeyGids, structure: storeyGid))
        }

        return [
            "type":                "ifcJSON",
            "version":             "0.1",
            "schemaIdentifier":    "IFC4",
            "originatingSystem":   "mi-render iOS",
            "preprocessorVersion": "mi-render 1.0",
            "timeStamp":           ISO8601DateFormatter().string(from: Date()),
            "data":                entities
        ]
    }

    // MARK: ── Entidades de infraestructura ───────────────────────────────────

    private func unitAssignment(globalId: String) -> [String: Any] {
        ["type":      "IfcUnitAssignment",
         "globalId":  globalId,
         "units": [
            siUnit("LENGTHUNIT",    "METRE"),
            siUnit("AREAUNIT",      "SQUARE_METRE"),
            siUnit("VOLUMEUNIT",    "CUBIC_METRE"),
            siUnit("PLANEANGLEUNIT","RADIAN")
         ]
        ]
    }

    private func siUnit(_ unitType: String, _ name: String) -> [String: Any] {
        ["type": "IfcSIUnit", "unitType": unitType, "name": name]
    }

    private func geometricContext(globalId: String) -> [String: Any] {
        ["type":              "IfcGeometricRepresentationContext",
         "globalId":          globalId,
         "contextType":       "Model",
         "coordinateSpaceDimension": 3,
         "precision":         1.0e-5,
         "worldCoordinateSystem": ax2p3d(origin: [0, 0, 0]),
         "trueNorth":         dir2D(0, 1)
        ]
    }

    // MARK: ── Jerarquía espacial ─────────────────────────────────────────────

    private func ifcProject(globalId: String, name: String,
                             unitGid: String, ctxGid: String) -> [String: Any] {
        ["type":                     "IfcProject",
         "globalId":                 globalId,
         "name":                     name,
         "description":              "Exportado desde mi-render iOS",
         "unitsInContext":            ref(unitGid),
         "representationContexts":   [ref(ctxGid)]
        ]
    }

    private func ifcSite(globalId: String) -> [String: Any] {
        ["type":             "IfcSite",
         "globalId":         globalId,
         "name":             "Sitio",
         "compositionType":  "ELEMENT",
         "objectPlacement":  worldPlacement()
        ]
    }

    private func ifcBuilding(globalId: String, graph: SceneGraph) -> [String: Any] {
        let rooms  = graph.nodes.values.filter { $0.type == .room && $0.id != graph.rootId }
        let area   = rooms.reduce(0.0) {
            $0 + Double(($1.maxX - $1.minX) * ($1.maxZ - $1.minZ))
        }
        let vol    = rooms.reduce(0.0) {
            $0 + Double(($1.maxX - $1.minX) * ($1.maxY - $1.minY) * ($1.maxZ - $1.minZ))
        }
        return ["type":            "IfcBuilding",
                "globalId":        globalId,
                "name":            "Edificio",
                "compositionType": "ELEMENT",
                "objectPlacement": worldPlacement(),
                "description":     String(format: "Sup: %.2f m² | Vol: %.2f m³", area, vol)
               ]
    }

    private func ifcBuildingStorey(globalId: String) -> [String: Any] {
        ["type":             "IfcBuildingStorey",
         "globalId":         globalId,
         "name":             "Planta Baja",
         "elevation":        0.0,
         "compositionType":  "ELEMENT",
         "objectPlacement":  worldPlacement()
        ]
    }

    // MARK: ── Elementos del modelo ───────────────────────────────────────────

    private func jsonSpace(node: SceneNode) -> (gid: String, entity: [String: Any]) {
        let gid  = ifcGid(node.id)
        let size = node.boundingSize
        let ctr  = node.boundingCenter
        let area = Double(size.x * size.z)

        var props: [String: Any] = ["NetFloorArea": area, "Height": Double(size.y)]
        node.metadata.forEach { props[$0.key] = $0.value }

        let entity: [String: Any] = [
            "type":            "IfcSpace",
            "globalId":        gid,
            "name":            node.label.isEmpty ? "Habitación" : node.label,
            "predefinedType":  "INTERNAL",
            "objectPlacement": localPlacement(ifcPos: ifc(ctr), axisZ: [0,0,1], axisX: [1,0,0]),
            "representation":  extrudedBox(sizeX: Double(size.x), sizeZ: Double(size.z),
                                            height: Double(size.y)),
            "propertySet":     pset("Pset_SpaceCommon", props: props)
        ]
        return (gid, entity)
    }

    private func jsonWall(node: SceneNode) -> (gid: String, entity: [String: Any]) {
        let gid    = ifcGid(node.id)
        let length = max(Double(node.boundingSize.x), 0.01)
        let height = max(Double(node.boundingSize.y), 0.01)
        let thick  = max(Double(node.boundingSize.z), 0.05)

        var props: [String: Any] = ["Length": length, "Height": height,
                                    "Thickness": thick, "IsExternal": false]
        node.metadata.forEach { props[$0.key] = $0.value }

        let entity: [String: Any] = [
            "type":            "IfcWallStandardCase",
            "globalId":        gid,
            "name":            node.label.isEmpty ? "Pared" : node.label,
            "predefinedType":  "SOLIDWALL",
            "objectPlacement": localPlacement(ifcPos: ifc(node.position),
                                               axisZ: [0,0,1],
                                               axisX: ifcXAxis(node.transform)),
            "representation":  extrudedBox(sizeX: length, sizeZ: thick, height: height),
            "propertySet":     pset("Pset_WallCommon", props: props)
        ]
        return (gid, entity)
    }

    private func jsonDoor(node: SceneNode) -> (gid: String, entity: [String: Any]) {
        let gid    = ifcGid(node.id)
        let width  = max(Double(node.boundingSize.x), 0.8)
        let height = max(Double(node.boundingSize.y), 2.0)

        var props: [String: Any] = ["OverallWidth": width, "OverallHeight": height,
                                    "OperationType": "SINGLE_SWING_LEFT"]
        node.metadata.forEach { props[$0.key] = $0.value }

        let entity: [String: Any] = [
            "type":            "IfcDoor",
            "globalId":        gid,
            "name":            node.label.isEmpty ? "Puerta" : node.label,
            "predefinedType":  "DOOR",
            "overallHeight":   height,
            "overallWidth":    width,
            "objectPlacement": localPlacement(ifcPos: ifc(node.position),
                                               axisZ: [0,0,1],
                                               axisX: ifcXAxis(node.transform)),
            "representation":  extrudedBox(sizeX: width, sizeZ: 0.10, height: height),
            "propertySet":     pset("Pset_DoorCommon", props: props)
        ]
        return (gid, entity)
    }

    private func jsonWindow(node: SceneNode) -> (gid: String, entity: [String: Any]) {
        let gid    = ifcGid(node.id)
        let width  = max(Double(node.boundingSize.x), 0.6)
        let height = max(Double(node.boundingSize.y), 0.9)

        var props: [String: Any] = ["OverallWidth": width, "OverallHeight": height,
                                    "IsExternal": true]
        node.metadata.forEach { props[$0.key] = $0.value }

        let entity: [String: Any] = [
            "type":            "IfcWindow",
            "globalId":        gid,
            "name":            node.label.isEmpty ? "Ventana" : node.label,
            "predefinedType":  "WINDOW",
            "overallHeight":   height,
            "overallWidth":    width,
            "objectPlacement": localPlacement(ifcPos: ifc(node.position),
                                               axisZ: [0,0,1],
                                               axisX: ifcXAxis(node.transform)),
            "representation":  extrudedBox(sizeX: width, sizeZ: 0.08, height: height),
            "propertySet":     pset("Pset_WindowCommon", props: props)
        ]
        return (gid, entity)
    }

    private func jsonSlab(node: SceneNode,
                           predefinedType: String) -> (gid: String, entity: [String: Any]) {
        let gid    = ifcGid(node.id)
        let sizeX  = max(Double(node.boundingSize.x), 0.1)
        let sizeZ  = max(Double(node.boundingSize.z), 0.1)
        let thick  = max(Double(node.boundingSize.y), 0.15)
        let isExt  = predefinedType == "ROOF"

        let entity: [String: Any] = [
            "type":            "IfcSlab",
            "globalId":        gid,
            "name":            isExt ? "Techo" : "Suelo",
            "predefinedType":  predefinedType,
            "objectPlacement": localPlacement(ifcPos: ifc(node.position),
                                               axisZ: [0,0,1], axisX: [1,0,0]),
            "representation":  extrudedBox(sizeX: sizeX, sizeZ: sizeZ, height: thick),
            "propertySet":     pset("Pset_SlabCommon",
                                     props: ["LoadBearing": true, "IsExternal": isExt])
        ]
        return (gid, entity)
    }

    private func jsonFurnishing(node: SceneNode) -> (gid: String, entity: [String: Any]) {
        let gid    = ifcGid(node.id)
        let sizeX  = max(Double(node.boundingSize.x), 0.1)
        let sizeY  = max(Double(node.boundingSize.y), 0.1)
        let sizeZ  = max(Double(node.boundingSize.z), 0.1)

        var props: [String: Any] = ["Width": sizeX, "Height": sizeY, "Depth": sizeZ]
        node.metadata.forEach { props[$0.key] = $0.value }

        let entity: [String: Any] = [
            "type":            "IfcFurnishingElement",
            "globalId":        gid,
            "name":            node.label.isEmpty ? "Objeto" : node.label,
            "objectPlacement": localPlacement(ifcPos: ifc(node.position),
                                               axisZ: [0,0,1], axisX: [1,0,0]),
            "representation":  extrudedBox(sizeX: sizeX, sizeZ: sizeZ, height: sizeY),
            "propertySet":     pset("Pset_FurnitureTypeCommon", props: props)
        ]
        return (gid, entity)
    }

    // MARK: ── Relaciones ────────────────────────────────────────────────────

    private func relAggregates(_ name: String,
                                relating: String,
                                related: [String]) -> [String: Any] {
        ["type":           "IfcRelAggregates",
         "globalId":       ifcGid(),
         "name":           name,
         "relatingObject": ref(relating),
         "relatedObjects": related.map { ref($0) }
        ]
    }

    private func relContained(elements: [String], structure: String) -> [String: Any] {
        ["type":              "IfcRelContainedInSpatialStructure",
         "globalId":          ifcGid(),
         "name":              "ElementsInStorey",
         "relatedElements":   elements.map { ref($0) },
         "relatingStructure": ref(structure)
        ]
    }

    // MARK: ── Helpers de geometría JSON ────────────────────────────────────

    private func worldPlacement() -> [String: Any] {
        localPlacement(ifcPos: [0, 0, 0], axisZ: [0, 0, 1], axisX: [1, 0, 0])
    }

    private func localPlacement(ifcPos: [Double],
                                  axisZ: [Double],
                                  axisX: [Double]) -> [String: Any] {
        ["type": "IfcLocalPlacement",
         "relativePlacement": ax2p3d(origin: ifcPos, axisZ: axisZ, axisX: axisX)
        ]
    }

    private func ax2p3d(origin: [Double],
                         axisZ: [Double] = [0, 0, 1],
                         axisX: [Double] = [1, 0, 0]) -> [String: Any] {
        ["type":         "IfcAxis2Placement3D",
         "location":     cartPt3(origin[0], origin[1], origin[2]),
         "axis":         dir3D(axisZ[0], axisZ[1], axisZ[2]),
         "refDirection": dir3D(axisX[0], axisX[1], axisX[2])
        ]
    }

    private func extrudedBox(sizeX: Double, sizeZ: Double, height: Double) -> [String: Any] {
        ["type": "IfcProductDefinitionShape",
         "representations": [[
            "type":                     "IfcShapeRepresentation",
            "representationIdentifier": "Body",
            "representationType":       "SweptSolid",
            "items": [[
                "type":     "IfcExtrudedAreaSolid",
                "sweptArea": [
                    "type":        "IfcRectangleProfileDef",
                    "profileType": "AREA",
                    "xDim":        sizeX,
                    "yDim":        sizeZ
                ],
                "position": ax2p3d(origin: [0, 0, 0]),
                "extrudedDirection": dir3D(0, 0, 1),
                "depth": height
            ]]
         ]]
        ]
    }

    private func pset(_ name: String, props: [String: Any]) -> [String: Any] {
        ["type":           "IfcPropertySet",
         "globalId":       ifcGid(),
         "name":           name,
         "hasProperties":  props.map { k, v in
            ["type":  "IfcPropertySingleValue",
             "name":  k,
             "nominalValue": ["type": ifcValueTypeName(v), "wrappedValue": v]
            ]
         }
        ]
    }

    private func cartPt3(_ x: Double, _ y: Double, _ z: Double) -> [String: Any] {
        ["type": "IfcCartesianPoint", "coordinates": [x, y, z]]
    }
    private func dir3D(_ x: Double, _ y: Double, _ z: Double) -> [String: Any] {
        ["type": "IfcDirection", "directionRatios": [x, y, z]]
    }
    private func dir2D(_ x: Double, _ y: Double) -> [String: Any] {
        ["type": "IfcDirection", "directionRatios": [x, y]]
    }
    private func ref(_ gid: String) -> [String: Any] {
        ["type": "ref", "value": gid]
    }
    private func ifcValueTypeName(_ v: Any) -> String {
        switch v {
        case is Double, is Float: return "IfcLengthMeasure"
        case is Int:              return "IfcInteger"
        case is Bool:             return "IfcBoolean"
        default:                  return "IfcLabel"
        }
    }

    // MARK: ── Conversión de coordenadas ARKit → IFC ─────────────────────────

    // ARKit (Y-up, Z-toward-cam) → IFC (Z-up, Y-into-scene)
    private func ifc(_ v: SIMD3<Float>) -> [Double] {
        [Double(v.x), Double(-v.z), Double(v.y)]
    }

    private func ifcXAxis(_ t: simd_float4x4) -> [Double] {
        let c = t.columns.0
        return [Double(c.x), Double(-c.z), Double(c.y)]
    }

    // MARK: ── GlobalId IFC (base-64 comprimido desde UUID) ─────────────────

    /// Genera un IFC GlobalId de 22 caracteres (codificación base-64 IFC).
    private func ifcGid(_ uuid: UUID = UUID()) -> String {
        let alpha = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$")
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: uuid.uuid) { ptr in
            for i in 0..<16 { bytes[i] = ptr[i] }
        }
        var result = [Character]()
        var acc: UInt64 = 0
        var bits = 0
        for byte in bytes {
            acc   = (acc << 8) | UInt64(byte)
            bits += 8
            while bits >= 6 {
                bits -= 6
                result.append(alpha[Int((acc >> bits) & 0x3F)])
            }
        }
        if bits > 0 { result.append(alpha[Int((acc << (6 - bits)) & 0x3F)]) }
        return String(result.prefix(22))
    }

    // MARK: ── Escritura JSON en disco ────────────────────────────────────────

    private func writeJSON(_ doc: [String: Any],
                            projectId: UUID,
                            completion: @escaping (Result<URL, Error>) -> Void) {
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
        let url = dir.appendingPathComponent("model.ifc.json")

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: doc,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: url, options: .atomic)
            let count = (doc["data"] as? [[String: Any]])?.count ?? 0
            print("[IFCExporter] model.ifc.json → \(data.count / 1024) KB, \(count) entidades")
            DispatchQueue.main.async { completion(.success(url)) }
        } catch {
            print("[IFCExporter] writeJSON error: \(error)")
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    // MARK: ══════════════════════════════════════════════════════════════════
    // MARK: Constructor STEP (IFC2X3)

    @available(iOS 16.0, *)
    private func buildSTEP(room: CapturedRoom,
                            segments: [RoomSegment],
                            projectName: String,
                            name: String) -> String {

        let b = IFCBuilder()

        let personId = b.add("IFCPERSON($,'mi-render',$,$,$,$,$,$)")
        let orgId    = b.add("IFCORGANIZATION($,'Zerbitecni',$,$,$)")
        let poId     = b.add("IFCPERSONANDORGANIZATION(#\(personId),#\(orgId),$)")
        let appId    = b.add("IFCAPPLICATION(#\(orgId),'1.0','mi-render','mi-render')")
        let ohId     = b.add("IFCOWNERHISTORY(#\(poId),#\(appId),$,.NOTDEFINED.,$,$,$,0)")

        let uLen  = b.add("IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.)")
        let uArea = b.add("IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.)")
        let uVol  = b.add("IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.)")
        let uAng  = b.add("IFCSIUNIT(*,.PLANEANGLEUNIT.,$,.RADIAN.)")
        let uAsgn = b.add("IFCUNITASSIGNMENT((#\(uLen),#\(uArea),#\(uVol),#\(uAng)))")

        let worldPt   = b.pt3(0, 0, 0)
        let worldAx   = b.ax3d(worldPt)
        let geoCtxId  = b.add("IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.E-05,#\(worldAx),$)")
        let bodyCtxId = b.add("IFCGEOMETRICREPRESENTATIONSUBCONTEXT('Body','Model',*,*,*,*,#\(geoCtxId),$,.MODEL_VIEW.,$)")

        let projId   = b.add("IFCPROJECT('\(b.guid(1))',#\(ohId),'\(projectName)',$,$,$,$,(#\(geoCtxId)),#\(uAsgn))")
        let sitePlac = b.localPlac(rel: nil, ax: worldAx)
        let siteId   = b.add("IFCSITE('\(b.guid(2))',#\(ohId),'Sitio',$,$,#\(sitePlac),$,$,.ELEMENT.,$,$,$,$,$)")
        let bldPlac  = b.localPlac(rel: sitePlac, ax: worldAx)
        let bldId    = b.add("IFCBUILDING('\(b.guid(3))',#\(ohId),'Edificio',$,$,#\(bldPlac),$,$,.ELEMENT.,$,$,$)")
        let stPlac   = b.localPlac(rel: bldPlac, ax: worldAx)
        let storeyId = b.add("IFCBUILDINGSTOREY('\(b.guid(4))',#\(ohId),'Planta Baja',$,$,#\(stPlac),$,$,.ELEMENT.,0.)")

        let ra1 = b.add("IFCRELAGGREGATES('\(b.guid(10))',#\(ohId),$,$,#\(projId),(#\(siteId)))")
        let ra2 = b.add("IFCRELAGGREGATES('\(b.guid(11))',#\(ohId),$,$,#\(siteId),(#\(bldId)))")
        let ra3 = b.add("IFCRELAGGREGATES('\(b.guid(12))',#\(ohId),$,$,#\(bldId),(#\(storeyId)))")
        _ = (ra1, ra2, ra3)

        var contained = [Int]()
        let zUp = b.dir3(0, 0, 1)

        // Espacios
        if !segments.isEmpty {
            for (i, seg) in segments.enumerated() {
                let h  = max(0.5, seg.avgHeight > 0.1 ? seg.avgHeight : 2.4)
                let bw = seg.bboxMax.x - seg.bboxMin.x
                let bd = seg.bboxMax.y - seg.bboxMin.y
                let spt  = b.pt3(seg.centroid.x, 0, -seg.centroid.y)
                let sax  = b.ax3d(spt, axis: zUp)
                let splc = b.localPlac(rel: stPlac, ax: sax)
                let pOrig = b.pt2(-bw/2, -bd/2)
                let prof  = b.rectProfile(origin2d: pOrig, w: bw, h: bd)
                let extAx = b.ax3d(b.pt3(0, 0, 0))
                let solid = b.extrude(profileId: prof, placAx: extAx, dirId: zUp, depth: h)
                let srep  = b.shapeRep(ctxId: bodyCtxId, solidId: solid)
                let pdef  = b.prodDef(repId: srep)
                let spId  = b.add("IFCSPACE('\(b.guid(100+i))',#\(ohId),'\(seg.label)',$,'Espacio \(i+1)',#\(splc),#\(pdef),$,.ELEMENT.,.INTERNAL.,0.)")
                contained.append(spId)
            }
        } else {
            let spt  = b.pt3(0, 0, 0)
            let sax  = b.ax3d(spt, axis: zUp)
            let splc = b.localPlac(rel: stPlac, ax: sax)
            let spId = b.add("IFCSPACE('\(b.guid(100))',#\(ohId),'Habitacion',$,'Espacio',#\(splc),$,$,.ELEMENT.,.INTERNAL.,0.)")
            contained.append(spId)
        }

        // Paredes
        for (i, wall) in room.walls.enumerated() {
            let t  = wall.transform
            let wL = wall.dimensions.x; let wH = wall.dimensions.y
            let wT = max(0.05, wall.dimensions.z)
            let cx = t.columns.3.x; let cy = t.columns.3.y; let cz = -t.columns.3.z
            let lx = t.columns.0.x; let ly = -t.columns.0.z
            let wpt  = b.pt3(cx, cz, cy)
            let xRef = b.dir3(lx, ly, 0)
            let wax  = b.ax3d(wpt, axis: zUp, refDir: xRef)
            let wplc = b.localPlac(rel: stPlac, ax: wax)
            let pOrig = b.pt2(-wL/2, -wT/2)
            let prof  = b.rectProfile(origin2d: pOrig, w: wL, h: wT)
            let extAx = b.ax3d(b.pt3(0, 0, 0))
            let solid = b.extrude(profileId: prof, placAx: extAx, dirId: zUp, depth: wH)
            let srep  = b.shapeRep(ctxId: bodyCtxId, solidId: solid)
            let pdef  = b.prodDef(repId: srep)
            let wId   = b.add("IFCWALLSTANDARDCASE('\(b.guid(200+i))',#\(ohId),'Pared \(i+1)',$,'Muro',#\(wplc),#\(pdef),$)")
            contained.append(wId)
        }

        // Puertas
        for (i, door) in room.doors.enumerated() {
            let t    = door.transform
            let dpt  = b.pt3(t.columns.3.x, -t.columns.3.z, t.columns.3.y)
            let dax  = b.ax3d(dpt, axis: zUp)
            let dplc = b.localPlac(rel: stPlac, ax: dax)
            let W = door.dimensions.x; let H = door.dimensions.y
            let dId = b.add("IFCDOOR('\(b.guid(300+i))',#\(ohId),'Puerta \(i+1)',$,'Puerta',#\(dplc),$,$,\(b.f(H)),\(b.f(W)))")
            contained.append(dId)
        }

        // Ventanas
        for (i, win) in room.windows.enumerated() {
            let t    = win.transform
            let wpt  = b.pt3(t.columns.3.x, -t.columns.3.z, t.columns.3.y)
            let wax  = b.ax3d(wpt, axis: zUp)
            let wplc = b.localPlac(rel: stPlac, ax: wax)
            let W = win.dimensions.x; let H = win.dimensions.y
            let wiId = b.add("IFCWINDOW('\(b.guid(400+i))',#\(ohId),'Ventana \(i+1)',$,'Ventana',#\(wplc),$,$,\(b.f(H)),\(b.f(W)))")
            contained.append(wiId)
        }

        if !contained.isEmpty {
            let items = contained.map { "#\($0)" }.joined(separator: ",")
            b.add("IFCRELCONTAINEDINSPATIALSTRUCTURE('\(b.guid(500))',#\(ohId),$,$,(\(items)),#\(storeyId))")
        }

        let dateStr = ISO8601DateFormatter().string(from: Date())
        var out  = "ISO-10303-21;\nHEADER;\n"
        out     += "FILE_DESCRIPTION(('IFC2X3 ViewDefinition [CoordinationView]'),'2;1');\n"
        out     += "FILE_NAME('\(name).ifc','\(dateStr)',(''),'','mi-render 1.0','','');\n"
        out     += "FILE_SCHEMA(('IFC2X3'));\nENDSEC;\n\nDATA;\n"
        for entry in b.lines.sorted(by: { $0.id < $1.id }) {
            out += "#\(entry.id)=\(entry.body);\n"
        }
        out += "ENDSEC;\nEND-ISO-10303-21;\n"
        return out
    }
}

// MARK: - Errores

enum IFCError: LocalizedError {
    case noSceneGraph
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noSceneGraph:   return "No se pudo cargar el SceneGraph del proyecto"
        case .encodingFailed: return "Error al codificar el documento IFC JSON"
        }
    }
}
