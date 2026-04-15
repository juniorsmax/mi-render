// SceneViewer.swift
// Visualizador 3D de la malla capturada usando RealityKit.
// Carga los datos de MeshPersistenceManager o MeshManager en vivo.
// Permite: navegación libre, zoom, rotación, bounding box.

import UIKit
import RealityKit
import ARKit
import ModelIO
import MetalKit
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

            let mdlAsset: MDLAsset
            if let fileName = self.meshFileName,
               let persisted = MeshPersistenceManager.shared.load(named: fileName) {
                mdlAsset = self.buildAsset(from: persisted)
            } else {
                mdlAsset = MeshManager.shared.combinedMesh()
            }

            DispatchQueue.main.async { self.displayAsset(mdlAsset) }
        }
    }

    private func buildAsset(from anchors: [PersistedMeshAnchor]) -> MDLAsset {
        let asset = MDLAsset()
        guard let device = MTLCreateSystemDefaultDevice() else { return asset }
        let allocator = MTKMeshBufferAllocator(device: device)

        for p in anchors {
            let vData = Data(bytes: p.vertices, count: p.vertices.count * MemoryLayout<Float>.size)
            let vBuf  = allocator.newBuffer(with: vData, type: .vertex)
            let iData = Data(bytes: p.faceIndices, count: p.faceIndices.count * MemoryLayout<UInt32>.size)
            let iBuf  = allocator.newBuffer(with: iData, type: .index)

            let desc = MDLVertexDescriptor()
            desc.attributes[0] = MDLVertexAttribute(
                name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
            desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 3)

            let sub  = MDLSubmesh(indexBuffer: iBuf,
                                  indexCount: p.faceIndices.count,
                                  indexType: .uInt32,
                                  geometryType: .triangles,
                                  material: nil)
            let mesh = MDLMesh(vertexBuffer: vBuf,
                               vertexCount: p.vertices.count / 3,
                               descriptor: desc,
                               submeshes: [sub])
            asset.add(mesh)
        }
        return asset
    }

    private func displayAsset(_ asset: MDLAsset) {
        // Limpiar entidades previas
        meshEntity?.removeFromParent()
        bboxEntity?.removeFromParent()

        guard asset.count > 0,
              let meshResource = try? MeshResource.generate(from: asset) else {
            showEmptyState()
            return
        }

        // Material PBR semitransparente
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.85))
        material.roughness = .init(floatLiteral: 0.7)
        material.metallic  = .init(floatLiteral: 0.1)

        let entity = ModelEntity(mesh: meshResource, materials: [material])
        anchorEntity.addChild(entity)
        meshEntity = entity

        // Centrar en escena
        let bbox = asset.boundingBox
        let center = (bbox.maxBounds + bbox.minBounds) * 0.5
        entity.position = [-center.x, -center.y, -center.z]

        // Distancia inicial basada en el tamaño del bbox
        let size = bbox.maxBounds - bbox.minBounds
        currentDistance = max(Float(size.x), Float(size.y), Float(size.z)) * 1.8
        updateCameraPosition()

        buildBoundingBox(bbox: bbox, entity: entity)
    }

    // MARK: - Bounding box

    private func buildBoundingBox(bbox: MDLAxisAlignedBoundingBox, entity: ModelEntity) {
        let size    = bbox.maxBounds - bbox.minBounds
        let boxMesh = MeshResource.generateBox(
            size: SIMD3<Float>(Float(size.x), Float(size.y), Float(size.z)),
            cornerRadius: 0
        )
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
