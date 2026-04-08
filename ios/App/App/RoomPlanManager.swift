// RoomPlanManager.swift
// Escaneo estructural automático con RoomPlan framework.
// Genera paredes, puertas, ventanas, aberturas y dimensiones.
// Requiere iOS 16+ y dispositivo con LiDAR.

import RoomPlan
import simd

@available(iOS 16.0, *)
class RoomPlanManager: NSObject {

    static let shared = RoomPlanManager()

    var captureSession = RoomCaptureSession()
    var lastCapturedRoom: CapturedRoom?

    var onRoomUpdated: ((CapturedRoom) -> Void)?
    var onScanComplete: ((CapturedRoom) -> Void)?

    override init() {
        super.init()
        captureSession.delegate = self
    }

    // MARK: - Iniciar escaneo

    func startScanning() {
        let configuration = RoomCaptureSession.Configuration()
        captureSession.run(configuration: configuration)
    }

    // MARK: - Detener escaneo

    func stopScanning() {
        captureSession.stop()
    }

    // MARK: - Exportar a USDZ

    func exportRoom(to url: URL) throws {
        guard let room = lastCapturedRoom else { return }
        try room.export(to: url)
    }

    // MARK: - Datos de la habitación

    func roomData() -> CapturedRoom? {
        return lastCapturedRoom
    }
}

// MARK: - RoomCaptureSessionDelegate

@available(iOS 16.0, *)
extension RoomPlanManager: RoomCaptureSessionDelegate {

    func captureSession(_ session: RoomCaptureSession,
                        didUpdate room: CapturedRoom) {
        lastCapturedRoom = room
        onRoomUpdated?(room)
    }

    func captureSession(_ session: RoomCaptureSession,
                        didEndWith data: CapturedRoomData,
                        error: Error?) {
        if let error = error {
            print("RoomPlan error: \(error.localizedDescription)")
            return
        }

        let request = RoomBuilder(options: [.beautifyObjects])
        Task {
            if let room = try? await request.capturedRoom(from: data) {
                self.lastCapturedRoom = room
                self.onScanComplete?(room)
            }
        }
    }
}

// Métricas calculadas exclusivamente en RoomPlanViewController.buildResult()
// RoomPlanManager actúa solo como almacenamiento de CapturedRoom.
