import Foundation
import Capacitor
import ARKit

/**
 * LiDARPlugin — RoomPlan para mi-render
 * Usa RoomCaptureView (Apple RoomPlan API, iOS 16+, requiere LiDAR)
 * Fallback: ARKit básico para dispositivos sin LiDAR
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
                "scanMode":   hasLiDAR ? "roomplan" : "arkit",
                "iosVersion": UIDevice.current.systemVersion,
            ])
        } else {
            call.resolve([
                "available":  false,
                "lidar":      false,
                "roomPlan":   false,
                "arKit":      hasARKit,
                "scanMode":   "unsupported",
                "iosVersion": UIDevice.current.systemVersion,
            ])
        }
    }

    // ── startScan ────────────────────────────────────────────────────────────
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

        // Área del suelo
        let floorArea = room.floors.reduce(Float(0)) { acc, floor in
            acc + floor.dimensions.x * floor.dimensions.z
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

    private func confidenceString(_ c: CapturedRoom.Surface.Confidence) -> String {
        switch c {
        case .high:   return "high"
        case .medium: return "medium"
        case .low:    return "low"
        @unknown default: return "unknown"
        }
    }
}
