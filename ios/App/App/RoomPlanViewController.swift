// RoomPlanViewController.swift
// Controlador de escaneo de habitación con RoomPlan.
// Apple proporciona RoomCaptureView con visualización de malla 3D integrada.
// iOS 16+ obligatorio.

import UIKit
import RoomPlan
import ARKit

@available(iOS 16.0, *)
class RoomPlanViewController: UIViewController {

    var onResult: (([String: Any]?) -> Void)?

    private var captureView: RoomCaptureView!
    private var captureSession: RoomCaptureSession!

    // ── Ciclo de vida ────────────────────────────────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Apple's built-in RoomCaptureView renders the live 3D mesh
        captureView = RoomCaptureView(frame: view.bounds)
        captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(captureView)

        captureSession = captureView.captureSession
        captureSession.delegate = self

        setupButtons()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stop()
    }

    // ── Botones ──────────────────────────────────────────────────────────────

    private func setupButtons() {
        // Done
        let doneBtn = makeButton(title: "Listo", accent: true)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        view.addSubview(doneBtn)
        NSLayoutConstraint.activate([
            doneBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            doneBtn.widthAnchor.constraint(equalToConstant: 180),
            doneBtn.heightAnchor.constraint(equalToConstant: 52),
        ])

        // Cancel
        let cancelBtn = makeButton(title: "Cancelar", accent: false)
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)
        NSLayoutConstraint.activate([
            cancelBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])
    }

    private func makeButton(title: String, accent: Bool) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        if accent {
            btn.backgroundColor = UIColor(red: 0.42, green: 0.56, blue: 1.0, alpha: 1.0)
            btn.setTitleColor(.white, for: .normal)
            btn.layer.cornerRadius = 14
        } else {
            btn.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        }
        return btn
    }

    // ── Acciones ─────────────────────────────────────────────────────────────

    @objc private func doneTapped() {
        captureSession.stop()
    }

    @objc private func cancelTapped() {
        captureSession.stop()
        dismiss(animated: true)
        onResult?(nil)
    }

    // ── Resultado ────────────────────────────────────────────────────────────

    private func buildResult(from room: CapturedRoom) -> [String: Any] {
        var floorArea: Float = 0
        var wallArea:  Float = 0
        var windowArea: Float = 0
        var perimeterCalc: Float = 0
        var avgHeight: Float = 2.5

        for floor in room.floors {
            floorArea += floor.dimensions.x * floor.dimensions.y
        }
        for wall in room.walls {
            wallArea     += wall.dimensions.x * wall.dimensions.y
            perimeterCalc += wall.dimensions.x
        }
        for window in room.windows {
            windowArea += window.dimensions.x * window.dimensions.y
        }
        if let h = room.walls.first?.dimensions.y { avgHeight = h }

        // Fallback: if RoomPlan detected no floors (some rooms), estimate from walls
        if floorArea < 0.1 && wallArea > 0 {
            // rough room area estimate: perimeter / 4 squared
            let side = perimeterCalc / 4.0
            floorArea = side * side
        }

        let wallsData: [[String: Any]] = room.walls.map { w in
            ["width": w.dimensions.x, "height": w.dimensions.y,
             "confidence": "\(w.confidence)"]
        }
        let doorsData: [[String: Any]] = room.doors.map { d in
            ["width": d.dimensions.x, "height": d.dimensions.y, "isOpen": d.isOpen]
        }
        let windowsData: [[String: Any]] = room.windows.map { w in
            ["width": w.dimensions.x, "height": w.dimensions.y]
        }
        let openingsData: [[String: Any]] = room.openings.map { o in
            ["width": o.dimensions.x, "height": o.dimensions.y]
        }

        return [
            "areaSqM":    floorArea,
            "floorArea":  floorArea,
            "wallArea":   wallArea,
            "windowArea": windowArea,
            "volume":     floorArea * avgHeight,
            "perimeterM": perimeterCalc,
            "avgHeight":  avgHeight,
            "walls":      wallsData,
            "doors":      doorsData,
            "windows":    windowsData,
            "openings":   openingsData,
            "wallCount":  room.walls.count,
            "confidence": "high",
        ]
    }
}

// ── RoomCaptureSessionDelegate ───────────────────────────────────────────────

@available(iOS 16.0, *)
extension RoomPlanViewController: RoomCaptureSessionDelegate {

    func captureSession(_ session: RoomCaptureSession,
                        didUpdate room: CapturedRoom) {
        RoomPlanManager.shared.lastCapturedRoom = room
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error = error {
            print("RoomPlanViewController error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.dismiss(animated: true)
                self.onResult?(nil)
            }
            return
        }

        let builder = RoomBuilder(options: [.beautifyObjects])
        Task { @MainActor in
            if let room = try? await builder.capturedRoom(from: data) {
                RoomPlanManager.shared.lastCapturedRoom = room
                let result = self.buildResult(from: room)
                self.dismiss(animated: true)
                self.onResult?(result)
            } else {
                self.dismiss(animated: true)
                self.onResult?(nil)
            }
        }
    }
}
