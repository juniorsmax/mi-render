import Foundation
import Capacitor
import ARKit
import RoomPlan

/**
 * LiDARPlugin — RoomPlan + ARKit para mi-render
 * Usa RoomCaptureView (Apple RoomPlan API, iOS 16+, requiere LiDAR)
 * Añade escaneo de objetos 3D via ARKit Scene Reconstruction (.mesh)
 */
@objc(LiDARPlugin)
public class LiDARPlugin: CAPPlugin {

    private var pendingCall: CAPPluginCall?

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

    // ── startScan (RoomPlan — escaneo de habitación) ─────────────────────────
    @objc func startScan(_ call: CAPPluginCall) {
        guard #available(iOS 16.0, *) else {
            call.reject("RoomPlan requiere iOS 16 o superior")
            return
        }
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) else {
            call.reject("Este dispositivo no tiene sensor LiDAR. RoomPlan requiere iPhone 12 Pro o superior.")
            return
        }

        pendingCall = call

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let vc = RoomPlanViewController()
            vc.onResult = { [weak self] result in
                if let result = result {
                    self?.pendingCall?.resolve(result)
                } else {
                    self?.pendingCall?.reject("Escaneo cancelado")
                }
                self?.pendingCall = nil
            }
            vc.modalPresentationStyle = .fullScreen
            self.bridge?.viewController?.present(vc, animated: true)
        }
    }

    // ── startObjectScan (ARKit .mesh — escaneo de objetos 3D) ────────────────
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
        DispatchQueue.main.async {
            self.bridge?.viewController?.presentedViewController?.dismiss(animated: true)
        }
        pendingCall?.reject("Escaneo detenido")
        pendingCall = nil
        call.resolve(["stopped": true])
    }
}

// ── RoomPlan ViewController (iOS 16+, LiDAR) ─────────────────────────────────
@available(iOS 16.0, *)
class RoomPlanViewController: UIViewController {

    var onResult: (([String: Any]?) -> Void)?

