// RoomPlanManager.swift
// Escaneo estructural automático con RoomPlan framework.
// Genera paredes, puertas, ventanas, aberturas y dimensiones.
// Requiere iOS 16+ y dispositivo con LiDAR.

import RoomPlan

@available(iOS 16.0, *)
class RoomPlanManager: NSObject {

    static let shared = RoomPlanManager()

    var captureSession = RoomCaptureSession()
    private(set) var lastCapturedRoom: CapturedRoom?

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

    func roomData() -> RoomData? {
        guard let room = lastCapturedRoom else { return nil }
        return RoomData(from: room)
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

// MARK: - Modelo de datos extraído de CapturedRoom

@available(iOS 16.0, *)
struct RoomData {

    let areaSqM: Float
    let perimeterM: Float
    let walls: [WallData]
    let doors: [OpeningData]
    let windows: [OpeningData]

    init(from room: CapturedRoom) {

        var perimeter: Float = 0
        var wallsData: [WallData] = []

        for wall in room.walls {
            let w = wall.dimensions.x
            let h = wall.dimensions.y
            perimeter += w
            wallsData.append(WallData(
                width:  w,
                height: h,
                transform: wall.transform
            ))
        }

        var area: Float = 0
        if let maxWall = room.walls.max(by: { $0.dimensions.x < $1.dimensions.x }),
           let perpWall = room.walls.max(by: { $0.dimensions.z < $1.dimensions.z }) {
            area = maxWall.dimensions.x * perpWall.dimensions.z
        }

        self.areaSqM    = area
        self.perimeterM = perimeter
        self.walls      = wallsData
        self.doors      = room.doors.map   { OpeningData(dimensions: $0.dimensions, transform: $0.transform) }
        self.windows    = room.windows.map { OpeningData(dimensions: $0.dimensions, transform: $0.transform) }
    }
}

struct WallData {
    let width: Float
    let height: Float
    let transform: simd_float4x4
}

struct OpeningData {
    let dimensions: simd_float3
    let transform: simd_float4x4
}
