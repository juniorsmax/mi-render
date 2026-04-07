import Foundation
import Capacitor
import ARKit
import RoomPlan

/**
 * LiDARPlugin — Plugin Capacitor para escaneo LiDAR nativo
 * Agentes: Kai (iOS) + Ares (Escáner)
 *
 * Usa RoomPlan (iOS 16+) para escanear habitaciones automáticamente.
 * En dispositivos sin LiDAR usa ARKit para estimación básica.
 */
@objc(LiDARPlugin)
public class LiDARPlugin: CAPPlugin {

    private var scanSession: Any? = nil  // RoomCaptureSession (iOS 16+)
    private var savedCall: CAPPluginCall? = nil

    // ── isAvailable ─────────────────────────────────────────────────────────
    @objc func isAvailable(_ call: CAPPluginCall) {
        var result: [String: Any] = [:]

        if #available(iOS 16.0, *) {
            result["available"] = RoomCaptureSession.isSupported
            result["roomPlan"]  = RoomCaptureSession.isSupported
            result["arKit"]     = ARWorldTrackingConfiguration.isSupported
            result["lidar"]     = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        } else {
            result["available"] = false
            result["roomPlan"]  = false
            result["arKit"]     = ARWorldTrackingConfiguration.isSupported
            result["lidar"]     = false
        }

        call.resolve(result)
    }

    // ── startScan ────────────────────────────────────────────────────────────
    @objc func startScan(_ call: CAPPluginCall) {
        guard #available(iOS 16.0, *) else {
            call.reject("RoomPlan requiere iOS 16 o superior")
            return
        }

        guard RoomCaptureSession.isSupported else {
            call.reject("Este dispositivo no tiene LiDAR")
            return
        }

        savedCall = call

        DispatchQueue.main.async {
            self.presentRoomScan()
        }
    }

    // ── stopScan ─────────────────────────────────────────────────────────────
    @objc func stopScan(_ call: CAPPluginCall) {
        if #available(iOS 16.0, *) {
            if let session = scanSession as? RoomCaptureSession {
                session.stop()
            }
        }
        call.resolve(["stopped": true])
    }

    // ── Presentar UI de RoomPlan ─────────────────────────────────────────────
    @available(iOS 16.0, *)
    private func presentRoomScan() {
        let controller = RoomScanViewController()
        controller.delegate = self
        controller.modalPresentationStyle = .fullScreen

        self.bridge?.viewController?.present(controller, animated: true)
    }
}

// ── Delegate para recibir resultado del scan ─────────────────────────────────
@available(iOS 16.0, *)
extension LiDARPlugin: RoomScanDelegate {
    func roomScanDidComplete(room: CapturedRoom?) {
        guard let call = savedCall else { return }

        if let room = room {
            let result = buildRoomResult(room)
            call.resolve(result)
        } else {
            call.reject("Escaneo cancelado o sin datos")
        }

        savedCall = nil
    }

    func roomScanDidFail(error: Error) {
        savedCall?.reject("Error en escaneo: \(error.localizedDescription)")
        savedCall = nil
    }

    // ── Convertir CapturedRoom a diccionario JSON ────────────────────────────
    @available(iOS 16.0, *)
    private func buildRoomResult(_ room: CapturedRoom) -> [String: Any] {
        // Calcular área del suelo aproximada
        var floorArea: Float = 0
        for surface in room.floors {
            let d = surface.dimensions
            floorArea += d.x * d.z
        }

        // Paredes
        var walls: [[String: Any]] = []
        for wall in room.walls {
            walls.append([
                "width":     wall.dimensions.x,
                "height":    wall.dimensions.y,
                "confidence": confidenceLabel(wall.confidence),
            ])
        }

        // Puertas y ventanas
        var doors: [[String: Any]] = []
        for door in room.doors {
            doors.append([
                "width":  door.dimensions.x,
                "height": door.dimensions.y,
            ])
        }

        var windows: [[String: Any]] = []
        for window in room.windows {
            windows.append([
                "width":  window.dimensions.x,
                "height": window.dimensions.y,
            ])
        }

        return [
            "floorArea":  floorArea,
            "walls":      walls,
            "doors":      doors,
            "windows":    windows,
            "wallCount":  room.walls.count,
            "confidence": "high",
            "scanMode":   "lidar-native",
        ]
    }

    private func confidenceLabel(_ confidence: CapturedRoom.Surface.Confidence) -> String {
        switch confidence {
        case .high:   return "high"
        case .medium: return "medium"
        case .low:    return "low"
        @unknown default: return "unknown"
        }
    }
}

// ── Protocolo delegate ────────────────────────────────────────────────────────
protocol RoomScanDelegate: AnyObject {
    @available(iOS 16.0, *)
    func roomScanDidComplete(room: CapturedRoom?)
    func roomScanDidFail(error: Error)
}

// ── ViewController del escáner ────────────────────────────────────────────────
@available(iOS 16.0, *)
class RoomScanViewController: UIViewController, RoomCaptureSessionDelegate {

    weak var delegate: RoomScanDelegate?
    private var captureSession: RoomCaptureSession!
    private var captureView: RoomCaptureView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        captureSession = RoomCaptureSession()
        captureView    = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        captureView.captureSession = captureSession
        captureSession.delegate    = self

        view.addSubview(captureView)
        addCloseButton()
        addDoneButton()
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

    // ── Botón Cerrar ─────────────────────────────────────────────────────────
    private func addCloseButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("✕", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        btn.layer.cornerRadius = 20
        btn.frame = CGRect(x: 20, y: 60, width: 40, height: 40)
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(btn)
    }

    // ── Botón Listo ──────────────────────────────────────────────────────────
    private func addDoneButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("Listo", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.tintColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        btn.layer.cornerRadius = 20
        btn.frame = CGRect(x: UIScreen.main.bounds.width - 100, y: 60, width: 80, height: 40)
        btn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(btn)
    }

    @objc private func closeTapped() {
        captureSession.stop()
        dismiss(animated: true)
        delegate?.roomScanDidComplete(room: nil)
    }

    @objc private func doneTapped() {
        captureSession.stop()
    }

    // ── RoomCaptureSessionDelegate ────────────────────────────────────────────
    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.dismiss(animated: true)
                self.delegate?.roomScanDidFail(error: error)
            }
            return
        }

        // Procesar y generar modelo final
        let processor = RoomBuilder(options: [.beautifyObjects])
        Task {
            do {
                let room = try await processor.capturedRoom(from: data)
                await MainActor.run {
                    self.dismiss(animated: true)
                    self.delegate?.roomScanDidComplete(room: room)
                }
            } catch {
                await MainActor.run {
                    self.dismiss(animated: true)
                    self.delegate?.roomScanDidFail(error: error)
                }
            }
        }
    }
}
