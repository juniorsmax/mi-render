// SceneViewer.swift
// Visualizador 3D de la malla capturada usando RealityKit.
// Carga los datos de MeshPersistenceManager o MeshManager en vivo.
// Permite: navegación libre, zoom, rotación, bounding box.

import UIKit
import RealityKit
import ARKit
import simd

// MARK: - SceneViewerViewController

class SceneViewerViewController: UIViewController {

    // MARK: Propiedades

    private var arView: ARView!
    private var meshEntity: ModelEntity?
    private var bboxEntity: ModelEntity?
    private var anchorEntity = AnchorEntity(world: .zero)

    /// Nombre del archivo .miremesh a cargar. Si nil, usa MeshManager.shared en vivo.
    var meshFileName: String?

    // Gestos de navegación
    private var lastPanTranslation:   CGPoint = .zero
    private var lastPinchScale:       Float   = 1.0
    private var currentRotationX:     Float   = 0
    private var currentRotationY:     Float   = 0
    private var currentDistance:      Float   = 3.0   // metros

    // Walkthrough
    private var playback: NavigationPlaybackController?
    private var isWalkthroughActive: Bool = false

    // MARK: - Ciclo de vida

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vista 3D"
        view.backgroundColor = .black
        setupARView()
        setupGestures()
        setupNavigationBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        loadMesh()
    }

    // MARK: - Setup ARView (modo sin tracking — solo visualización)

    private func setupARView() {
        arView = ARView(frame: view.bounds, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.environment.background = .color(.black)
        view.addSubview(arView)
        arView.scene.addAnchor(anchorEntity)

        // Luz omnidireccional
        let pointLight = PointLight()
        pointLight.light.color = .white
        pointLight.light.intensity = 100_000
        pointLight.position = [0, 3, 3]
        anchorEntity.addChild(pointLight)

        // Luz de relleno
        let ambientLight = PointLight()
        ambientLight.light.color = UIColor(white: 0.4, alpha: 1)
        ambientLight.light.intensity = 50_000
        ambientLight.position = [0, -2, -2]
        anchorEntity.addChild(ambientLight)
    }

    // MARK: - Gestos

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinch)

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        arView.addGestureRecognizer(twoFingerPan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(resetCamera))
        doubleTap.numberOfTapsRequired = 2
        arView.addGestureRecognizer(doubleTap)
    }

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Walk", style: .plain, target: self, action: #selector(toggleWalkthrough)),
            UIBarButtonItem(title: "BBox", style: .plain, target: self, action: #selector(toggleBBox)),
            UIBarButtonItem(title: "Reset", style: .plain, target: self, action: #selector(resetCamera)),
        ]
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(dismiss(_:))
        )
    }

    // MARK: - Cargar malla

    private func loadMesh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let descriptors: [MeshDescriptor]
            if let fileName = self.meshFileName,
               let persisted = MeshPersistenceManager.shared.load(named: fileName) {
                descriptors = Self.buildDescriptors(from: persisted)
            } else {
                descriptors = Self.buildDescriptors(from: MeshManager.shared.meshAnchors)
            }

            DispatchQueue.main.async { self.displayDescriptors(descriptors) }
        }
    }

    /// Convierte PersistedMeshAnchor → [MeshDescriptor] (sin MDLMesh/MDLAsset)
    private static func buildDescriptors(from anchors: [PersistedMeshAnchor]) -> [MeshDescriptor] {
        anchors.compactMap { p -> MeshDescriptor? in
            guard p.vertices.count >= 3, !p.faceIndices.isEmpty else { return nil }

            let mat = p.transformMatrix

            // Vértices en espacio mundo (aplica transform del anchor)
            var positions = [SIMD3<Float>]()
            positions.reserveCapacity(p.vertices.count / 3)
            for i in stride(from: 0, to: p.vertices.count - 2, by: 3) {
                let local = SIMD4<Float>(p.vertices[i], p.vertices[i+1], p.vertices[i+2], 1)
                let world = mat * local
                positions.append(SIMD3<Float>(world.x, world.y, world.z))
            }

            // Normales en espacio mundo (solo rotación, sin traslación)
            var normals = [SIMD3<Float>]()
            if p.normals.count >= 3 {
                normals.reserveCapacity(p.normals.count / 3)
                // Matrix 3x3 de rotación (sin escala ni traslación)
                let r = simd_float3x3(
                    SIMD3<Float>(mat.columns.0.x, mat.columns.0.y, mat.columns.0.z),
                    SIMD3<Float>(mat.columns.1.x, mat.columns.1.y, mat.columns.1.z),
                    SIMD3<Float>(mat.columns.2.x, mat.columns.2.y, mat.columns.2.z)
                )
                for i in stride(from: 0, to: p.normals.count - 2, by: 3) {
                    let n = SIMD3<Float>(p.normals[i], p.normals[i+1], p.normals[i+2])
                    normals.append(simd_normalize(r * n))
                }
            }

            var desc = MeshDescriptor()
            desc.name      = p.id
            desc.positions = .init(positions)
            if !normals.isEmpty {
                desc.normals = .init(normals)
            }
            let uintIndices = p.faceIndices.map { UInt32($0) }
            desc.primitives = .triangles(uintIndices)
            return desc
        }
    }

    /// Convierte ARMeshAnchor[] vivos → [MeshDescriptor]
    private static func buildDescriptors(from anchors: [ARMeshAnchor]) -> [MeshDescriptor] {
        anchors.compactMap { anchor -> MeshDescriptor? in
            guard let desc = ScanManager.buildDescriptor(from: anchor) else { return nil }
            return desc
        }
    }

    private func displayDescriptors(_ descriptors: [MeshDescriptor]) {
        meshEntity?.removeFromParent()
        bboxEntity?.removeFromParent()

        guard !descriptors.isEmpty,
              let meshResource = try? MeshResource.generate(from: descriptors) else {
            showEmptyState()
            return
        }

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.85))
        material.roughness = .init(floatLiteral: 0.7)
        material.metallic  = .init(floatLiteral: 0.0)

        let entity = ModelEntity(mesh: meshResource, materials: [material])
        anchorEntity.addChild(entity)
        meshEntity = entity

        // Calcular bbox manualmente desde los descriptores
        let (minP, maxP, center) = boundingInfo(from: descriptors)
        entity.position = -center
        let diag = simd_distance(minP, maxP)
        currentDistance = max(1.0, diag * 1.2)
        updateCameraPosition()
        buildBoundingBox(min: minP, max: maxP, entity: entity)
    }

    private func boundingInfo(from descriptors: [MeshDescriptor])
        -> (min: SIMD3<Float>, max: SIMD3<Float>, center: SIMD3<Float>) {
        var minP = SIMD3<Float>(repeating:  Float.greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
        for d in descriptors {
            for p in d.positions {
                minP = simd_min(minP, p)
                maxP = simd_max(maxP, p)
            }
        }
        if minP.x == Float.greatestFiniteMagnitude { minP = .zero; maxP = .zero }
        return (minP, maxP, (minP + maxP) * 0.5)
    }

    // MARK: - Bounding box

    private func buildBoundingBox(min minP: SIMD3<Float>,
                                   max maxP: SIMD3<Float>,
                                   entity: ModelEntity) {
        let size = maxP - minP
        guard size.x > 0.01 else { return }
        let boxMesh = MeshResource.generateBox(size: size, cornerRadius: 0)
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor.cyan.withAlphaComponent(0.25))
        let boxEntity = ModelEntity(mesh: boxMesh, materials: [mat])
        boxEntity.isEnabled = false
        entity.addChild(boxEntity)
        bboxEntity = boxEntity
    }

    @objc private func toggleBBox() {
        guard let b = bboxEntity else { return }
        b.isEnabled = !b.isEnabled
    }

    // MARK: - Cámara orbital

    private func updateCameraPosition() {
        let rX  = simd_quatf(angle: currentRotationX, axis: [1, 0, 0])
        let rY  = simd_quatf(angle: currentRotationY, axis: [0, 1, 0])
        let rot = rY * rX
        let pos = rot.act(SIMD3<Float>(0, 0, currentDistance))
        arView.cameraMode = .nonAR
        // Mover la cámara virtual actualizando el anchor de la cámara
        let cameraAnchor = AnchorEntity(world: pos)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        cameraAnchor.addChild(camera)
        // Eliminar cámara anterior
        arView.scene.anchors.filter { $0 !== anchorEntity }.forEach { arView.scene.removeAnchor($0) }
        arView.scene.addAnchor(cameraAnchor)
        cameraAnchor.look(at: .zero, from: pos, relativeTo: nil)
    }

    // MARK: - Gesture handlers

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: arView)
        currentRotationY += Float(t.x - lastPanTranslation.x) * 0.005
        currentRotationX += Float(t.y - lastPanTranslation.y) * 0.005
        currentRotationX = max(-Float.pi / 2, min(Float.pi / 2, currentRotationX))
        lastPanTranslation = g.state == .ended ? .zero : t
        if g.state == .ended { lastPanTranslation = .zero }
        updateCameraPosition()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        let scale = Float(g.scale)
        currentDistance /= (scale / lastPinchScale)
        currentDistance = max(0.3, min(20.0, currentDistance))
        lastPinchScale = g.state == .ended ? 1.0 : scale
        updateCameraPosition()
    }

    @objc private func handleTwoFingerPan(_ g: UIPanGestureRecognizer) {
        // Pan en plano XY para desplazar el mesh
        guard let entity = meshEntity else { return }
        let t = g.translation(in: arView)
        entity.position.x += Float(t.x) * 0.002
        entity.position.y -= Float(t.y) * 0.002
        g.setTranslation(.zero, in: arView)
    }

    @objc private func resetCamera() {
        currentRotationX = 0
        currentRotationY = 0
        currentDistance  = 3.0
        meshEntity?.position = .zero
        updateCameraPosition()
    }

    // MARK: - Estado vacío

    private func showEmptyState() {
        let label = UILabel()
        label.text = "No hay malla disponible.\nRealiza un escaneo primero."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
        ])
    }

    @objc private func dismiss(_ sender: Any) {
        dismiss(animated: true)
    }
}

