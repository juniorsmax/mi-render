import Foundation
import Capacitor
import ARKit
import RealityKit
import RoomPlan
import CoreLocation
import AVFoundation

/**
 * LiDARPlugin — RoomPlan + ARKit para mi-render
 *
 * Métodos:
 *  isAvailable     → capacidades del dispositivo
 *  startScan       → escaneo de habitación con RoomPlan (iOS 16+)
 *  startObjectScan → escaneo 3D de objeto con ARKit .mesh
 *  stopScan        → para cualquier escaneo en curso
 *  exportUSDZ      → exporta último escaneo como USDZ
 *  saveWorldMap    → persiste ARWorldMap con nombre
 *  measureDistance → distancia entre dos puntos 3D
 *  exportOBJ       → exporta malla como OBJ
 *  exportPLY       → exporta malla como PLY
 *  exportSTL       → exporta malla como STL
 */
@objc(LiDARPlugin)
public class LiDARPlugin: CAPPlugin, CLLocationManagerDelegate {

    private var pendingCall: CAPPluginCall?
    private var locationManager: CLLocationManager?
    private var lastLocation: CLLocation?

    // ── isAvailable ──────────────────────────────────────────────────────────
    @objc func isAvailable(_ call: CAPPluginCall) {
        let hasARKit = ARWorldTrackingConfiguration.isSupported
        let hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

        if #available(iOS 16.0, *) {
            call.resolve([
                "available":  hasLiDAR,
                "lidar":      hasLiDAR,
                "roomPlan":   hasLiDAR,
                "arKit":      hasARKit,
                "objectScan": hasLiDAR,
                "scanMode":   hasLiDAR ? "roomplan" : "arkit",
                "iosVersion": UIDevice.current.systemVersion,
            ])
        } else {
            call.resolve([
                "available":  false,
                "lidar":      false,
                "roomPlan":   false,
                "arKit":      hasARKit,
                "objectScan": false,
                "scanMode":   "unsupported",
                "iosVersion": UIDevice.current.systemVersion,
            ])
        }
    }

    // ── startScan (RoomPlan) ─────────────────────────────────────────────────
    @objc func startScan(_ call: CAPPluginCall) {
        guard #available(iOS 16.0, *) else {
            call.reject("RoomPlan requiere iOS 16 o superior")
            return
        }
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            call.reject("Este dispositivo no tiene sensor LiDAR. Se requiere iPhone 12 Pro o superior.")
            return
        }

        requestLocation()
        pendingCall = call

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let vc = RoomPlanViewController()
            vc.onResult = { [weak self] result in
                guard let self = self else { return }
                if var result = result {
                    if let loc = self.lastLocation {
                        result["latitude"]  = loc.coordinate.latitude
                        result["longitude"] = loc.coordinate.longitude
                        result["altitude"]  = loc.altitude
                    }
                    self.pendingCall?.resolve(result)
                } else {
                    self.pendingCall?.reject("Escaneo cancelado")
                }
                self.pendingCall = nil
                self.locationManager?.stopUpdatingLocation()
            }
            vc.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(vc, animated: true)
        }
    }

    // ── startObjectScan (ARKit .mesh) ────────────────────────────────────────
    @objc func startObjectScan(_ call: CAPPluginCall) {
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            call.reject("Este dispositivo no tiene sensor LiDAR para escaneo de objetos.")
            return
        }

        pendingCall = call

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let vc = ObjectScanViewController()
            vc.onResult = { [weak self] result in
                if let result = result {
                    self?.pendingCall?.resolve(result)
                } else {
                    self?.pendingCall?.reject("Escaneo de objeto cancelado")
                }
                self?.pendingCall = nil
            }
            vc.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(vc, animated: true)
        }
    }

    // ── startPhotogrammetry (Object Capture API, iOS 17+) ───────────────────
    @objc func startPhotogrammetry(_ call: CAPPluginCall) {
        guard #available(iOS 17.0, *) else {
            call.reject("La fotogrametría on-device requiere iOS 17 o superior")
            return
        }
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            call.reject("No se encontró cámara trasera")
            return
        }

        pendingCall = call

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if #available(iOS 17.0, *) {
                let vc = PhotogrammetryViewController()
                vc.onResult = { [weak self] result in
                    guard let self = self else { return }
                    if let result = result, result["error"] == nil {
                        self.pendingCall?.resolve(result)
                    } else if let err = result?["error"] as? String {
                        self.pendingCall?.reject(err)
                    } else {
                        self.pendingCall?.reject("Fotogrametría cancelada")
                    }
                    self.pendingCall = nil
                }
                vc.modalPresentationStyle = .fullScreen
                self.bridge?.viewController?.present(vc, animated: true)
            }
        }
    }

    // ── startWalkthrough (recorrido interior SceneKit) ───────────────────────
    @objc func startWalkthrough(_ call: CAPPluginCall) {
        guard let path = call.getString("path"), !path.isEmpty else {
            call.reject("Se requiere la ruta del modelo USDZ")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let vc = WalkthroughViewController()
            vc.usdzPath = path
            vc.modalPresentationStyle = .fullScreen
            vc.modalTransitionStyle   = .crossDissolve
            self.bridge?.viewController?.present(vc, animated: true) {
                call.resolve(["opened": true])
            }
        }
    }

    // ── stopScan ─────────────────────────────────────────────────────────────
    @objc func stopScan(_ call: CAPPluginCall) {
        ScanManager.shared.stopScan()
        DispatchQueue.main.async {
            self.bridge?.viewController?.presentedViewController?.dismiss(animated: true)
        }
        pendingCall?.reject("Escaneo detenido")
        pendingCall = nil
        call.resolve(["stopped": true])
    }

    // ── exportUSDZ ───────────────────────────────────────────────────────────
    @objc func exportUSDZ(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }

            // Intentar exportar desde RoomPlanManager si hay sala capturada (iOS 16+)
            if #available(iOS 16.0, *),
               let room = RoomPlanManager.shared.lastCapturedRoom,
               let url = ExportManager.shared.exportUSDZ(room: room, named: "mi-render-scan") {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path])
                return
            }

            // Fallback: buscar USDZ en directorio temporal (flujo ObjectScan)
            let tmpUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent("mi-render-scan.usdz")
            if FileManager.default.fileExists(atPath: tmpUrl.path) {
                ExportManager.shared.shareFile(at: tmpUrl, from: vc)
                call.resolve(["path": tmpUrl.path])
            } else {
                call.reject("No hay escaneo guardado para exportar")
            }
        }
    }

    // ── saveWorldMap ─────────────────────────────────────────────────────────
    @objc func saveWorldMap(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "worldmap-\(Int(Date().timeIntervalSince1970))"

        guard let session = ScanManager.shared.session else {
            call.reject("No hay sesión AR activa para guardar")
            return
        }

        WorldMapManager.shared.saveWorldMap(session: session, named: name) { result in
            switch result {
            case .success(let url):
                call.resolve(["saved": true, "path": url.path, "name": name])
            case .failure(let error):
                call.reject("Error guardando mapa: \(error.localizedDescription)")
            }
        }
    }

    // ── measureDistance ──────────────────────────────────────────────────────
    @objc func measureDistance(_ call: CAPPluginCall) {
        guard
            let aDict = call.getObject("pointA"),
            let bDict = call.getObject("pointB"),
            let ax = aDict["x"] as? Double,
            let ay = aDict["y"] as? Double,
            let az = aDict["z"] as? Double,
            let bx = bDict["x"] as? Double,
            let by = bDict["y"] as? Double,
            let bz = bDict["z"] as? Double
        else {
            call.reject("Se requieren pointA y pointB con propiedades x, y, z")
            return
        }

        let pointA = SIMD3<Float>(Float(ax), Float(ay), Float(az))
        let pointB = SIMD3<Float>(Float(bx), Float(by), Float(bz))

        let distance = MeasurementManager.shared.measureDistance(from: pointA, to: pointB)
        let formatted = MeasurementManager.shared.formattedDistance(from: pointA, to: pointB)

        call.resolve([
            "distanceM":  Double(distance),
            "formatted":  formatted,
        ])
    }

    // ── getSurfaceAreas — expone cálculo ARKit a JS ──────────────────────────
    @objc func getSurfaceAreas(_ call: CAPPluginCall) {
        let s = MeshManager.shared.surfaces
        call.resolve(s.toDictionary())
    }

    // ── getWallMetrics — áreas de pared por plano ────────────────────────────
    @objc func getWallMetrics(_ call: CAPPluginCall) {
        MeasurementManager.shared.calculateWallAreas()
        MeasurementManager.shared.onWallsCalculated = { walls in
            let dicts = walls.map { $0.toDictionary() }
            let total = walls.reduce(0.0) { $0 + $1.area }
            call.resolve([
                "walls":      dicts,
                "wallCount":  walls.count,
                "totalWallArea": Double((total * 100).rounded() / 100),
            ])
            // limpiar callback para no acumular retención
            MeasurementManager.shared.onWallsCalculated = nil
        }
    }

    // ── getFloorFootprint — proyección 2D del suelo → convex hull ────────────
    @objc func getFloorFootprint(_ call: CAPPluginCall) {
        let epsilon = call.getFloat("simplifyEpsilon") ?? 0.05

        DispatchQueue.global(qos: .userInitiated).async {
            if let footprint = FloorFootprintBuilder.build(simplifyEpsilon: epsilon) {
                call.resolve(footprint.toDictionary())
            } else {
                // Si todavía no hay mesh de suelo, devolvemos vacío sin rechazar
                call.resolve([
                    "polygon":    [[String: Any]](),
                    "area":       0.0,
                    "width":      0.0,
                    "depth":      0.0,
                    "minX":       0.0, "minZ": 0.0,
                    "maxX":       0.0, "maxZ": 0.0,
                    "pointCount": 0,
                ])
            }
        }
    }

    // ── renderFloorPlan — genera UIImage del plano y devuelve base64 ─────────
    @available(iOS 16.0, *)
    @objc func renderFloorPlan(_ call: CAPPluginCall) {
        let width  = CGFloat(call.getFloat("width")  ?? 800)
        let height = CGFloat(call.getFloat("height") ?? 800)

        DispatchQueue.main.async {
            if #available(iOS 16.0, *) {
                let image = RoomPlanManager.shared.renderFloorPlan(
                    size: CGSize(width: width, height: height)
                )
                guard let data = image.pngData() else {
                    call.reject("No se pudo generar la imagen del plano")
                    return
                }
                let base64 = data.base64EncodedString()
                call.resolve(["image": "data:image/png;base64,\(base64)"])
            } else {
                call.reject("iOS 16+ requerido para renderFloorPlan")
            }
        }
    }

    // ── getRoomSegmentation — detecta habitaciones múltiples ─────────────────
    @objc func getRoomSegmentation(_ call: CAPPluginCall) {
        let cellSize   = call.getFloat("cellSize")   ?? 0.20
        let minAreaM2  = call.getFloat("minAreaM2")  ?? 0.8

        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Segmentar
            var segs = RoomSegmentationManager.shared.segmentRooms(
                cellSize: cellSize, minAreaM2: minAreaM2
            )
            // 2. Enriquecer con altura/volumen
            segs = VolumeCalculator.shared.enrichAll(segs)

            let dicts    = segs.map { $0.toDictionary() }
            let total    = segs.reduce(Float(0)) { $0 + $1.volume }
            let totalArea = segs.reduce(Float(0)) { $0 + $1.area }

            call.resolve([
                "rooms":         dicts,
                "roomCount":     segs.count,
                "totalArea":     Double(totalArea),
                "totalVolume":   Double(total),
            ])
        }
    }

    // ── getAutoVolume — volumen automático desde mesh + footprint ─────────────
    @objc func getAutoVolume(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Reutiliza segmentos si ya existen, si no los calcula
            var segs = RoomSegmentationManager.shared.segments
            if segs.isEmpty {
                segs = RoomSegmentationManager.shared.segmentRooms()
            }
            segs = VolumeCalculator.shared.enrichAll(segs)
            let totalVol = VolumeCalculator.shared.totalVolume()

            let volumes = segs.map { s in
                [
                    "roomId":    s.id,
                    "label":     s.label,
                    "floorArea": Double(s.area),
                    "avgHeight": Double(s.avgHeight),
                    "volume":    Double(s.volume),
                ] as [String: Any]
            }

            call.resolve([
                "volumes":      volumes,
                "totalVolume":  Double(totalVol),
                "roomCount":    segs.count,
            ])
        }
    }

    // ── exportIFC — exportación BIM IFC 2x3 ──────────────────────────────────
    @objc func exportIFC(_ call: CAPPluginCall) {
        guard #available(iOS 16.0, *) else {
            call.reject("IFC export requiere iOS 16+")
            return
        }
        guard let room = RoomPlanManager.shared.lastCapturedRoom else {
            call.reject("No hay habitación escaneada para exportar como IFC")
            return
        }

        let name    = call.getString("name")        ?? "mi-render-bim"
        let project = call.getString("projectName") ?? "mi-render"

        DispatchQueue.global(qos: .userInitiated).async {
            var segs = RoomSegmentationManager.shared.segments
            if segs.isEmpty {
                segs = RoomSegmentationManager.shared.segmentRooms()
            }
            segs = VolumeCalculator.shared.enrichAll(segs)

            if let url = IFCExporter.shared.exportIFC(
                from: room,
                segments: segs,
                projectName: project,
                named: name
            ) {
                DispatchQueue.main.async {
                    guard let vc = self.bridge?.viewController else {
                        call.resolve(["path": url.path])
                        return
                    }
                    ExportManager.shared.shareFile(at: url, from: vc)
                    call.resolve(["path": url.path, "format": "ifc"])
                }
            } else {
                call.reject("Error generando archivo IFC")
            }
        }
    }

    // ── exportOptimizedUSDZ — USDZ con materiales PBR por clasificación ───────
    @objc func exportOptimizedUSDZ(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"

        DispatchQueue.global(qos: .userInitiated).async {
            if let url = ExportManager.shared.exportOptimizedUSDZ(named: name) {
                DispatchQueue.main.async {
                    guard let vc = self.bridge?.viewController else {
                        call.resolve(["path": url.path])
                        return
                    }
                    ExportManager.shared.shareFile(at: url, from: vc)
                    call.resolve(["path": url.path, "format": "usdz"])
                }
            } else {
                call.reject("No hay malla capturada para exportar USDZ optimizado")
            }
        }
    }

    // ── exportOBJ ────────────────────────────────────────────────────────────
    @objc func exportOBJ(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"
        let meshes = MeshManager.shared.getAllMeshes()

        guard !meshes.isEmpty else {
            call.reject("No hay malla 3D capturada para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportAsset(asset, format: .obj, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "obj"])
            } else {
                call.reject("Error exportando OBJ")
            }
        }
    }

    // ── exportPLY ────────────────────────────────────────────────────────────
    @objc func exportPLY(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"
        let meshes = MeshManager.shared.getAllMeshes()

        guard !meshes.isEmpty else {
            call.reject("No hay malla 3D capturada para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportAsset(asset, format: .ply, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "ply"])
            } else {
                call.reject("Error exportando PLY")
            }
        }
    }

    // ── exportSTL ────────────────────────────────────────────────────────────
    @objc func exportSTL(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"
        let meshes = MeshManager.shared.getAllMeshes()

        guard !meshes.isEmpty else {
            call.reject("No hay malla 3D capturada para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportAsset(asset, format: .stl, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "stl"])
            } else {
                call.reject("Error exportando STL")
            }
        }
    }

    // ── exportDAE ────────────────────────────────────────────────────────────
    @objc func exportDAE(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"
        let meshes = MeshManager.shared.getAllMeshes()

        guard !meshes.isEmpty else {
            call.reject("No hay malla 3D capturada para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportDAE(asset: asset, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "dae"])
            } else {
                call.reject("Error exportando DAE")
            }
        }
    }

    // ── exportSVG ────────────────────────────────────────────────────────────
    @available(iOS 16.0, *)
    @objc func exportSVG(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-plan"

        guard let room = RoomPlanManager.shared.lastCapturedRoom else {
            call.reject("No hay escaneo de habitación disponible para SVG")
            return
        }

        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportSVG(from: room.walls, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "svg"])
            } else {
                call.reject("Error exportando SVG")
            }
        }
    }

    // ── exportPDF ────────────────────────────────────────────────────────────
    @available(iOS 16.0, *)
    @objc func exportPDF(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-plan"

        guard let room = RoomPlanManager.shared.lastCapturedRoom else {
            call.reject("No hay escaneo de habitación disponible para PDF")
            return
        }

        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportPDF(from: room.walls, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "pdf"])
            } else {
                call.reject("Error exportando PDF")
            }
        }
    }

    // ── exportDXF ────────────────────────────────────────────────────────────
    @available(iOS 16.0, *)
    @objc func exportDXF(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-plan"

        guard let room = RoomPlanManager.shared.lastCapturedRoom else {
            call.reject("No hay escaneo de habitación disponible para DXF")
            return
        }

        // Obtener footprint en background (puede tardar si aún no se calculó)
        DispatchQueue.global(qos: .userInitiated).async {
            let footprint = RoomPlanManager.shared.floorFootprint
                ?? FloorFootprintBuilder.build(simplifyEpsilon: 0.05)

            DispatchQueue.main.async {
                guard let vc = self.bridge?.viewController else {
                    call.reject("No se encontró viewController")
                    return
                }
                if let url = ExportManager.shared.generateDXF(from: room,
                                                               footprint: footprint,
                                                               named: name) {
                    ExportManager.shared.shareFile(at: url, from: vc)
                    call.resolve([
                        "path":    url.path,
                        "format":  "dxf",
                        "walls":   room.walls.count,
                        "doors":   room.doors.count,
                        "windows": room.windows.count,
                        "hasFootprint": footprint != nil,
                    ])
                } else {
                    call.reject("Error exportando DXF")
                }
            }
        }
    }

    // ── exportGLTF ───────────────────────────────────────────────────────────
    @objc func exportGLTF(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"
        let meshes = MeshManager.shared.getAllMeshes()

        guard !meshes.isEmpty else {
            call.reject("No hay malla 3D capturada para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportGLTF(asset: asset, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "gltf"])
            } else {
                call.reject("Error exportando GLTF")
            }
        }
    }

    // ── exportGLB ────────────────────────────────────────────────────────────
    @objc func exportGLB(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"
        let meshes = MeshManager.shared.getAllMeshes()

        guard !meshes.isEmpty else {
            call.reject("No hay malla 3D capturada para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        DispatchQueue.main.async {
            guard let vc = self.bridge?.viewController else {
                call.reject("No se encontró viewController")
                return
            }
            if let url = ExportManager.shared.exportGLB(asset: asset, named: name) {
                ExportManager.shared.shareFile(at: url, from: vc)
                call.resolve(["path": url.path, "format": "glb"])
            } else {
                call.reject("Error exportando GLB")
            }
        }
    }

    // ── exportAllFormats ─────────────────────────────────────────────────────
    @available(iOS 16.0, *)
    @objc func exportAllFormats(_ call: CAPPluginCall) {
        let name   = call.getString("name") ?? "mi-render-export"
        let meshes = MeshManager.shared.getAllMeshes()
        let room   = RoomPlanManager.shared.lastCapturedRoom

        guard !meshes.isEmpty || room != nil else {
            call.reject("No hay datos escaneados para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        ExportManager.shared.exportAllFormats(asset: asset, room: room, named: name)

        let exports = ExportManager.shared.listExports()
            .filter { $0.lastPathComponent.hasPrefix(name) }
            .map { ["path": $0.path, "format": $0.pathExtension] }

        call.resolve(["files": exports, "count": exports.count])
    }

    // ── GPS ──────────────────────────────────────────────────────────────────
    private func requestLocation() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.requestWhenInUseAuthorization()
        locationManager?.startUpdatingLocation()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
}

// ── RoomPlan ViewController — Guided scanning UI (iOS 16+) ───────────────────
//
// Usa RoomCaptureView como capa de cámara + malla de Apple.
// ScanGuidanceOverlay cubre toda la pantalla con la UI de guía:
//   - Anillo de progreso animado (NavigationManager.calculateScanProgress)
//   - Mensaje de guía contextual (zonas faltantes, dirección a mover)
//   - Badges de superficies detectadas en tiempo real
//   - Miniatura del plano planta actualizada cada ~4.5 s
//
@available(iOS 16.0, *)
class RoomPlanViewController: UIViewController {

    var onResult: (([String: Any]?) -> Void)?

    private var captureView:    RoomCaptureView!
    private var captureSession: RoomCaptureSession!
    private var overlay:        ScanGuidanceOverlay!
    private var meshOverlayView: ARView?
    private var isPaused        = false
    private var torchOn         = false
    private var uiReady         = false
    private var meshTimer:      Timer?
    private var meshTickCount   = 0
    private var meshTimerInterval: TimeInterval = 1.5   // se reduce en thermal serious
    private var lastProgress:   Float = 0               // para no regresionar
    private var pausedBySystem  = false                 // distinción entre pausa manual y sistema

    // Conteo en vivo de RoomPlan
    private var liveDoors   = 0
    private var liveWindows = 0

    // Métricas en tiempo real — actualizadas en el timer
    private var liveVolume:    Float = 0
    private var liveHeight:    Float = 0
    private var livePerimeter: Float = 0

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)

        captureSession          = captureView.captureSession
        captureSession.delegate = self

        // ARView transparente sobre RoomCaptureView para renderizar la malla LiDAR con colores
        // semánticos. Comparte el ARSession de RoomPlan — ScanManager actúa como delegate.
        let meshView = ARView(frame: view.bounds)
        meshView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        meshView.isUserInteractionEnabled = false
        meshView.environment.background = .color(.clear)   // sin camera feed propio
        meshView.session = captureSession.arSession        // compartir sesión
        view.insertSubview(meshView, aboveSubview: captureView)
        meshOverlayView = meshView

        // ScanManager recibe callbacks de ARSession y renderiza la malla en meshView
        ScanManager.shared.arView   = meshView
        ScanManager.shared.session  = captureSession.arSession
        captureSession.arSession.delegate = ScanManager.shared

        MeshManager.shared.onSurfacesUpdated = { [weak self] surfaces in
            guard let self = self else { return }
            self.overlay?.updateSurfaces(surfaces, doors: self.liveDoors, windows: self.liveWindows)
            // Propagar volumen estimado (altura puede no estar calculada aún → usar liveHeight o fallback)
            let vol = surfaces.floor * max(self.liveHeight > 0.1 ? self.liveHeight : 2.4, 0.5)
            self.liveVolume = vol
            self.overlay?.updateLiveMetrics(volume: vol,
                                            height: self.liveHeight,
                                            perimeter: self.livePerimeter)
        }

        MeasurementManager.shared.onWallsCalculated = { [weak self] _ in
            self?.refreshProgress()
        }

        UIStateManager.shared.switchMode(.scanning)
        startStabilityMonitoring()
        registerLifecycleNotifications()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !uiReady else { return }
        uiReady = true
        buildGuidanceOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        captureSession.run(configuration: RoomCaptureSession.Configuration())
        startMeshTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        setTorch(false)
        stopMeshTimer()
        captureSession.stop()
        ThermalBatteryManager.shared.stopMonitoring()
        ScanQualityManager.shared.reset()
        removeLifecycleNotifications()
        UIStateManager.shared.reset()
        // Limpiar entidades del overlay y desconectar ScanManager
        ScanManager.shared.clearMeshEntities()
        ScanManager.shared.arView   = nil
        ScanManager.shared.session  = nil
        meshOverlayView?.removeFromSuperview()
        meshOverlayView = nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Reducir anchors para liberar memoria — mantiene los 30 más recientes
        MeshManager.shared.removeOldAnchors(session: captureSession.arSession, keepLast: 30)
        showGuidanceWarning("Memoria alta — reduciendo detalle del mesh")
    }

    // MARK: – Estabilidad: monitoreo térmico, batería y calidad ARKit

    private func startStabilityMonitoring() {
        ThermalBatteryManager.shared.startMonitoring()

        // Temperatura seria → duplicar intervalo del timer (menos carga CPU/GPU)
        ThermalBatteryManager.shared.onShouldReduceScan = { [weak self] in
            guard let self = self else { return }
            self.meshTimerInterval = 3.0
            self.stopMeshTimer()
            self.startMeshTimer()
            self.showGuidanceWarning(
                ThermalBatteryManager.shared.thermalWarningMessage()
                ?? "Temperatura alta — calidad reducida"
            )
        }

        // Temperatura crítica → pausar escaneo automáticamente
        ThermalBatteryManager.shared.onShouldStopScan = { [weak self] in
            guard let self = self, !self.isPaused else { return }
            self.pauseBySystem(reason: "Temperatura crítica — escaneo pausado para proteger el dispositivo")
        }

        // Batería baja → aviso
        ThermalBatteryManager.shared.onBatteryWarning = { [weak self] level in
            let msg = "Batería \(Int(level * 100))% — conecta el cargador"
            self?.showGuidanceWarning(msg)
        }

        // Calidad ARKit cambia → actualizar guidance label
        ScanQualityManager.shared.onQualityChanged = { [weak self] quality in
            guard let self = self else { return }
            switch quality {
            case .lost:
                self.showGuidanceWarning("Tracking perdido — apunta a una superficie plana")
            case .poor:
                self.showGuidanceWarning("Mueve el dispositivo más despacio")
            case .good, .excellent:
                self.refreshProgress()   // restaurar mensaje normal
            }
        }

        ScanQualityManager.shared.onSuggestRescan = { [weak self] msg in
            self?.showGuidanceWarning(msg)
        }
    }

    // MARK: – Ciclo de vida de la aplicación

    private func registerLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private func removeLifecycleNotifications() {
        NotificationCenter.default.removeObserver(
            self, name: UIApplication.willResignActiveNotification, object: nil
        )
        NotificationCenter.default.removeObserver(
            self, name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    // App pierde foco (llamada, notificación, home): pausa automática
    @objc private func appWillResignActive() {
        guard !isPaused else { return }
        pauseBySystem(reason: "Escaneo pausado — vuelve para continuar")
    }

    // App recupera foco: reanuda si fue el sistema quien pausó
    @objc private func appDidBecomeActive() {
        guard pausedBySystem else { return }
        pausedBySystem = false
        isPaused = false
        overlay?.setPauseState(false)
        // Reiniciar tracking conservando anchors existentes
        if let cfg = captureSession.arSession.configuration {
            captureSession.arSession.run(cfg, options: [.resetTracking])
        }
        refreshProgress()
    }

    // Pausa iniciada por el sistema (no por el usuario)
    private func pauseBySystem(reason: String) {
        isPaused = true
        pausedBySystem = true
        captureSession.arSession.pause()
        overlay?.setPauseState(true)
        showGuidanceWarning(reason)
        UIStateManager.shared.switchMode(.processing)
    }

    // MARK: – Construcción del overlay

    private func buildGuidanceOverlay() {
        let topInset = max(view.safeAreaInsets.top, 50)
        let botInset = max(view.safeAreaInsets.bottom, 20)

        overlay = ScanGuidanceOverlay(frame: view.bounds,
                                      topInset: topInset,
                                      botInset: botInset)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlay)

        overlay.onClose = { [weak self] in
            self?.captureSession.stop()
            self?.dismiss(animated: true) { self?.onResult?(nil) }
        }
        overlay.onPause = { [weak self] in
            guard let self = self else { return }
            self.isPaused.toggle()
            self.pausedBySystem = false          // pausa manual
            self.overlay.setPauseState(self.isPaused)
            if self.isPaused {
                self.captureSession.arSession.pause()
                UIStateManager.shared.switchMode(.processing)
            } else {
                if let cfg = self.captureSession.arSession.configuration {
                    self.captureSession.arSession.run(cfg, options: [.resetTracking])
                }
                UIStateManager.shared.switchMode(.scanning)
                self.refreshProgress()
            }
        }
        overlay.onDone = { [weak self] in
            UIStateManager.shared.switchMode(.processing)
            self?.captureSession.stop()
        }
        overlay.onTorch = { [weak self] in
            guard let self = self else { return }
            self.torchOn.toggle()
            self.setTorch(self.torchOn)
            self.overlay.setTorchState(self.torchOn)
        }
    }

    // MARK: – Timer de mesh

    private func startMeshTimer() {
        meshTimer?.invalidate()
        meshTimer = Timer.scheduledTimer(withTimeInterval: meshTimerInterval,
                                         repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused else { return }

            let arAnchors = self.captureSession.arSession.currentFrame?.anchors
                .compactMap { $0 as? ARMeshAnchor } ?? []
            guard !arAnchors.isEmpty else { return }

            // Evaluar calidad de frame (tracking + iluminación + profundidad)
            if let frame = self.captureSession.arSession.currentFrame {
                ScanQualityManager.shared.evaluate(frame: frame)
            }

            // Verificar presupuesto de memoria antes de acumular
            let totalVerts = arAnchors.reduce(0) { $0 + $1.geometry.vertices.count }
            if MeshOptimizationManager.shared.isWithinMemoryBudget(vertexCount: totalVerts,
                                                                    limit: 500_000) {
                MeshManager.shared.setMeshAnchors(arAnchors)
            } else {
                // Demasiados vértices: quitar los más antiguos antes de añadir
                MeshManager.shared.removeOldAnchors(session: self.captureSession.arSession,
                                                    keepLast: 40)
                MeshManager.shared.setMeshAnchors(arAnchors)
            }

            self.meshTickCount += 1

            // ── Volumen + altura cada 2 ticks (~3 s) — Gap 3 ─────────────────
            if self.meshTickCount % 2 == 0 {
                DispatchQueue.global(qos: .background).async { [weak self] in
                    guard let self = self else { return }
                    let h   = VolumeCalculator.shared.estimateHeight()
                    let vol = MeshManager.shared.surfaces.floor * max(h, 0.5)
                    DispatchQueue.main.async {
                        self.liveHeight = h
                        self.liveVolume = vol
                        self.overlay?.updateLiveMetrics(volume: vol,
                                                        height: h,
                                                        perimeter: self.livePerimeter)
                    }
                }
            }

            // ── Paredes + progreso cada 3 ticks (~4.5 s) — Gap 6 ─────────────
            if self.meshTickCount % 3 == 0 {
                MeasurementManager.shared.calculateWallAreas()
                self.refreshProgress()
                UIStateManager.shared.updateProgress(
                    NavigationManager.shared.calculateScanProgress().percentage
                )
            }

            // ── Reconstruir footprint + calcular perímetro cada 5 ticks (~7.5 s) — Gaps 1 & 5
            if self.meshTickCount % 5 == 0 {
                self.refreshPlanPreview()   // ya construye footprint
                DispatchQueue.global(qos: .background).async { [weak self] in
                    guard let self = self else { return }
                    if let fp = FloorFootprintBuilder.build(simplifyEpsilon: 0.08) {
                        DispatchQueue.main.async {
                            self.livePerimeter = fp.perimeter
                            self.overlay?.updateLiveMetrics(volume: self.liveVolume,
                                                            height: self.liveHeight,
                                                            perimeter: fp.perimeter)
                        }
                    }
                }
            }
        }
    }

    private func stopMeshTimer() {
        meshTimer?.invalidate()
        meshTimer = nil
    }

    // MARK: – Progreso y plano

    private func refreshProgress() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sp = NavigationManager.shared.calculateScanProgress()
            DispatchQueue.main.async {
                guard let self = self else { return }
                // El progreso nunca retrocede (evita saltos al recalcular)
                let p = max(self.lastProgress, sp.percentage)
                self.lastProgress = p
                self.overlay?.updateProgress(p, guidance: sp.guidanceMessage)
            }
        }
    }

    private func refreshPlanPreview() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if let room = RoomPlanManager.shared.lastCapturedRoom,
               let fp   = RoomPlanManager.shared.floorFootprint {
                let img = PlanRenderer.shared.renderCombined(
                    room: room, footprint: fp,
                    size: CGSize(width: 160, height: 160)
                )
                DispatchQueue.main.async { self.overlay?.updatePlanPreview(img) }
            } else if let fp = FloorFootprintBuilder.build(simplifyEpsilon: 0.08) {
                let img = PlanRenderer.shared.renderFloorFootprint(
                    fp, size: CGSize(width: 160, height: 160)
                )
                DispatchQueue.main.async { self.overlay?.updatePlanPreview(img) }
            }
        }
    }

    // MARK: – Aviso temporal en guidance label (3 s, luego restaura progreso)

    private func showGuidanceWarning(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.overlay?.updateProgress(self.lastProgress, guidance: message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                self?.refreshProgress()
            }
        }
    }

    // MARK: – Linterna

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

