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

    // Multi-layer visualization
    private var layerPanel: LayerTogglePanel?
    private var cachedDescriptors: [MeshDescriptor] = []
    private var cachedPersistedAnchors: [PersistedMeshAnchor] = []
    private var panoramaNodeEntities: [ModelEntity] = []
    private var semanticEntities: [ModelEntity] = []

    // MARK: - Ciclo de vida

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Vista 3D"
        view.backgroundColor = .black
        setupARView()
        setupGestures()
        setupNavigationBar()
        setupLayerPanel()
        NotificationCenter.default.addObserver(
            self, selector: #selector(onSceneModeChanged(_:)),
            name: .sceneModeDidChange, object: nil
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: .sceneModeDidChange, object: nil)
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

    // MARK: - Setup panel de capas

    private func setupLayerPanel() {
        let panel = LayerTogglePanel()
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            panel.heightAnchor.constraint(equalToConstant: 64),
        ])
        layerPanel = panel
    }

    // MARK: - Cargar malla

    private func loadMesh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let descriptors: [MeshDescriptor]
            var persisted: [PersistedMeshAnchor] = []

            if let fileName = self.meshFileName,
               let loaded = MeshPersistenceManager.shared.load(named: fileName) {
                persisted    = loaded
                descriptors  = Self.buildDescriptors(from: loaded)
            } else {
                descriptors = Self.buildDescriptors(from: MeshManager.shared.meshAnchors)
            }

            DispatchQueue.main.async { self.displayDescriptors(descriptors, persisted: persisted) }
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

    private func displayDescriptors(_ descriptors: [MeshDescriptor],
                                     persisted: [PersistedMeshAnchor] = []) {
        cachedDescriptors      = descriptors
        cachedPersistedAnchors = persisted

        clearSemanticEntities()
        clearPanoramaNodes()
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

        // Restaurar modo guardado si no es el default
        let saved = SceneModeManager.shared.currentMode
        if saved != .meshSolid && saved != .orbitViewer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.applySceneMode(saved)
            }
        }
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

// MARK: - Scene Mode Handling

extension SceneViewerViewController {

    @objc func onSceneModeChanged(_ note: Notification) {
        guard let mode = note.object as? SceneMode else { return }
        applySceneMode(mode)
    }

    func applySceneMode(_ mode: SceneMode) {
        switch mode {

        case .meshSolid:
            if isWalkthroughActive { stopWalkthrough() }
            clearSemanticEntities(); clearPanoramaNodes()
            meshEntity?.isEnabled = true
            bboxEntity?.isEnabled = false
            applySolidMaterial()
            setGesturesEnabled(true)
            updateCameraPosition()

        case .meshWireframe:
            if isWalkthroughActive { stopWalkthrough() }
            clearSemanticEntities(); clearPanoramaNodes()
            meshEntity?.isEnabled = true
            bboxEntity?.isEnabled = false
            applyWireframeMaterial()
            setGesturesEnabled(true)
            updateCameraPosition()

        case .meshSemantic:
            if isWalkthroughActive { stopWalkthrough() }
            clearPanoramaNodes()
            meshEntity?.isEnabled = false
            bboxEntity?.isEnabled = false
            setGesturesEnabled(true)
            buildSemanticView()
            updateCameraPosition()

        case .floorPlan2D:
            if isWalkthroughActive { stopWalkthrough() }
            clearSemanticEntities(); clearPanoramaNodes()
            meshEntity?.isEnabled = true
            bboxEntity?.isEnabled = false
            applySolidMaterial()
            setGesturesEnabled(false)
            positionCameraTopDown()

        case .roomVolumeBounding:
            if isWalkthroughActive { stopWalkthrough() }
            clearSemanticEntities(); clearPanoramaNodes()
            meshEntity?.isEnabled = false
            bboxEntity?.isEnabled = true
            setGesturesEnabled(true)
            updateCameraPosition()

        case .orbitViewer:
            if isWalkthroughActive { stopWalkthrough() }
            clearSemanticEntities(); clearPanoramaNodes()
            meshEntity?.isEnabled = true
            bboxEntity?.isEnabled = false
            applySolidMaterial()
            setGesturesEnabled(true)
            updateCameraPosition()

        case .walkthroughPlayback:
            clearSemanticEntities(); clearPanoramaNodes()
            meshEntity?.isEnabled = true
            bboxEntity?.isEnabled = false
            applySolidMaterial()
            if !isWalkthroughActive { startWalkthrough() }

        case .panoramaNodes:
            if isWalkthroughActive { stopWalkthrough() }
            clearSemanticEntities()
            meshEntity?.isEnabled = true
            bboxEntity?.isEnabled = false
            applySolidMaterial()
            setGesturesEnabled(true)
            buildPanoramaNodes()
            updateCameraPosition()
        }
    }

