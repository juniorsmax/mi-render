// ScanViewerView.swift
// Visor 3D de escaneos LiDAR guardados.
// Carga mesh.usdz desde Documents/projects/{uuid}/ y permite navegar
// con gestos en dos modos:
//
//   .orbit (por defecto)
//     1 dedo  → órbita (azimuth + elevation)
//     pinch   → zoom (radio)
//     2 dedos → paneo del pivote
//
//   .firstPerson
//     1 dedo  → mirar (yaw + pitch)
//     pinch   → avanzar / retroceder
//     2 dedos → desplazamiento lateral + vertical (strafe)
//     doble toque → teleportar al punto pulsado (si hay mesh cargado)
//
// Usa RealityKit ARView en modo .nonAR — sin sesión ARKit activa.

import RealityKit
import ARKit
import UIKit
import Combine
import simd

// MARK: - NavigationMode

enum NavigationMode {
    /// Cámara orbital alrededor de un pivote central.
    case orbit
    /// Cámara en primera persona libre dentro de la malla.
    case firstPerson
}

// MARK: - ScanViewerView

class ScanViewerView: UIView {

    // MARK: - Propiedades

    private(set) var arView: ARView!

    /// AnchorEntity raíz que contiene el modelo cargado.
    private var rootAnchor: AnchorEntity?

    /// ModelEntity del mesh cargado.
    private(set) var modelEntity: ModelEntity?

    /// Centro del bounding box del modelo — pivote de órbita.
    private var modelCenter: SIMD3<Float> = .zero

    // MARK: - Modo de navegación

    private(set) var navigationMode: NavigationMode = .orbit

    /// AnchorEntity virtual que marca la posición de la cámara en primera persona.
    private(set) var cameraAnchor: AnchorEntity?

    /// AnchorEntity con PerspectiveCamera activo — controla la vista en ambos modos.
    private var perspCameraAnchor: AnchorEntity?

    // MARK: - Estado de cámara orbital

    private var azimuth:   Float = 0.30
    private var elevation: Float = 0.45
    private var radius:    Float = 3.0

    private let minRadius:    Float = 0.3
    private let maxRadius:    Float = 20.0
    private let minElevation: Float = -.pi / 2 + 0.05
    private let maxElevation: Float =  .pi / 2 - 0.05

    private var panStartAzimuth:   Float = 0
    private var panStartElevation: Float = 0
    private var pinchStartRadius:  Float = 3.0

    // MARK: - Estado de cámara primera persona

    /// Posición del observador en espacio mundo.
    private var fpPosition: SIMD3<Float> = SIMD3(0, 1.7, 0)

    /// Rotación horizontal (yaw) en radianes.
    private var fpYaw:   Float = 0

    /// Rotación vertical (pitch) en radianes.
    private var fpPitch: Float = 0

    private let fpMinPitch: Float = -.pi / 2 + 0.05
    private let fpMaxPitch: Float =  .pi / 2 - 0.05

    /// Sensibilidad de mirada (rad / punto de pantalla).
    var lookSensitivity:  Float = 0.004

    /// Velocidad de desplazamiento al hacer pinch (m / delta escala).
    var moveSensitivity:  Float = 4.0

    /// Sensibilidad del strafe con 2 dedos (m / punto).
    var strafeSensitivity: Float = 0.006

    // Valores de inicio de gesto primera persona
    private var fpPanStartYaw:   Float = 0
    private var fpPanStartPitch: Float = 0
    private var fpPinchStartPos: SIMD3<Float> = .zero

    // MARK: - Estado de carga

    private(set) var isLoading = false
    var onLoadComplete: ((Bool) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = UIColor(white: 0.08, alpha: 1)

        arView = ARView(frame: bounds, cameraMode: .nonAR,
                        automaticallyConfigureSession: false)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.environment.background = .color(UIColor(white: 0.1, alpha: 1))
        addSubview(arView)

        setupLighting()
        setupCamera()
        setupGestures()
    }

    // MARK: - Iluminación

    private func setupLighting() {
        arView.environment.lighting.intensityExponent = 1.0

        let dirLight = DirectionalLight()
        dirLight.light.color     = .white
        dirLight.light.intensity = 3000
        dirLight.shadow          = DirectionalLightComponent.Shadow(maximumDistance: 20,
                                                                     depthBias: 0.05)
        let lightAnchor = AnchorEntity(world: SIMD3(2, 4, 3))
        lightAnchor.addChild(dirLight)
        arView.scene.addAnchor(lightAnchor)

        let fillLight = DirectionalLight()
        fillLight.light.color     = UIColor(red: 0.7, green: 0.8, blue: 1.0, alpha: 1)
        fillLight.light.intensity = 800
        let fillAnchor = AnchorEntity(world: SIMD3(-3, 1, -2))
        fillAnchor.addChild(fillLight)
        arView.scene.addAnchor(fillAnchor)
    }