    private var captureView:    RoomCaptureView!
    private var captureSession: RoomCaptureSession!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // RoomCaptureView — UI nativa de Apple con guías AR automáticas
        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)

        captureSession = captureView.captureSession
        captureSession.delegate = self

        addButtons()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stop()
    }

    // ── Botones ───────────────────────────────────────────────────────────────
    private func addButtons() {
        let topInset = view.safeAreaInsets.top > 0 ? view.safeAreaInsets.top : 44
        let w = view.bounds.width

        // Cerrar
        let closeBtn = circleButton(title: "✕", color: .white)
        closeBtn.frame = CGRect(x: 16, y: topInset + 12, width: 44, height: 44)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        // Listo
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("✓  Listo", for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        doneBtn.setTitleColor(UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1), for: .normal)
        doneBtn.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        doneBtn.layer.cornerRadius = 22
        doneBtn.layer.borderWidth  = 1.5
        doneBtn.layer.borderColor  = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.6).cgColor
        doneBtn.frame = CGRect(x: w - 110, y: topInset + 12, width: 94, height: 44)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)
    }

    private func circleButton(title: String, color: UIColor) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.tintColor = color
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        btn.layer.cornerRadius = 22
        return btn
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

    // Llamado al finalizar el escaneo
    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error = error {
            dismiss(animated: true) { [weak self] in
                self?.onResult?(["error": error.localizedDescription])
            }
            return
        }

        // Procesar con RoomBuilder para obtener el modelo final
        Task {
            do {
                let room = try await RoomBuilder(options: []).capturedRoom(from: data)
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

    // ── Convertir CapturedRoom → JSON ─────────────────────────────────────────
    private func buildResult(from room: CapturedRoom) -> [String: Any] {

        // Área del suelo (floors disponible en iOS 17+)
        var floorArea = Float(0)
        if #available(iOS 17.0, *) {
            floorArea = room.floors.reduce(Float(0)) { acc, floor in
                acc + floor.dimensions.x * floor.dimensions.z
            }
        }
        // iOS 16: estimar área desde paredes (perímetro aproximado)
        if floorArea == 0 && !room.walls.isEmpty {
            let widths  = room.walls.map { $0.dimensions.x }
            let maxW    = widths.max() ?? 0
            let maxL    = widths.sorted().dropLast().last ?? maxW
            floorArea   = maxW * maxL
        }

        // Paredes
        let walls: [[String: Any]] = room.walls.map { wall in
            [
                "width":      wall.dimensions.x,
                "height":     wall.dimensions.y,
                "confidence": confidenceString(wall.confidence),
            ]
        }

        // Puertas y ventanas
        let doors: [[String: Any]] = room.doors.map { d in
            ["width": d.dimensions.x, "height": d.dimensions.y]
        }
        let windows: [[String: Any]] = room.windows.map { w in
            ["width": w.dimensions.x, "height": w.dimensions.y]
        }

        return [
            "floorArea":  floorArea,
            "walls":      walls,
            "wallCount":  room.walls.count,
            "doors":      doors,
            "windows":    windows,
            "scanMode":   "roomplan",
            "confidence": "high",
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

// ── ObjectScan ViewController (ARKit Scene Reconstruction .mesh) ──────────────
class ObjectScanViewController: UIViewController, ARSessionDelegate {

    var onResult: (([String: Any]?) -> Void)?

    private var arView:   ARSCNView!
    private var session:  ARSession { arView.session }
    private var meshAnchors: [ARMeshAnchor] = []
    private var scanTimer: Timer?
    private var isProcessing = false

    // UI
    private var progressLabel: UILabel!
    private var captureBtn:    UIButton!
    private var closeBtn:      UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // AR Scene View con mesh reconstruction
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.session.delegate = self
        view.addSubview(arView)

        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
        scanTimer?.invalidate()
    }

    private func startARSession() {
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        // Auto-capture después de 15 segundos si el usuario no pulsa
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            self?.finalizeScan()
        }
    }

    private func setupUI() {
        let topInset = max(view.safeAreaInsets.top, 44)
        let w = view.bounds.width

        // Instrucción
        progressLabel = UILabel()
        progressLabel.text = "Mueve el iPhone alrededor del objeto"
        progressLabel.textColor = .white
        progressLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        progressLabel.textAlignment = .center
        progressLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        progressLabel.layer.cornerRadius = 16
        progressLabel.clipsToBounds = true
        progressLabel.frame = CGRect(x: (w-280)/2, y: topInset + 12, width: 280, height: 36)
        view.addSubview(progressLabel)

        // Cerrar
        closeBtn = UIButton(type: .system)
        closeBtn.setTitle("✕", for: .normal)
        closeBtn.tintColor = .white
        closeBtn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        closeBtn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        closeBtn.layer.cornerRadius = 22
        closeBtn.frame = CGRect(x: 16, y: topInset + 12, width: 44, height: 44)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        // Botón captura
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
        session.pause()
        scanTimer?.invalidate()
        dismiss(animated: true) { [weak self] in self?.onResult?(nil) }
    }

    @objc private func captureTapped() {
        finalizeScan()
    }

    private func finalizeScan() {
        guard !isProcessing else { return }
        isProcessing = true
        scanTimer?.invalidate()

        DispatchQueue.main.async {
            self.progressLabel.text = "Procesando malla 3D…"
            self.captureBtn.isEnabled = false
        }

        // Recopilar datos de malla de ARMeshAnchor
        let anchors = meshAnchors
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.buildMeshResult(from: anchors)
            DispatchQueue.main.async {
                self.session.pause()
                self.dismiss(animated: true) { [weak self] in
                    self?.onResult?(result)
                }
            }
        }
    }

    // ── ARSessionDelegate ─────────────────────────────────────────────────────
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let meshes = anchors.compactMap { $0 as? ARMeshAnchor }
        if !meshes.isEmpty {
            meshAnchors.append(contentsOf: meshes)
            updateProgressLabel()
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) {
            if let idx = meshAnchors.firstIndex(where: { $0.identifier == anchor.identifier }) {
                meshAnchors[idx] = anchor
            }
        }
        updateProgressLabel()
    }

    private func updateProgressLabel() {
        let totalFaces = meshAnchors.reduce(0) { $0 + $1.geometry.faces.count }
        DispatchQueue.main.async {
            if totalFaces < 500 {
                self.progressLabel.text = "Mueve alrededor del objeto…"
            } else if totalFaces < 2000 {
                self.progressLabel.text = "Buen progreso — sigue escaneando"
            } else {
                self.progressLabel.text = "Listo para capturar ✓"
            }
        }
    }

    // ── Construir resultado desde mallas ARKit ────────────────────────────────
    private func buildMeshResult(from anchors: [ARMeshAnchor]) -> [String: Any] {
        var totalFaces    = 0
        var totalVertices = 0
        var minX = Float.infinity, minY = Float.infinity, minZ = Float.infinity
        var maxX = -Float.infinity, maxY = -Float.infinity, maxZ = -Float.infinity

        for anchor in anchors {
            let geo = anchor.geometry
            totalFaces    += geo.faces.count
            totalVertices += geo.vertices.count

            // Calcular bounding box en coordenadas mundo
            let transform = anchor.transform
            let vBuf = geo.vertices
            let stride = vBuf.stride
            let count  = vBuf.count

            for i in 0..<count {
                let offset = i * stride
                let ptr = vBuf.buffer.contents().advanced(by: vBuf.offset + offset)
                    .assumingMemoryBound(to: Float.self)
                let lx = ptr[0], ly = ptr[1], lz = ptr[2]
                let world = transform * simd_float4(lx, ly, lz, 1)
                minX = min(minX, world.x); maxX = max(maxX, world.x)
                minY = min(minY, world.y); maxY = max(maxY, world.y)
                minZ = min(minZ, world.z); maxZ = max(maxZ, world.z)
            }
        }

        let width  = maxX - minX
        let height = maxY - minY
        let depth  = maxZ - minZ

        return [
            "scanMode":     "object-mesh",
            "meshFaces":    totalFaces,
            "meshVertices": totalVertices,
            "anchorCount":  anchors.count,
            "boundingBox": [
                "width":  width,
                "height": height,
                "depth":  depth,
            ],
            "dimensions": String(format: "%.2f m × %.2f m × %.2f m", width, height, depth),
            "confidence":   totalFaces > 2000 ? "high" : totalFaces > 500 ? "medium" : "low",
        ]
    }
}