// MARK: - Walkthrough (NavigationPlaybackDelegate)

extension SceneViewerViewController: NavigationPlaybackDelegate {

    /// Alterna entre modo orbital libre y recorrido walkthrough.
    @objc func toggleWalkthrough() {
        if isWalkthroughActive {
            stopWalkthrough()
        } else {
            startWalkthrough()
        }
    }

    private func startWalkthrough() {
        let nodes = NavigationManager.shared.cameraNodes
        guard nodes.count >= 2 else {
            showAlert("Sin recorrido", "Realiza un escaneo para registrar nodos de cámara.")
            return
        }

        let ctrl = NavigationPlaybackController(nodes: nodes)
        ctrl.delegate = self
        ctrl.speed    = 1.2
        ctrl.loops    = false
        playback      = ctrl

        isWalkthroughActive = true
        updateWalkthroughButton()

        // Deshabilitar gestos manuales durante el recorrido
        arView.gestureRecognizers?.forEach { $0.isEnabled = false }

        ctrl.play()
    }

    private func stopWalkthrough() {
        playback?.stop()
        playback = nil
        isWalkthroughActive = false
        updateWalkthroughButton()
        arView.gestureRecognizers?.forEach { $0.isEnabled = true }
        updateCameraPosition()
    }

    private func updateWalkthroughButton() {
        let title = isWalkthroughActive ? "Stop" : "Walk"
        navigationItem.rightBarButtonItems?.first?.title = title
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: NavigationPlaybackDelegate

    func playback(_ controller: NavigationPlaybackController,
                  didMoveTo position: SIMD3<Float>,
                  lookingAt target: SIMD3<Float>) {
        // Colocar la cámara en la posición interpolada mirando al target
        let cameraAnchor = AnchorEntity(world: position)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 70
        cameraAnchor.addChild(camera)

        arView.scene.anchors
            .filter { $0 !== anchorEntity }
            .forEach { arView.scene.removeAnchor($0) }

        arView.scene.addAnchor(cameraAnchor)
        cameraAnchor.look(at: target, from: position, relativeTo: nil)
    }

    func playbackDidFinish(_ controller: NavigationPlaybackController) {
        isWalkthroughActive = false
        updateWalkthroughButton()
        arView.gestureRecognizers?.forEach { $0.isEnabled = true }
        updateCameraPosition()
    }
}
