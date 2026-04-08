import Foundation
import Capacitor
import ARKit

/**
 * LiDARPlugin — Plugin Capacitor para escaneo LiDAR / ARKit
 * Agentes: Kai (iOS) + Ares (Escáner)
 *
 * Estrategia:
 *  - iPhone con LiDAR (12 Pro+): ARKit sceneReconstruction .mesh → alta precisión
 *  - iPhone sin LiDAR: ARKit planeDetection → precisión media
 *
 * RoomPlan (iOS 16+) se carga dinámicamente cuando está disponible.
 * Registrado via LiDARPlugin.m con CAP_PLUGIN macro.
 */
@objc(LiDARPlugin)
public class LiDARPlugin: CAPPlugin {

    private var pendingCall: CAPPluginCall?

    // ── isAvailable ──────────────────────────────────────────────────────────
    @objc func isAvailable(_ call: CAPPluginCall) {
        let hasLiDAR   = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let hasARKit   = ARWorldTrackingConfiguration.isSupported
        let iosVersion = UIDevice.current.systemVersion

        var roomPlan = false
        if #available(iOS 16.0, *) {
            roomPlan = hasLiDAR
        }

        call.resolve([
            "available":   hasLiDAR || hasARKit,
            "lidar":       hasLiDAR,
            "roomPlan":    roomPlan,
            "arKit":       hasARKit,
            "iosVersion":  iosVersion,
            "scanMode":    hasLiDAR ? "lidar" : "arkit",
        ])
    }

    // ── startScan ────────────────────────────────────────────────────────────
    @objc func startScan(_ call: CAPPluginCall) {
        guard ARWorldTrackingConfiguration.isSupported else {
            call.reject("ARKit no disponible en este dispositivo")
            return
        }

        pendingCall = call

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let vc = ARScanViewController()
            vc.hasLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
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
        pendingCall?.reject("Escaneo detenido")
        pendingCall = nil
        call.resolve(["stopped": true])
    }
}

// ── ViewController de escaneo AR ──────────────────────────────────────────────
class ARScanViewController: UIViewController, ARSessionDelegate {

    var hasLiDAR = false
    var onComplete: (([String: Any]?) -> Void)?