    // MARK: - Cámara

    private func setupCamera() {
        // RealityKit .nonAR: la cámara se controla via PerspectiveCamera entity.
        // arView.cameraTransform es get-only; hay que mover el anchor.
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 60
        let anchor = AnchorEntity(world: .zero)
        anchor.name = "perspCamera"
        anchor.addChild(cam)
        arView.scene.addAnchor(anchor)
        perspCameraAnchor = anchor
        updateCameraTransform()
    }

    private func updateCameraTransform() {
        switch navigationMode {
        case .orbit:
            updateOrbitCamera()
        case .firstPerson:
            updateFirstPersonCamera()
        }
    }

    // MARK: Cámara orbital

    private func updateOrbitCamera() {
        let x = radius * cos(elevation) * sin(azimuth)
        let y = radius * sin(elevation)
        let z = radius * cos(elevation) * cos(azimuth)
        let camPos = modelCenter + SIMD3<Float>(x, y, z)

        let forward = simd_normalize(modelCenter - camPos)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right   = simd_normalize(simd_cross(forward, worldUp))
        let up      = simd_cross(right, forward)

        var m = simd_float4x4(1)
        m.columns.0 = SIMD4( right.x,   right.y,   right.z,   0)
        m.columns.1 = SIMD4( up.x,       up.y,       up.z,     0)
        m.columns.2 = SIMD4(-forward.x, -forward.y, -forward.z, 0)
        m.columns.3 = SIMD4( camPos.x,   camPos.y,   camPos.z,  1)

        perspCameraAnchor?.move(to: Transform(matrix: m), relativeTo: nil)
    }

    // MARK: Cámara primera persona

    private func updateFirstPersonCamera() {
        // Dirección de mirada desde yaw + pitch
        let cosP    = cos(fpPitch)
        let forward = SIMD3<Float>( sin(fpYaw) * cosP,
                                    sin(fpPitch),
                                   -cos(fpYaw) * cosP)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right   = simd_normalize(simd_cross(forward, worldUp))
        let up      = simd_cross(right, forward)

        var m = simd_float4x4(1)
        m.columns.0 = SIMD4( right.x,   right.y,   right.z,   0)
        m.columns.1 = SIMD4( up.x,       up.y,       up.z,     0)
        m.columns.2 = SIMD4(-forward.x, -forward.y, -forward.z, 0)
        m.columns.3 = SIMD4( fpPosition.x, fpPosition.y, fpPosition.z, 1)

        perspCameraAnchor?.move(to: Transform(matrix: m), relativeTo: nil)

        // Actualizar anchor virtual de cámara (marcador de posición FP)
        cameraAnchor?.move(to: Transform(matrix: m), relativeTo: nil)
    }

    // MARK: - Gestos

    private func setupGestures() {
        // 1 dedo
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1

        // Pinch
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

        // 2 dedos
        let twoFingerPan = UIPanGestureRecognizer(target: self,
                                                   action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2

        // Doble toque — primera persona: teleportar
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        pan.require(toFail: twoFingerPan)

        arView.addGestureRecognizer(pan)
        arView.addGestureRecognizer(pinch)
        arView.addGestureRecognizer(twoFingerPan)
        arView.addGestureRecognizer(doubleTap)
    }

    // MARK: Pan 1 dedo

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch navigationMode {
        case .orbit:
            handleOrbitPan(gesture)
        case .firstPerson:
            handleFPLook(gesture)
        }
    }

