import Foundation
import Capacitor
import ARKit

/**
 * LiDARPlugin — Plugin Capacitor nativo para LiDAR / RoomPlan
 * Agentes: Kai (iOS) + Ares (Escáner)
 *
 * Registrado en LiDARPlugin.m via CAP_PLUGIN macro.
 * Llamado desde JavaScript via Capacitor.Plugins.LiDARPlugin
 */
@objc(LiDARPlugin)
public class LiDARPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "LiDARPlugin"
    public let jsName = "LiDARPlugin"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "isAvailable",  returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startScan",    returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopScan",     returnType: CAPPluginReturnPromise),
    ]

    private var pendingCall: CAPPluginCall?

    // ── isAvailable ──────────────────────────────────────────────────────────
    @objc func isAvailable(_ call: CAPPluginCall) {
        var result: [String: Any] = [:]

        if #available(iOS 16.0, *) {
            let roomPlanSupported = checkRoomPlanSupport()
            result["available"]  = roomPlanSupported
            result["roomPlan"]   = roomPlanSupported
            result["lidar"]      = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            result["arKit"]      = ARWorldTrackingConfiguration.isSupported
            result["iosVersion"] = UIDevice.current.systemVersion
        } else {
            result["available"]  = false
            result["roomPlan"]   = false
            result["lidar"]      = false
            result["arKit"]      = ARWorldTrackingConfiguration.isSupported
            result["iosVersion"] = UIDevice.current.systemVersion
        }

        call.resolve(result)
    }

    // ── startScan ────────────────────────────────────────────────────────────
    @objc func startScan(_ call: CAPPluginCall) {
        guard #available(iOS 16.0, *) else {
            call.reject("RoomPlan requiere iOS 16+")
            return
        }
        guard checkRoomPlanSupport() else {
            call.reject("Este dispositivo no tiene sensor LiDAR")
            return
        }

        pendingCall = call

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let vc = RoomScanViewController()
            vc.onComplete = { [weak self] result in
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

    // ── stopScan ─────────────────────────────────────────────────────────────
    @objc func stopScan(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.bridge?.viewController?.presentedViewController?.dismiss(animated: true)
        }
        pendingCall?.reject("Escaneo detenido manualmente")
        pendingCall = nil
        call.resolve(["stopped": true])
    }

    // ── Detectar RoomPlan sin importarlo directamente ─────────────────────────
    private func checkRoomPlanSupport() -> Bool {
        if #available(iOS 16.0, *) {
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }
        return false
    }
}

// ── ViewController del escaneo ────────────────────────────────────────────────
@available(iOS 16.0, *)
class RoomScanViewController: UIViewController {

    var onComplete: (([String: Any]?) -> Void)?
    private var session: ARSession!
    private var sceneView: ARSCNView!
    private var isScanning = false
    private var scanStartTime: Date?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupARView()
        setupHUD()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session?.pause()
    }

    // ── Configurar vista AR ──────────────────────────────────────────────────
    private func setupARView() {
        session = ARSession()
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.session = session
        sceneView.automaticallyUpdatesLighting = true
        view.addSubview(sceneView)
    }

    private func startARSession() {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isScanning = true
        scanStartTime = Date()
    }

    // ── HUD ──────────────────────────────────────────────────────────────────
    private func setupHUD() {
        // Botón cerrar
        let closeBtn = makeButton(title: "✕", x: 20, y: 60, w: 44, h: 44)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        // Instrucción
        let label = UILabel()
        label.text = "Mueve el iPhone por la habitación"
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.layer.cornerRadius = 20
        label.layer.masksToBounds = true
        label.frame = CGRect(x: 20, y: 70, width: view.bounds.width - 40, height: 40)
        view.addSubview(label)

        // Botón Listo
        let doneBtn = makeButton(title: "✓ Listo", x: view.bounds.width - 110, y: 60, w: 90, h: 44)
        doneBtn.backgroundColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.9)
        doneBtn.setTitleColor(.black, for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)
    }

    private func makeButton(title: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        btn.layer.cornerRadius = h / 2
        btn.frame = CGRect(x: x, y: y, width: w, height: h)
        return btn
    }

    // ── Acciones ─────────────────────────────────────────────────────────────
    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onComplete?(nil)
        }
    }

    @objc private func doneTapped() {
        session.pause()
        let result = buildResult()
        dismiss(animated: true) { [weak self] in
            self?.onComplete?(result)
        }
    }

    // ── Construir resultado desde anchors de ARKit ────────────────────────────
    private func buildResult() -> [String: Any] {
        var floorArea: Float = 0
        var wallCount = 0
        var walls: [[String: Any]] = []

        for anchor in session.currentFrame?.anchors ?? [] {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                if planeAnchor.alignment == .horizontal && planeAnchor.classification == .floor {
                    let ext = planeAnchor.planeExtent
                    floorArea += ext.width * ext.height
                }
                if planeAnchor.alignment == .vertical {
                    wallCount += 1
                    let ext = planeAnchor.planeExtent
                    walls.append([
                        "width":  ext.width,
                        "height": ext.height,
                    ])
                }
            }
        }

        let duration = scanStartTime.map { Date().timeIntervalSince($0) } ?? 0

        return [
            "floorArea":    floorArea,
            "walls":        walls,
            "wallCount":    wallCount,
            "scanDuration": duration,
            "scanMode":     "lidar-native",
            "confidence":   floorArea > 0 ? "high" : "medium",
        ]
    }
}