    // MARK: Materiales

    func applySolidMaterial() {
        guard let entity = meshEntity else { return }
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.85))
        mat.roughness = .init(floatLiteral: 0.7)
        mat.metallic  = .init(floatLiteral: 0.0)
        entity.model?.materials = [mat]
    }

    func applyWireframeMaterial() {
        guard let entity = meshEntity else { return }
        var mat = UnlitMaterial()
        mat.color = .init(tint: UIColor(red: 0.0, green: 0.9, blue: 0.7, alpha: 0.55))
        entity.model?.materials = [mat]
    }

    // MARK: Modo semántico

    func buildSemanticView() {
        clearSemanticEntities()
        guard !cachedPersistedAnchors.isEmpty else { return }
        let anchors = cachedPersistedAnchors
        let offset  = meshEntity?.position ?? .zero
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let pairs = Self.buildSemanticDescriptors(from: anchors)
            DispatchQueue.main.async {
                for (desc, color) in pairs {
                    guard let mesh = try? MeshResource.generate(from: [desc]) else { continue }
                    var mat = UnlitMaterial()
                    mat.color = .init(tint: color)
                    let entity = ModelEntity(mesh: mesh, materials: [mat])
                    entity.position = offset
                    self.anchorEntity.addChild(entity)
                    self.semanticEntities.append(entity)
                }
            }
        }
    }

    private static func buildSemanticDescriptors(from anchors: [PersistedMeshAnchor])
        -> [(MeshDescriptor, UIColor)] {
        var result: [(MeshDescriptor, UIColor)] = []

        for p in anchors {
            guard p.vertices.count >= 9, !p.faceIndices.isEmpty else { continue }
            let mat4 = p.transformMatrix

            // Vértices → espacio mundo
            var worldVerts = [SIMD3<Float>]()
            worldVerts.reserveCapacity(p.vertices.count / 3)
            for i in stride(from: 0, to: p.vertices.count - 2, by: 3) {
                let local = SIMD4<Float>(p.vertices[i], p.vertices[i+1], p.vertices[i+2], 1)
                let w = mat4 * local
                worldVerts.append(SIMD3<Float>(w.x, w.y, w.z))
            }

            // Agrupar caras por clasificación
            let triCount = p.faceIndices.count / 3
            var classFaces: [UInt8: [(Int, Int, Int)]] = [:]
            for t in 0..<triCount {
                let base = t * 3
                guard base + 2 < p.faceIndices.count else { continue }
                let cls: UInt8 = t < p.classifications.count ? p.classifications[t] : 0
                classFaces[cls, default: []].append(
                    (Int(p.faceIndices[base]),
                     Int(p.faceIndices[base + 1]),
                     Int(p.faceIndices[base + 2]))
                )
            }

            for (cls, faces) in classFaces {
                guard faces.count >= 120 else { continue }   // filtrar clústeres pequeños

                // Re-indexar vértices para este sub-mesh
                var remapped = [Int: UInt32]()
                var verts    = [SIMD3<Float>]()
                var indices  = [UInt32]()

                for (i0, i1, i2) in faces {
                    for vi in [i0, i1, i2] {
                        if remapped[vi] == nil {
                            remapped[vi] = UInt32(verts.count)
                            if vi < worldVerts.count { verts.append(worldVerts[vi]) }
                        }
                        indices.append(remapped[vi] ?? 0)
                    }
                }
                guard verts.count >= 3, !indices.isEmpty else { continue }

                // Laplacian smoothing — 2 iteraciones
                laplacianSmooth(&verts, indices: indices, iterations: 2)

                var desc = MeshDescriptor()
                desc.name      = "\(p.id)_cls\(cls)"
                desc.positions = .init(verts)
                desc.primitives = .triangles(indices)
                result.append((desc, colorForClassification(cls)))
            }
        }
        return result
    }

    private static func laplacianSmooth(_ positions: inout [SIMD3<Float>],
                                         indices: [UInt32],
                                         iterations: Int) {
        let n = positions.count
        guard n > 0 else { return }
        for _ in 0..<iterations {
            var sums  = [SIMD3<Float>](repeating: .zero, count: n)
            var count = [Int](repeating: 0, count: n)
            let tc = indices.count / 3
            for t in 0..<tc {
                let base = t * 3
                guard base + 2 < indices.count else { break }
                let a = Int(indices[base])
                let b = Int(indices[base + 1])
                let c = Int(indices[base + 2])
                guard a < n, b < n, c < n else { continue }
                sums[a] += positions[b]; sums[a] += positions[c]; count[a] += 2
                sums[b] += positions[a]; sums[b] += positions[c]; count[b] += 2
                sums[c] += positions[a]; sums[c] += positions[b]; count[c] += 2
            }
            for i in 0..<n where count[i] > 0 {
                let avg = sums[i] / Float(count[i])
                positions[i] = (positions[i] + avg) * 0.5
            }
        }
    }

    private static func colorForClassification(_ cls: UInt8) -> UIColor {
        switch cls {
        case 1: return UIColor(red: 0.45, green: 0.80, blue: 0.45, alpha: 0.9) // wall — verde
        case 2: return UIColor(red: 0.80, green: 0.70, blue: 0.50, alpha: 0.9) // floor — beige
        case 3: return UIColor(red: 0.55, green: 0.55, blue: 0.90, alpha: 0.9) // ceiling — azul claro
        case 4: return UIColor(red: 0.90, green: 0.70, blue: 0.35, alpha: 0.9) // table — naranja
        case 5: return UIColor(red: 0.70, green: 0.50, blue: 0.35, alpha: 0.9) // seat — marrón
        case 6: return UIColor(red: 0.75, green: 0.90, blue: 1.00, alpha: 0.9) // window — azul pálido
        case 7: return UIColor(red: 0.55, green: 0.35, blue: 0.25, alpha: 0.9) // door — marrón oscuro
        default: return UIColor(red: 0.55, green: 0.55, blue: 0.55, alpha: 0.9) // none — gris
        }
    }

    func clearSemanticEntities() {
        semanticEntities.forEach { $0.removeFromParent() }
        semanticEntities.removeAll()
    }

    // MARK: Nodos panorama

    func buildPanoramaNodes() {
        clearPanoramaNodes()
        let nodes  = NavigationManager.shared.cameraNodes
        guard !nodes.isEmpty else { return }
        let offset = meshEntity?.position ?? .zero

        let sphereMesh = MeshResource.generateSphere(radius: 0.08)
        for (i, node) in nodes.enumerated() {
            let hue = CGFloat(i) / CGFloat(max(nodes.count, 1))
            let color = UIColor(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 1.0)
            var mat = UnlitMaterial()
            mat.color = .init(tint: color)
            let sphere = ModelEntity(mesh: sphereMesh, materials: [mat])
            sphere.position = node.position + offset
            anchorEntity.addChild(sphere)
            panoramaNodeEntities.append(sphere)
        }

        // Puntos de trayectoria entre nodos
        if nodes.count > 1 {
            let dotMesh = MeshResource.generateSphere(radius: 0.025)
            var dotMat  = UnlitMaterial()
            dotMat.color = .init(tint: UIColor.white.withAlphaComponent(0.45))
            for i in 0..<nodes.count - 1 {
                let mid = (nodes[i].position + nodes[i+1].position) * 0.5 + offset
                let dot = ModelEntity(mesh: dotMesh, materials: [dotMat])
                dot.position = mid
                anchorEntity.addChild(dot)
                panoramaNodeEntities.append(dot)
            }
        }
    }

    func clearPanoramaNodes() {
        panoramaNodeEntities.forEach { $0.removeFromParent() }
        panoramaNodeEntities.removeAll()
    }

    // MARK: Helpers de cámara y gestos

    func positionCameraTopDown() {
        let height: Float = max(currentDistance, 5.0)
        let pos = SIMD3<Float>(0, height, 0.001)
        let cameraAnchor = AnchorEntity(world: pos)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 60
        cameraAnchor.addChild(camera)
        arView.scene.anchors.filter { $0 !== anchorEntity }.forEach { arView.scene.removeAnchor($0) }
        arView.scene.addAnchor(cameraAnchor)
        cameraAnchor.look(at: .zero, from: pos, relativeTo: nil)
    }

    func setGesturesEnabled(_ enabled: Bool) {
        arView.gestureRecognizers?.forEach { $0.isEnabled = enabled }
    }
}