    /// Órbita: azimuth + elevation.
    private func handleOrbitPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            panStartAzimuth   = azimuth
            panStartElevation = elevation
        case .changed:
            let t = gesture.translation(in: arView)
            let s: Float = 0.005
            azimuth   = panStartAzimuth   + Float(t.x) * s
            elevation = (panStartElevation - Float(t.y) * s)
                .clamped(to: minElevation...maxElevation)
            updateCameraTransform()
        default:
            break
        }
    }

    /// Primera persona: mirar (yaw + pitch).
    private func handleFPLook(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            fpPanStartYaw   = fpYaw
            fpPanStartPitch = fpPitch
        case .changed:
            let t = gesture.translation(in: arView)
            fpYaw   = fpPanStartYaw   + Float(t.x) * lookSensitivity
            fpPitch = (fpPanStartPitch - Float(t.y) * lookSensitivity)
                .clamped(to: fpMinPitch...fpMaxPitch)
            updateCameraTransform()
        default:
            break
        }
    }

    // MARK: Pinch

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch navigationMode {
        case .orbit:
            handleOrbitZoom(gesture)
        case .firstPerson:
            handleFPWalk(gesture)
        }
    }

    /// Órbita: zoom (radio).
    private func handleOrbitZoom(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartRadius = radius
        case .changed:
            radius = (pinchStartRadius / Float(gesture.scale))
                .clamped(to: minRadius...maxRadius)
            updateCameraTransform()
        default:
            break
        }
    }

    /// Primera persona: avanzar / retroceder según escala del pinch.
    private func handleFPWalk(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            fpPinchStartPos = fpPosition
        case .changed:
            // scale > 1 = separa dedos → avanzar; < 1 → retroceder
            let delta    = Float(gesture.scale - 1.0) * moveSensitivity
            let forward  = fpForwardVector()
            fpPosition   = fpPinchStartPos + forward * delta
            updateCameraTransform()
        default:
            break
        }
    }

    // MARK: Pan 2 dedos

    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        switch navigationMode {
        case .orbit:
            handleOrbitPivotPan(gesture)
        case .firstPerson:
            handleFPStrafe(gesture)
        }
    }

    /// Órbita: paneo del pivote.
    private func handleOrbitPivotPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let t = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)

        let s     = Float(0.002) * radius
        let right = simd_normalize(SIMD3<Float>(cos(azimuth), 0, -sin(azimuth)))
        let up    = SIMD3<Float>(0, 1, 0)

        modelCenter += right * (-Float(t.x) * s)
        modelCenter += up    * ( Float(t.y) * s)
        updateCameraTransform()
    }

    /// Primera persona: strafe lateral + vertical.
    private func handleFPStrafe(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let t = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)

        let right = fpRightVector()
        let up    = SIMD3<Float>(0, 1, 0)

        fpPosition += right * ( Float(t.x) * strafeSensitivity)
        fpPosition += up    * (-Float(t.y) * strafeSensitivity)
        updateCameraTransform()
    }

    // MARK: Doble toque — teleportar en primera persona

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard navigationMode == .firstPerson else { return }

        let point = gesture.location(in: arView)

        // Intentar ray-cast contra la malla cargada
        let results = arView.hitTest(point, query: .nearest, mask: .all)
        if let hit = results.first {
            let worldPos = hit.position
            // Mantener altura del observador, teletransportar XZ
            fpPosition = SIMD3(worldPos.x, fpPosition.y, worldPos.z)
            updateCameraTransform()
        }
    }

    // MARK: - Vectores auxiliares primera persona

    private func fpForwardVector() -> SIMD3<Float> {
        SIMD3<Float>(sin(fpYaw), 0, -cos(fpYaw))   // plano XZ (sin componente Y)
    }

    private func fpRightVector() -> SIMD3<Float> {
        SIMD3<Float>(cos(fpYaw), 0, sin(fpYaw))
    }

    private func fpLookVector() -> SIMD3<Float> {
        let cosP = cos(fpPitch)
        return SIMD3<Float>(sin(fpYaw) * cosP, sin(fpPitch), -cos(fpYaw) * cosP)
    }

    // MARK: - API pública

    /// Cambia el modo de navegación.
    /// Al entrar en .firstPerson crea el anchor virtual de cámara.
    /// Al salir a .orbit lo elimina.
    func setNavigationMode(_ mode: NavigationMode) {
        navigationMode = mode

        switch mode {
        case .firstPerson:
            // Crear anchor virtual de cámara si no existe
            if cameraAnchor == nil {
                let anchor = AnchorEntity(world: fpPosition)
                anchor.name = "virtualCamera"
                arView.scene.addAnchor(anchor)
                cameraAnchor = anchor
            }
            // Posicionar dentro del modelo si ya está cargado
            if let bbox = modelEntity?.visualBounds(relativeTo: nil) {
                fpPosition = SIMD3(bbox.center.x, bbox.min.y + 1.7, bbox.center.z)
                fpYaw   = 0
                fpPitch = 0
            }
            updateCameraTransform()

        case .orbit:
            cameraAnchor?.removeFromParent()
            cameraAnchor = nil
            updateCameraTransform()
        }
    }

    /// Mueve la cámara primera persona a una posición específica con animación.
    func walkTo(position: SIMD3<Float>, duration: TimeInterval = 0.4) {
        guard navigationMode == .firstPerson else { return }

        let steps    = max(Int(duration * 60), 1)
        let start    = fpPosition
        let delta    = position - start
        var step     = 0

        // Interpolación lineal en pantalla (no usa async/await — compatible iOS 15)
        let link = CADisplayLink.init(target: DisplayLinkHelper {
            step += 1
            let t = Float(step) / Float(steps)
            self.fpPosition = start + delta * t
            self.updateCameraTransform()
            if step >= steps { $0.invalidate() }
        }, selector: #selector(DisplayLinkHelper.tick(_:)))
        link.add(to: .main, forMode: .common)
    }

    /// Carga mesh.usdz del proyecto indicado.
    func loadMesh(projectId: UUID, completion: ((Bool) -> Void)? = nil) {
        let docs    = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let usdzURL = docs
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("mesh.usdz")
        loadMesh(from: usdzURL, completion: completion)
    }

    /// Carga un .usdz desde una URL arbitraria.
    func loadMesh(from url: URL, completion: ((Bool) -> Void)? = nil) {
        guard !isLoading else { return }
        isLoading = true
        clearScene()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let entity = try Entity.load(contentsOf: url)
                DispatchQueue.main.async {
                    self.attachModel(entity: entity)
                    self.isLoading = false
                    completion?(true)
                    self.onLoadComplete?(true)
                }
            } catch {
                print("[ScanViewerView] Error cargando \(url.lastPathComponent): \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    completion?(false)
                    self.onLoadComplete?(false)
                }
            }
        }
    }

    // MARK: - Attach model a la escena

    private func attachModel(entity: Entity) {
        let anchor = AnchorEntity(world: .zero)
        let bbox   = entity.visualBounds(relativeTo: nil)
        let center = bbox.center
        entity.position = -center

        let diagonal = simd_length(bbox.max - bbox.min)
        radius       = max(diagonal * 1.5, 0.5)
        pinchStartRadius = radius
        modelCenter  = .zero

        if let model = entity as? ModelEntity {
            anchor.addChild(model)
            modelEntity = model
        } else {
            anchor.addChild(entity)
            modelEntity = findModelEntity(in: entity)
        }

        rootAnchor = anchor
        arView.scene.addAnchor(anchor)
        updateCameraTransform()
        print("[ScanViewerView] modelo cargado — diagonal: \(String(format: "%.2f", diagonal)) m")
    }

    // MARK: - Añadir ModelEntity manualmente

    func addModelEntity(_ model: ModelEntity) {
        clearScene()
        let anchor = AnchorEntity(world: .zero)
        let bbox   = model.visualBounds(relativeTo: nil)
        model.position = -bbox.center
        radius = max(simd_length(bbox.max - bbox.min) * 1.5, 0.5)
        modelCenter = .zero
        anchor.addChild(model)
        rootAnchor  = anchor
        modelEntity = model
        arView.scene.addAnchor(anchor)
        updateCameraTransform()
    }

    // MARK: - Resetear cámara

    func resetCamera() {
        switch navigationMode {
        case .orbit:
            azimuth   = 0.30
            elevation = 0.45
            if let bbox = modelEntity?.visualBounds(relativeTo: nil) {
                radius = max(simd_length(bbox.max - bbox.min) * 1.5, 0.5)
            }
            modelCenter = .zero

        case .firstPerson:
            if let bbox = modelEntity?.visualBounds(relativeTo: nil) {
                fpPosition = SIMD3(bbox.center.x, bbox.min.y + 1.7, bbox.center.z)
            } else {
                fpPosition = SIMD3(0, 1.7, 0)
            }
            fpYaw   = 0
            fpPitch = 0
        }
        updateCameraTransform()
    }

    // MARK: - Limpiar escena

    func clearScene() {
        rootAnchor?.removeFromParent()
        rootAnchor  = nil
        modelEntity = nil
        cameraAnchor?.removeFromParent()
        cameraAnchor = nil
    }

    // MARK: - Helper

    private func findModelEntity(in entity: Entity, maxDepth: Int = 50) -> ModelEntity? {
        guard maxDepth > 0 else { return nil }
        if let model = entity as? ModelEntity { return model }
        for child in entity.children {
            if let found = findModelEntity(in: child, maxDepth: maxDepth - 1) { return found }
        }
        return nil
    }
}

// MARK: - DisplayLinkHelper (para walkTo sin async/await)

private final class DisplayLinkHelper: NSObject {
    private let block: (CADisplayLink) -> Void
    init(_ block: @escaping (CADisplayLink) -> Void) { self.block = block }
    @objc func tick(_ link: CADisplayLink) { block(link) }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
