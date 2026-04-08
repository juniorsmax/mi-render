import Foundation
import Capacitor
import ARKit
import RoomPlan
import CoreLocation

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

    // ── exportOBJ ────────────────────────────────────────────────────────────
    @objc func exportOBJ(_ call: CAPPluginCall) {
        let name = call.getString("name") ?? "mi-render-mesh"
        let meshes = MeshManager.shared.getAllMeshes()

        guard !meshes.isEmpty else {
            call.reject("No hay malla 3D capturada para exportar")
            return
        }

        let asset = MeshManager.shared.combinedMesh()
        if let url = ExportManager.shared.exportAsset(asset, format: .obj, named: name) {
            call.resolve(["path": url.path, "format": "obj"])
        } else {
            call.reject("Error exportando OBJ")
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
        if let url = ExportManager.shared.exportAsset(asset, format: .ply, named: name) {
            call.resolve(["path": url.path, "format": "ply"])
        } else {
            call.reject("Error exportando PLY")
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
        if let url = ExportManager.shared.exportAsset(asset, format: .stl, named: name) {
            call.resolve(["path": url.path, "format": "stl"])
        } else {
            call.reject("Error exportando STL")
        }
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

// ── RoomPlan ViewController (iOS 16+) ────────────────────────────────────────
@available(iOS 16.0, *)
class RoomPlanViewController: UIViewController {

    var onResult: (([String: Any]?) -> Void)?

    private var captureView:    RoomCaptureView!
    private var captureSession: RoomCaptureSession!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)

        captureSession = captureView.captureSession
        captureSession.delegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        captureSession.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.viewWithTag(101) != nil { return }

        let topInset = view.safeAreaInsets.top + 12
        let w = view.bounds.width

        let closeBtn = UIButton(type: .system)
        closeBtn.tag = 101
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.tintColor = .white
        closeBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeBtn.layer.cornerRadius = 22
        closeBtn.frame = CGRect(x: 16, y: topInset, width: 44, height: 44)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        let doneBtn = UIButton(type: .system)
        doneBtn.tag = 102
        doneBtn.setTitle("✓  Listo", for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        doneBtn.setTitleColor(UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1), for: .normal)
        doneBtn.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        doneBtn.layer.cornerRadius = 22
        doneBtn.layer.borderWidth  = 1.5
        doneBtn.layer.borderColor  = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.6).cgColor
        doneBtn.frame = CGRect(x: w - 110, y: topInset, width: 94, height: 44)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)
    }

    @objc private func closeTapped() {
        captureSession.stop()
        dismiss(animated: true) { [weak self] in self?.onResult?(nil) }
    }

    @objc private func doneTapped() {
        captureSession.stop()
    }
}

// ── RoomCaptureSessionDelegate ────────────────────────────────────────────────
@available(iOS 16.0, *)
extension RoomPlanViewController: RoomCaptureSessionDelegate {

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error = error {
            dismiss(animated: true) { [weak self] in
                self?.onResult?(["error": error.localizedDescription])
            }
            return
        }

        Task {
            do {
                let room = try await RoomBuilder(options: []).capturedRoom(from: data)

                // Guardar en RoomPlanManager para acceso posterior (exportUSDZ, etc.)
                RoomPlanManager.shared.lastCapturedRoom = room

                // Exportar USDZ al directorio de exportaciones
                let _ = ExportManager.shared.exportUSDZ(room: room, named: "mi-render-scan")

                // También en tmp para compatibilidad con flujo anterior
                let tmpUrl = FileManager.default.temporaryDirectory
                    .appendingPathComponent("mi-render-scan.usdz")
                try? room.export(to: tmpUrl, exportOptions: .parametric)

                let result = self.buildResult(from: room)
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

        var floorArea  = Float(0)
        var wallArea   = Float(0)
        var totalVolume = Float(0)
        var perimeter  = Float(0)

        if #available(iOS 17.0, *) {
            floorArea = room.floors.reduce(Float(0)) { acc, f in
                acc + f.dimensions.x * f.dimensions.z
            }
        }
        if floorArea == 0 && !room.walls.isEmpty {
            let widths = room.walls.map { $0.dimensions.x }
            let maxW   = widths.max() ?? 0
            let maxL   = widths.sorted().dropLast().last ?? maxW
            floorArea  = maxW * maxL
        }

        let walls: [[String: Any]] = room.walls.map { wall in
            let t = wall.transform
            wallArea += wall.dimensions.x * wall.dimensions.y
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
            "floorArea":   Double(floorArea),
            "wallArea":    Double(wallArea),
            "windowArea":  Double(windowArea),
            "totalVolume": Double(totalVolume),
            "perimeter":   Double(perimeter),
            "avgHeight":   Double(avgHeight),
            "walls":       walls,
            "wallCount":   room.walls.count,
            "doors":       doors,
            "windows":     windows,
            "openings":    openings,
            "scanMode":    "roomplan",
            "confidence":  "high",
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