// ── RoomCaptureSessionDelegate ────────────────────────────────────────────────
@available(iOS 16.0, *)
extension RoomPlanViewController: RoomCaptureSessionDelegate {

    // Actualización en tiempo real durante el escaneo
    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        // Guardar conteo de puertas/ventanas para los badges
        liveDoors   = room.doors.count
        liveWindows = room.windows.count

        // Superficie del suelo (iOS 17+) o estimación desde paredes
        var area: Float = 0
        if #available(iOS 17.0, *) {
            area = room.floors.reduce(0) { $0 + $1.dimensions.x * $1.dimensions.z }
        }
        if area < 0.5, !room.walls.isEmpty {
            let ws = room.walls.map { $0.dimensions.x }.sorted(by: >)
            area   = ws.count >= 2 ? ws[0] * ws[1] : ws[0] * ws[0]
        }

        let surfaces = MeshManager.shared.surfaces
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Actualizar badges con datos frescos de RoomPlan
            self.overlay?.updateSurfaces(surfaces,
                                         doors: room.doors.count,
                                         windows: room.windows.count)
            // Actualizar guía con nueva info de paredes detectadas
            let wallArea = room.walls.reduce(Float(0)) { $0 + $1.dimensions.x * $1.dimensions.y }
            let wallMsg  = room.walls.count > 0
                ? "Paredes: \(room.walls.count) · \(String(format:"%.1f",wallArea)) m²"
                : nil
            if let msg = wallMsg {
                let pct = min(Float(room.walls.count) / 4.0, 0.5)
                self.overlay?.updateProgress(pct, guidance: msg)
            }
        }
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error = error {
            dismiss(animated: true) { [weak self] in
                self?.onResult?(["error": error.localizedDescription])
            }
            return
        }

        // Guardar mesh anchors ARKit para exportación posterior
        let arAnchors = captureSession.arSession.currentFrame?.anchors
            .compactMap { $0 as? ARMeshAnchor } ?? []
        if !arAnchors.isEmpty {
            MeshManager.shared.setMeshAnchors(arAnchors)
        }

        Task {
            do {
                let room = try await RoomBuilder(options: []).capturedRoom(from: data)
                RoomPlanManager.shared.lastCapturedRoom = room

                let _ = ExportManager.shared.exportUSDZ(room: room, named: "mi-render-scan")

                let tmpUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mi-render-scan.usdz")
                try? room.export(to: tmpUrl, exportOptions: .parametric)

                var result = self.buildResult(from: room)
                if let usdzUrl = ExportManager.shared.lastUsdzUrl {
                    result["usdzPath"] = usdzUrl.path
                }
                result["meshAnchorsCount"] = arAnchors.count
                await MainActor.run {
                    self.dismiss(animated: true) { [weak self] in
                        self?.onResult?(result)
                    }
                }
            } catch {
                await MainActor.run {
                    self.dismiss(animated: true) { [weak self] in
                        self?.onResult?(["error": error.localizedDescription])
                    }
                }
            }
        }
    }

    private func buildResult(from room: CapturedRoom) -> [String: Any] {

        var floorArea   = Float(0)
        var wallArea    = Float(0)
        var totalVolume = Float(0)
        var perimeter   = Float(0)

        if #available(iOS 17.0, *) {
            floorArea = room.floors.reduce(Float(0)) { $0 + $1.dimensions.x * $1.dimensions.z }
        }
        if floorArea == 0, !room.walls.isEmpty {
            let widths = room.walls.map { $0.dimensions.x }
            let maxW   = widths.max() ?? 0
            let maxL   = widths.sorted().dropLast().last ?? maxW
            floorArea  = maxW * maxL
        }

        let walls: [[String: Any]] = room.walls.map { wall in
            let t = wall.transform
            wallArea  += wall.dimensions.x * wall.dimensions.y
            perimeter += wall.dimensions.x
            return [
                "width":      Double(wall.dimensions.x),
                "height":     Double(wall.dimensions.y),
                "depth":      Double(wall.dimensions.z),
                "confidence": confidenceString(wall.confidence),
                "posX":       Double(t.columns.3.x),
                "posY":       Double(t.columns.3.y),
                "posZ":       Double(t.columns.3.z),
                "angle":      Double(atan2(t.columns.0.z, t.columns.0.x)),
            ]
        }

        let avgHeight = room.walls.isEmpty ? Float(2.5) :
            room.walls.map { $0.dimensions.y }.reduce(0, +) / Float(room.walls.count)
        totalVolume = floorArea * avgHeight

        let windows: [[String: Any]] = room.windows.map { w in
            let t = w.transform
            return [
                "width":  Double(w.dimensions.x),
                "height": Double(w.dimensions.y),
                "posX":   Double(t.columns.3.x),
                "posY":   Double(t.columns.3.y),
                "posZ":   Double(t.columns.3.z),
                "angle":  Double(atan2(t.columns.0.z, t.columns.0.x)),
            ]
        }
        let windowArea = room.windows.reduce(Float(0)) { $0 + Float($1.dimensions.x * $1.dimensions.y) }

        let doors: [[String: Any]] = room.doors.map { d in
            let t = d.transform
            return [
                "width":  Double(d.dimensions.x),
                "height": Double(d.dimensions.y),
                "posX":   Double(t.columns.3.x),
                "posY":   Double(t.columns.3.y),
                "posZ":   Double(t.columns.3.z),
                "angle":  Double(atan2(t.columns.0.z, t.columns.0.x)),
                "isOpen": false,
            ]
        }

        let openings: [[String: Any]] = room.openings.map { o in
            let t = o.transform
            return [
                "width":  Double(o.dimensions.x),
                "height": Double(o.dimensions.y),
                "posX":   Double(t.columns.3.x),
                "posZ":   Double(t.columns.3.z),
                "angle":  Double(atan2(t.columns.0.z, t.columns.0.x)),
            ]
        }

        return [
            "floorArea":    Double(floorArea),
            "wallArea":     Double(wallArea),
            "windowArea":   Double(windowArea),
            "totalVolume":  Double(totalVolume),
            "perimeter":    Double(perimeter),
            "avgHeight":    Double(avgHeight),
            "walls":        walls,
            "wallCount":    room.walls.count,
            "doors":        doors,
            "windows":      windows,
            "openings":     openings,
            "scanMode":     "roomplan",
            "confidence":   "high",
            "usdzExported": true,
        ]
    }

    private func confidenceString(_ c: CapturedRoom.Confidence) -> String {
        switch c {
        case .high:   return "high"
        case .medium: return "medium"
        case .low:    return "low"
        @unknown default: return "unknown"
        }
    }
}