    private var arSession   = ARSession()
    private var sceneView   = ARSCNView()
    private var scanTimer: Timer?
    private var scanSeconds = 0
    private var timerLabel  = UILabel()
    private var statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSceneView()
        setupHUD()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startARSession()
        startTimer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arSession.pause()
        scanTimer?.invalidate()
    }

    // ── AR Session ───────────────────────────────────────────────────────────
    private func setupSceneView() {
        sceneView.frame = view.bounds
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.session = arSession
        sceneView.automaticallyUpdatesLighting = true
        sceneView.delegate = nil
        view.addSubview(sceneView)

        arSession.delegate = self
    }

    private func startARSession() {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        if hasLiDAR {
            config.sceneReconstruction = .mesh
            config.frameSemantics = .sceneDepth
        }

        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // ── HUD ──────────────────────────────────────────────────────────────────
    private func setupHUD() {
        let w = view.bounds.width
        let topInset = UIApplication.shared.windows.first?.safeAreaInsets.top ?? 44

        // Barra superior oscura
        let topBar = UIView(frame: CGRect(x: 0, y: 0, width: w, height: topInset + 60))
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.addSubview(topBar)

        // Botón cerrar
        let closeBtn = makeRoundBtn(title: "✕", x: 16, y: topInset + 10, size: 40)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        // Modo badge
        let modeBadge = UILabel(frame: CGRect(x: w/2 - 70, y: topInset + 10, width: 140, height: 36))
        modeBadge.text = hasLiDAR ? "⚡ LiDAR activo" : "📷 ARKit"
        modeBadge.textColor = hasLiDAR ? UIColor(red:0.2,green:0.83,blue:0.75,alpha:1) : UIColor(red:0.94,green:0.65,blue:0,alpha:1)
        modeBadge.font = .systemFont(ofSize: 13, weight: .bold)
        modeBadge.textAlignment = .center
        modeBadge.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        modeBadge.layer.cornerRadius = 18
        modeBadge.layer.masksToBounds = true
        view.addSubview(modeBadge)

        // Timer
        timerLabel.frame = CGRect(x: w - 70, y: topInset + 10, width: 54, height: 36)
        timerLabel.text = "0s"
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timerLabel.textAlignment = .center
        timerLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        timerLabel.layer.cornerRadius = 18
        timerLabel.layer.masksToBounds = true
        view.addSubview(timerLabel)

        // Instrucción
        statusLabel.frame = CGRect(x: 16, y: topInset + 64, width: w - 32, height: 36)
        statusLabel.text = "Mueve el iPhone por toda la habitación"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor(red:0.94,green:0.65,blue:0,alpha:0.2)
        statusLabel.layer.cornerRadius = 18
        statusLabel.layer.borderWidth = 1
        statusLabel.layer.borderColor = UIColor(red:0.94,green:0.65,blue:0,alpha:0.5).cgColor
        statusLabel.layer.masksToBounds = true
        view.addSubview(statusLabel)

        // Barra inferior
        let bottomInset = UIApplication.shared.windows.first?.safeAreaInsets.bottom ?? 34
        let barH: CGFloat = 100 + bottomInset
        let bottomBar = UIView(frame: CGRect(x: 0, y: view.bounds.height - barH, width: w, height: barH))
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.addSubview(bottomBar)

        // Botón Listo
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("✓  Listo", for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        doneBtn.setTitleColor(UIColor(red:0.94,green:0.65,blue:0,alpha:1), for: .normal)
        doneBtn.backgroundColor = UIColor(red:0.94,green:0.65,blue:0,alpha:0.15)
        doneBtn.layer.cornerRadius = 24
        doneBtn.layer.borderWidth = 1.5
        doneBtn.layer.borderColor = UIColor(red:0.94,green:0.65,blue:0,alpha:0.5).cgColor
        doneBtn.frame = CGRect(x: w/2 - 90, y: view.bounds.height - barH + 20, width: 180, height: 50)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)
    }

    private func makeRoundBtn(title: String, x: CGFloat, y: CGFloat, size: CGFloat) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        btn.layer.cornerRadius = size / 2
        btn.frame = CGRect(x: x, y: y, width: size, height: size)
        return btn
    }

    // ── Timer ─────────────────────────────────────────────────────────────────
    private func startTimer() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.scanSeconds += 1
            self.timerLabel.text = "\(self.scanSeconds)s"

            // Actualizar instrucción conforme pasa el tiempo
            if self.scanSeconds == 5  { self.statusLabel.text = "Apunta a las paredes y esquinas" }
            if self.scanSeconds == 12 { self.statusLabel.text = "Gira para capturar todos los ángulos" }
            if self.scanSeconds == 20 { self.statusLabel.text = "Puedes pulsar Listo cuando acabes" }
        }
    }

    // ── ARSessionDelegate ─────────────────────────────────────────────────────
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Actualizar conteo de planos detectados
        let planeCount = frame.anchors.filter { $0 is ARPlaneAnchor }.count
        if planeCount > 0 && scanSeconds < 5 {
            DispatchQueue.main.async {
                self.statusLabel.text = "\(planeCount) superficie\(planeCount > 1 ? "s" : "") detectada\(planeCount > 1 ? "s" : "") — sigue escaneando"
            }
        }
    }

    // ── Acciones ──────────────────────────────────────────────────────────────
    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onComplete?(nil)
        }
    }

    @objc private func doneTapped() {
        arSession.pause()
        scanTimer?.invalidate()
        let result = buildResult()
        dismiss(animated: true) { [weak self] in
            self?.onComplete?(result)
        }
    }

    // ── Construir resultado desde ARKit anchors ────────────────────────────────
    private func buildResult() -> [String: Any] {
        guard let frame = arSession.currentFrame else {
            return ["floorArea": 0, "walls": [], "scanMode": "arkit"]
        }

        var floorArea: Float  = 0
        var wallArea:  Float  = 0
        var walls: [[String: Any]] = []

        for anchor in frame.anchors {
            guard let plane = anchor as? ARPlaneAnchor else { continue }
            let ext = plane.planeExtent

            if plane.alignment == .horizontal && plane.classification == .floor {
                floorArea += ext.width * ext.height
            }
            if plane.alignment == .vertical {
                wallArea += ext.width * ext.height
                walls.append([
                    "width":  ext.width,
                    "height": ext.height,
                    "confidence": "medium",
                ])
            }
        }

        return [
            "floorArea":    floorArea,
            "walls":        walls,
            "wallCount":    walls.count,
            "wallArea":     wallArea,
            "scanDuration": scanSeconds,
            "scanMode":     hasLiDAR ? "lidar-native" : "arkit",
            "confidence":   floorArea > 0 ? "high" : "low",
        ]
    }
}
