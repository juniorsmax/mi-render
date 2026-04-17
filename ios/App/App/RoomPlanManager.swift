// RoomPlanManager.swift
// Escaneo estructural automático con RoomPlan framework.
// Genera paredes, puertas, ventanas, aberturas y dimensiones.
// Requiere iOS 16+ y dispositivo con LiDAR.

import UIKit
import RoomPlan
import simd

@available(iOS 16.0, *)
class RoomPlanManager: NSObject {

    static let shared = RoomPlanManager()

    var captureSession = RoomCaptureSession()
    var lastCapturedRoom: CapturedRoom?

    /// Footprint 2D calculado desde ARKit mesh (disponible tras buildFloorFootprint())
    private(set) var floorFootprint: FloorFootprint?

    /// Callback cuando el footprint cambia (p.ej. durante el escaneo)
    var onFootprintUpdated: ((FloorFootprint) -> Void)?

    var onRoomUpdated: ((CapturedRoom) -> Void)?
    var onScanComplete: ((CapturedRoom) -> Void)?

    /// Habilita actualizaciones en tiempo real del SceneGraph durante el escaneo.
    var enableRealtimeSceneGraph: Bool = true

    override init() {
        super.init()
        captureSession.delegate = self
    }

    // MARK: - Iniciar escaneo

    func startScanning() {
        floorFootprint = nil
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

    // MARK: - Generar footprint 2D desde mesh ARKit

    /// Ejecuta el pipeline completo: vértices .floor → ConvexHull → Douglas-Peucker → FloorFootprint
    /// Se llama automáticamente al finalizar el escaneo.
    /// También puede llamarse manualmente para actualizar durante el escaneo.
    func buildFloorFootprint(simplifyEpsilon: Float = 0.05) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let footprint = FloorFootprintBuilder.build(simplifyEpsilon: simplifyEpsilon) else {
                return
            }
            DispatchQueue.main.async {
                self.floorFootprint = footprint
                self.onFootprintUpdated?(footprint)
            }
        }
    }

    // MARK: - Renderizar imagen del plano planta

    /// Genera UIImage del plano combinando footprint + paredes RoomPlan (si disponibles)
    func renderFloorPlan(size: CGSize = CGSize(width: 800, height: 800)) -> UIImage {
        if let room = lastCapturedRoom, let fp = floorFootprint {
            return PlanRenderer.shared.renderCombined(room: room, footprint: fp, size: size)
        } else if let fp = floorFootprint {
            return PlanRenderer.shared.renderFloorFootprint(fp, size: size)
        } else if let room = lastCapturedRoom {
            return PlanRenderer.shared.renderImage(from: room, size: size)
        }
        return UIImage()
    }
}

// MARK: - RoomCaptureSessionDelegate

@available(iOS 16.0, *)
extension RoomPlanManager: RoomCaptureSessionDelegate {

    func captureSession(_ session: RoomCaptureSession,
                        didUpdate room: CapturedRoom) {
        lastCapturedRoom = room

        // Actualizar SceneGraph en tiempo real
        if enableRealtimeSceneGraph {
            SceneGraphManager.shared.buildGraph(from: room)
        }

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

                // Grafo final con modelo refinado
                SceneGraphManager.shared.buildGraph(from: room)
                SceneGraphManager.shared.saveGraph()

                // Generar footprint desde el mesh ARKit capturado durante el escaneo
                self.buildFloorFootprint()
                self.onScanComplete?(room)
            }
        }
    }
}

// Métricas calculadas exclusivamente en RoomPlanViewController.buildResult()
// RoomPlanManager actúa solo como almacenamiento de CapturedRoom.
