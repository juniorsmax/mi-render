// ScanViewerView.swift
// Visor 3D de escaneos LiDAR guardados.
// Carga mesh.usdz desde Documents/projects/{uuid}/ y permite navegar
// con gestos: órbita (pan), zoom (pinch), rotación (rotación).
// Usa RealityKit ARView en modo .nonAR — sin sesión ARKit activa.

import RealityKit
import ARKit
import UIKit
import Combine
import simd

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

    // MARK: - Estado de cámara orbital

    private var azimuth:   Float = 0.30      // radianes horizontal
    private var elevation: Float = 0.45      // radianes vertical
    private var radius:    Float = 3.0       // distancia al pivote (metros)

    private let minRadius: Float = 0.3
    private let maxRadius: Float = 20.0
    private let minElevation: Float = -.pi / 2 + 0.05
    private let maxElevation: Float =  .pi / 2 - 0.05

    // Valores al comenzar el gesto
    private var panStartAzimuth:   Float = 0
    private var panStartElevation: Float = 0
    private var pinchStartRadius:  Float = 3.0

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

        // ARView en modo no-AR (visor puro 3D)
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

        // Luz direccional principal
        let dirLight = DirectionalLight()
        dirLight.light.color     = .white
        dirLight.light.intensity = 3000
        dirLight.shadow          = DirectionalLightComponent.Shadow(maximumDistance: 20,
                                                                     depthBias: 0.05)
        let lightAnchor = AnchorEntity(world: SIMD3(2, 4, 3))
        lightAnchor.addChild(dirLight)
        arView.scene.addAnchor(lightAnchor)

        // Luz de relleno
        let fillLight = DirectionalLight()
        fillLight.light.color     = UIColor(red: 0.7, green: 0.8, blue: 1.0, alpha: 1)
        fillLight.light.intensity = 800
        let fillAnchor = AnchorEntity(world: SIMD3(-3, 1, -2))
        fillAnchor.addChild(fillLight)
        arView.scene.addAnchor(fillAnchor)
    }

    // MARK: - Cámara

    private func setupCamera() {
        updateCameraTransform()
    }

    private func updateCameraTransform() {
        // Posición esférica en torno a modelCenter
        let x = radius * cos(elevation) * sin(azimuth)
        let y = radius * sin(elevation)
        let z = radius * cos(elevation) * cos(azimuth)
        let camPos = modelCenter + SIMD3<Float>(x, y, z)

        // Matriz lookAt manual
        let forward = simd_normalize(modelCenter - camPos)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right   = simd_normalize(simd_cross(forward, worldUp))
        let up      = simd_cross(right, forward)

        var transform = simd_float4x4(1)
        transform.columns.0 = SIMD4( right.x,   right.y,   right.z,   0)
        transform.columns.1 = SIMD4( up.x,       up.y,       up.z,     0)
        transform.columns.2 = SIMD4(-forward.x, -forward.y, -forward.z, 0)
        transform.columns.3 = SIMD4( camPos.x,   camPos.y,   camPos.z,  1)

        arView.cameraTransform = Transform(matrix: transform)
    }

    // MARK: - Gestos

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinch)

        let twoFingerPan = UIPanGestureRecognizer(target: self,
                                                   action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        arView.addGestureRecognizer(twoFingerPan)

        // Permitir que gestos de 1 y 2 dedos coexistan
        pan.require(toFail: twoFingerPan)
    }

    /// Pan con 1 dedo → órbita (azimuth + elevation).
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            panStartAzimuth   = azimuth
            panStartElevation = elevation
        case .changed:
            let translation = gesture.translation(in: arView)
            let sensitivity: Float = 0.005
            azimuth   = panStartAzimuth   + Float(translation.x) * sensitivity
            elevation = (panStartElevation - Float(translation.y) * sensitivity)
                .clamped(to: minElevation...maxElevation)
            updateCameraTransform()
        default:
            break
        }
    }

    /// Pinch → zoom (radio de órbita).
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
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

    /// Pan con 2 dedos → paneo del pivote.
    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let translation = gesture.translation(in: arView)
        gesture.setTranslation(.zero, in: arView)

        let sensitivity: Float = 0.002 * radius
        let right   = simd_normalize(SIMD3<Float>(cos(azimuth), 0, -sin(azimuth)))
        let up      = SIMD3<Float>(0, 1, 0)

        modelCenter += right * (-Float(translation.x) * sensitivity)
        modelCenter += up    * ( Float(translation.y) * sensitivity)
        updateCameraTransform()
    }

    // MARK: - API pública

    /// Carga mesh.usdz del proyecto indicado.
    func loadMesh(projectId: UUID,
                  completion: ((Bool) -> Void)? = nil) {

        let docs    = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let usdzURL = docs
            .appendingPathComponent("projects")
            .appendingPathComponent(projectId.uuidString)
            .appendingPathComponent("mesh.usdz")

        loadMesh(from: usdzURL, completion: completion)
    }

    /// Carga un .usdz desde una URL arbitraria.
    func loadMesh(from url: URL,
                  completion: ((Bool) -> Void)? = nil) {

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

        // Centrar el modelo calculando su bounding box
        let bbox   = entity.visualBounds(relativeTo: nil)
        let center = bbox.center
        entity.position = -center

        // Ajustar radio inicial al tamaño del modelo
        let diagonal = simd_length(bbox.max - bbox.min)
        radius       = max(diagonal * 1.5, 0.5)
        pinchStartRadius = radius

        modelCenter = .zero

        // Extraer ModelEntity si es posible, o envolverlo
        if let model = entity as? ModelEntity {
            anchor.addChild(model)
            modelEntity = model
        } else {
            anchor.addChild(entity)
            // Buscar primer ModelEntity descendiente
            modelEntity = findModelEntity(in: entity)
        }

        rootAnchor = anchor
        arView.scene.addAnchor(anchor)

        updateCameraTransform()
        print("[ScanViewerView] modelo cargado — diagonal: \(String(format: "%.2f", diagonal)) m")
    }

    // MARK: - Añadir ModelEntity manualmente (mesh ya construido)

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
        azimuth   = 0.30
        elevation = 0.45
        if let bbox = modelEntity?.visualBounds(relativeTo: nil) {
            radius = max(simd_length(bbox.max - bbox.min) * 1.5, 0.5)
        }
        modelCenter = .zero
        updateCameraTransform()
    }

    // MARK: - Limpiar escena

    func clearScene() {
        rootAnchor?.removeFromParent()
        rootAnchor  = nil
        modelEntity = nil
    }

    // MARK: - Helper

    private func findModelEntity(in entity: Entity) -> ModelEntity? {
        if let model = entity as? ModelEntity { return model }
        for child in entity.children {
            if let found = findModelEntity(in: child) { return found }
        }
        return nil
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