// ── ObjectScan ViewController (ARKit .mesh) ───────────────────────────────────
class ObjectScanViewController: UIViewController, ARSessionDelegate {

    var onResult: (([String: Any]?) -> Void)?

    private var arView:      ARSCNView!
    private var meshAnchors: [ARMeshAnchor] = []
    private var scanTimer:   Timer?
    private var isProcessing = false

    private var progressLabel: UILabel!
    private var captureBtn:    UIButton!
    private var closeBtn:      UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.session.delegate = self

        view.addSubview(arView)
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        arView.session.pause()
        scanTimer?.invalidate()
    }

    private func startARSession() {
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.finalizeScan()
        }
    }

    private func setupUI() {
        let topInset = max(view.safeAreaInsets.top, 44)
        let w = view.bounds.width

        progressLabel = UILabel()
        progressLabel.text = "Mueve el iPhone alrededor del objeto"
        progressLabel.textColor = .white
        progressLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        progressLabel.textAlignment = .center
        progressLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        progressLabel.layer.cornerRadius = 16
        progressLabel.clipsToBounds = true
        progressLabel.frame = CGRect(x: (w-280)/2, y: topInset + 8, width: 280, height: 36)
        view.addSubview(progressLabel)

        closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.tintColor = .white
        closeBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeBtn.layer.cornerRadius = 22
        closeBtn.frame = CGRect(x: 16, y: topInset + 8, width: 44, height: 44)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        captureBtn = UIButton(type: .system)
        captureBtn.setTitle("✓  Capturar objeto", for: .normal)
        captureBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        captureBtn.setTitleColor(UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1), for: .normal)
        captureBtn.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        captureBtn.layer.cornerRadius = 22
        captureBtn.layer.borderWidth  = 1.5
        captureBtn.layer.borderColor  = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.6).cgColor
        let bw: CGFloat = 180
        captureBtn.frame = CGRect(x: (w-bw)/2, y: view.bounds.height - 100, width: bw, height: 48)
        captureBtn.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureBtn)
    }

    @objc private func closeTapped() {
        arView.session.pause()
        scanTimer?.invalidate()
        dismiss(animated: true) { [weak self] in self?.onResult?(nil) }
    }

    @objc private func captureTapped() { finalizeScan() }

    private func finalizeScan() {
        guard !isProcessing else { return }
        isProcessing = true
        scanTimer?.invalidate()
        DispatchQueue.main.async {
            self.progressLabel.text = "Procesando malla 3D…"
            self.captureBtn.isEnabled = false
        }
        let anchors = meshAnchors
        // Registrar anchors en MeshManager para exportación posterior
        anchors.forEach { MeshManager.shared.addAnchor($0) }

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.buildMeshResult(from: anchors)
            DispatchQueue.main.async {
                self.arView.session.pause()
                self.dismiss(animated: true) { [weak self] in
                    self?.onResult?(result)
                }
            }
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        if !meshes.isEmpty { meshAnchors.append(contentsOf: meshes); updateLabel() }
    }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) {
            if let idx = meshAnchors.firstIndex(where: { $0.identifier == anchor.identifier }) {
                meshAnchors[idx] = anchor
            }
        }
        updateLabel()
    }

    private func updateLabel() {
        let faces = meshAnchors.reduce(0) { $0 + $1.geometry.faces.count }
        DispatchQueue.main.async {
            self.progressLabel.text = faces < 500 ? "Mueve alrededor del objeto…"
                : faces < 2000 ? "Buen progreso — sigue escaneando"
                : "Listo para capturar ✓"
        }
    }

    private func buildMeshResult(from anchors: [ARMeshAnchor]) -> [String: Any] {
        var totalFaces = 0, totalVertices = 0
        var minX = Float.infinity, minY = Float.infinity, minZ = Float.infinity
        var maxX = -Float.infinity, maxY = -Float.infinity, maxZ = -Float.infinity

        for anchor in anchors {
            let geo = anchor.geometry
            totalFaces    += geo.faces.count
            totalVertices += geo.vertices.count
            let transform = anchor.transform
            let vBuf = geo.vertices
            for i in 0..<vBuf.count {
                let ptr = vBuf.buffer.contents()
                    .advanced(by: vBuf.offset + i * vBuf.stride)
                    .assumingMemoryBound(to: Float.self)
                let w = transform * simd_float4(ptr[0], ptr[1], ptr[2], 1)
                minX = min(minX, w.x); maxX = max(maxX, w.x)
                minY = min(minY, w.y); maxY = max(maxY, w.y)
                minZ = min(minZ, w.z); maxZ = max(maxZ, w.z)
            }
        }

        let width = maxX - minX, height = maxY - minY, depth = maxZ - minZ
        return [
            "scanMode":     "object-mesh",
            "meshFaces":    totalFaces,
            "meshVertices": totalVertices,
            "anchorCount":  anchors.count,
            "boundingBox":  ["width": Double(width), "height": Double(height), "depth": Double(depth)],
            "dimensions":   String(format: "%.2f m × %.2f m × %.2f m", width, height, depth),
            "confidence":   totalFaces > 2000 ? "high" : totalFaces > 500 ? "medium" : "low",
        ]
    }
}
