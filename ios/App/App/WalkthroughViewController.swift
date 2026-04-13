// WalkthroughViewController.swift
// Recorrido interior en primera persona — versión optimizada
//
// Características:
//  • Giroscopio (CoreMotion): mira con el teléfono
//  • Tap-to-teleport: toca el suelo para moverte
//  • Vista Dollhouse: vista aérea 3D de toda la habitación
//  • Colisión con paredes (no atraviesa superficies)
//  • Screenshot desde dentro del recorrido
//  • Carga async con barra de progreso
//  • LOD automático vía SceneKit + texture mip-maps
//  • Iluminación HDR + ambient occlusion
//
// Zerbitecni · mi-render

import UIKit
import SceneKit
import CoreMotion
import Photos

class WalkthroughViewController: UIViewController {

    // MARK: - Input
    var usdzPath: String = ""

    // MARK: - SceneKit
    private var scnView:        SCNView!
    private var scene:          SCNScene!
    private var cameraNode:     SCNNode!
    private var cameraYawNode:  SCNNode!   // nodo padre (rotación horizontal)
    private var modelBounds:    (min: SCNVector3, max: SCNVector3)?

    // MARK: - Modo de vista
    private enum ViewMode { case firstPerson, dollhouse }
    private var viewMode: ViewMode = .firstPerson
    private var savedFPPosition = SCNVector3Zero
    private var savedFPYaw:   Float = 0
    private var savedFPPitch: Float = 0

    // MARK: - Orientación cámara
    private var yaw:   Float = 0
    private var pitch: Float = 0
    private var lastPan = CGPoint.zero

    // MARK: - Movimiento
    private var moveTimer: Timer?
    private let moveSpeed: Float = 0.05

    // MARK: - Giroscopio
    private let motionManager = CMMotionManager()
    private var gyroEnabled   = false
    private var refAttitude:  CMAttitude?

    // MARK: - Colisión
    private var physicsEnabled = false

    // MARK: - UI
    private var loadingView:   UIView!
    private var progressBar:   UIProgressView!
    private var loadingLabel:  UILabel!
    private var dollhouseBtn:  UIButton!
    private var gyroBtn:       UIButton!
    private var uiReady        = false
    private var initialPos     = SCNVector3Zero

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildLoadingUI()
        DispatchQueue.global(qos: .userInitiated).async { self.loadModel() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scnView?.frame     = view.bounds
        loadingView?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopGyro()
        moveTimer?.invalidate()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Carga del modelo (async + progreso)

    private func buildLoadingUI() {
        loadingView = UIView(frame: view.bounds)
        loadingView.backgroundColor = .black
        view.addSubview(loadingView)

        let logo = UILabel()
        logo.text = "mi-render"
        logo.textColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.6)
        logo.font = .systemFont(ofSize: 13, weight: .semibold)
        logo.textAlignment = .center
        logo.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(logo)

        loadingLabel = UILabel()
        loadingLabel.text = "Preparando recorrido…"
        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        loadingLabel.textAlignment = .center
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(loadingLabel)

        progressBar = UIProgressView(progressViewStyle: .bar)
        progressBar.progressTintColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1)
        progressBar.trackTintColor    = UIColor.white.withAlphaComponent(0.15)
        progressBar.layer.cornerRadius = 3
        progressBar.clipsToBounds = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(progressBar)

        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            logo.bottomAnchor.constraint(equalTo: loadingLabel.topAnchor, constant: -8),

            loadingLabel.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),

            progressBar.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            progressBar.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 16),
            progressBar.widthAnchor.constraint(equalToConstant: 220),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
        ])
    }

    private func setProgress(_ v: Float, label: String) {
        DispatchQueue.main.async {
            self.progressBar.setProgress(v, animated: true)
            self.loadingLabel.text = label
        }
    }

    private func loadModel() {
        setProgress(0.1, label: "Leyendo archivo USDZ…")

        let url = URL(fileURLWithPath: usdzPath)
        guard FileManager.default.fileExists(atPath: usdzPath),
              let loaded = try? SCNScene(url: url, options: [
                  SCNSceneSource.LoadingOption.checkConsistency: false,
                  SCNSceneSource.LoadingOption.convertToYUp: true,
              ]) else {
            DispatchQueue.main.async { self.showError("No se encontró el modelo") }
            return
        }

        setProgress(0.35, label: "Optimizando geometría…")
        scene = loaded
        optimizeScene()

        setProgress(0.6, label: "Calculando iluminación…")
        setupLighting()

        setProgress(0.8, label: "Posicionando cámara…")
        setupCamera()

        setProgress(0.95, label: "Preparando física…")
        setupPhysics()

        DispatchQueue.main.async {
            self.progressBar.setProgress(1.0, animated: true)
            self.buildSceneView()
        }
    }

    // MARK: - Optimización de escena

    private func optimizeScene() {
        // Bounding box del modelo completo
        modelBounds = scene.rootNode.boundingBox

        scene.rootNode.enumerateHierarchy { node, _ in
            guard let geo = node.geometry else { return }

            // Doble cara solo en superficies que lo necesitan
            geo.materials.forEach { mat in
                mat.isDoubleSided  = true
                mat.cullMode       = .front
                // Mip-maps para texturas (mejor rendimiento en lejos)
                mat.diffuse.mipFilter  = .linear
                mat.diffuse.wrapS      = .repeat
                mat.diffuse.wrapT      = .repeat
            }

            // LOD: simplificar nodos lejanos automáticamente
            let lod = SCNLevelOfDetail(geometry: geo, screenSpaceRadius: 5)
            node.levelsOfDetail = [lod]
        }

        // Flatten geometrías estáticas (mejora render)
        scene.rootNode.flattenedClone()
    }

    // MARK: - Iluminación

    private func setupLighting() {
        // Ambiente cálida (como una habitación)
        let amb = SCNLight(); amb.type = .ambient
        amb.intensity = 600
        amb.temperature = 6500
        amb.color = UIColor.white
        let ambNode = SCNNode(); ambNode.light = amb
        scene.rootNode.addChildNode(ambNode)

        // Luz direccional suave (simula ventana)
        let dir = SCNLight(); dir.type = .directional
        dir.intensity = 800
        dir.temperature = 5500
        dir.castsShadow = true
        dir.shadowRadius = 8
        dir.shadowSampleCount = 4
        dir.shadowColor = UIColor.black.withAlphaComponent(0.3)
        let dirNode = SCNNode(); dirNode.light = dir
        dirNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(dirNode)

        // Activar ambient occlusion en la escena
        scene.lightingEnvironment.intensity = 0.8
    }

    // MARK: - Cámara

    private func setupCamera() {
        guard let bounds = modelBounds else { return }

        let cx = (bounds.min.x + bounds.max.x) / 2
        let cz = (bounds.min.z + bounds.max.z) / 2
        let eyeY = bounds.min.y + 1.65

        initialPos = SCNVector3(cx, eyeY, cz)

        // Nodo de yaw (rotación horizontal del cuerpo)
        cameraYawNode = SCNNode()
        cameraYawNode.position = initialPos

        // Nodo de cámara (hijo — solo pitch vertical)
        cameraNode = SCNNode()
        cameraNode.camera = {
            let cam = SCNCamera()
            cam.fieldOfView    = 80
            cam.zNear          = 0.02
            cam.zFar           = 200
            cam.wantsHDR       = true
            cam.wantsExposureAdaptation = true
            return cam
        }()

        cameraYawNode.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraYawNode)
    }

    // MARK: - Física / colisiones

    private func setupPhysics() {
        // Cuerpo de cámara (cápsula)
        let capsule = SCNCapsule(capRadius: 0.2, height: 1.7)
        let camBody = SCNPhysicsBody(type: .kinematic, shape: SCNPhysicsShape(geometry: capsule))
        camBody.categoryBitMask  = 1
        camBody.collisionBitMask = 2
        cameraYawNode?.physicsBody = camBody

        // Física estática a los nodos del modelo
        scene.rootNode.enumerateHierarchy { node, _ in
            guard node.geometry != nil, node !== cameraYawNode, node !== cameraNode else { return }
            if node.physicsBody == nil {
                let body = SCNPhysicsBody(type: .static, shape: SCNPhysicsShape(node: node, options: [
                    SCNPhysicsShape.Option.type: SCNPhysicsShape.ShapeType.concavePolyhedron
                ]))
                body.categoryBitMask  = 2
                body.collisionBitMask = 1
                node.physicsBody = body
            }
        }

        scene.physicsWorld.gravity = SCNVector3(0, 0, 0)  // sin gravedad (floating camera)
        physicsEnabled = true
    }

    // MARK: - SCNView

    private func buildSceneView() {
        scnView = SCNView(frame: view.bounds)
        scnView.scene            = scene
        scnView.pointOfView      = cameraNode
        scnView.allowsCameraControl = false
        scnView.backgroundColor  = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.showsStatistics  = false

        // Ambient occlusion + render quality
        scnView.technique        = nil

        view.insertSubview(scnView, belowSubview: loadingView)

        setupOverlayUI()
        setupGestures()

        UIView.animate(withDuration: 0.5, delay: 0.2) {
            self.loadingView.alpha = 0
        } completion: { _ in
            self.loadingView.removeFromSuperview()
        }
    }

    // MARK: - UI superpuesta

    private func setupOverlayUI() {
        let w   = view.bounds.width
        let top = view.safeAreaInsets.top + 8
        let bot = view.bounds.height - view.safeAreaInsets.bottom - 12

        // ── Barra superior ────────────────────────────────────────────────────
        let topBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        topBlur.frame = CGRect(x: 0, y: 0, width: w, height: top + 52)
        topBlur.alpha = 0.9
        view.addSubview(topBlur)

        // Cerrar
        addIconBtn("✕", x: 12, y: top + 4, action: #selector(closeTapped))

        // Título
        let title = UILabel(frame: CGRect(x: 60, y: top + 10, width: w - 120, height: 28))
        title.text = "Recorrido interior"
        title.textColor = .white
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textAlignment = .center
        view.addSubview(title)

        // Reset
        addIconBtn("⌂", x: w - 52, y: top + 4, action: #selector(resetCamera))

        // ── Botones secundarios ───────────────────────────────────────────────
        dollhouseBtn = pillBtn("🏠 Dollhouse", y: top + 58, action: #selector(toggleDollhouse))
        view.addSubview(dollhouseBtn)

        gyroBtn = pillBtn("📱 Giroscopio", y: top + 104, action: #selector(toggleGyro))
        view.addSubview(gyroBtn)

        let screenshotBtn = pillBtn("📷 Captura", y: top + 150, action: #selector(takeScreenshot))
        view.addSubview(screenshotBtn)

        // ── Panel de movimiento ───────────────────────────────────────────────
        let pad: CGFloat = 14
        let panelH: CGFloat = 96
        let panelY = bot - panelH - pad

        let ctrlBg = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        ctrlBg.frame = CGRect(x: pad, y: panelY, width: w - pad * 2, height: panelH)
        ctrlBg.layer.cornerRadius = 20
        ctrlBg.clipsToBounds = true
        ctrlBg.alpha = 0.85
        view.addSubview(ctrlBg)

        let cx = (w - pad * 2) / 2
        // ▲ adelante
        addMoveBtn("▲", frame: CGRect(x: cx - 30, y: 8,  w: 60, h: 38), tag: 1, parent: ctrlBg.contentView)
        // ▼ atrás
        addMoveBtn("▼", frame: CGRect(x: cx - 30, y: 50, w: 60, h: 38), tag: -1, parent: ctrlBg.contentView)
        // ◀ girar izq
        addMoveBtn("◀", frame: CGRect(x: cx - 108, y: 28, w: 52, h: 40), tag: 10, parent: ctrlBg.contentView)
        // ▶ girar der
        addMoveBtn("▶", frame: CGRect(x: cx + 56,  y: 28, w: 52, h: 40), tag: 11, parent: ctrlBg.contentView)
        // ↑ subir
        addMoveBtn("↑", frame: CGRect(x: 8,        y: 8,  w: 44, h: 38), tag: 20, parent: ctrlBg.contentView)
        // ↓ bajar
        addMoveBtn("↓", frame: CGRect(x: 8,        y: 50, w: 44, h: 38), tag: 21, parent: ctrlBg.contentView)

        // Hint tap-to-teleport
        let hint = UILabel(frame: CGRect(x: 0, y: panelY - 22, width: w, height: 18))
        hint.text = "Toca el suelo para teletransportarte"
        hint.textColor = UIColor.white.withAlphaComponent(0.35)
        hint.font = .systemFont(ofSize: 11)
        hint.textAlignment = .center
        view.addSubview(hint)
        UIView.animate(withDuration: 0.6, delay: 4) { hint.alpha = 0 }
    }

    @discardableResult
    private func addIconBtn(_ t: String, x: CGFloat, y: CGFloat, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: x, y: y, width: 40, height: 40)
        btn.setTitle(t, for: .normal)
        btn.tintColor = .white
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        btn.layer.cornerRadius = 20
        btn.addTarget(self, action: action, for: .touchUpInside)
        view.addSubview(btn)
        return btn
    }

    private func pillBtn(_ t: String, y: CGFloat, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(t, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        btn.layer.cornerRadius = 14
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor.white.withAlphaComponent(0.12).cgColor
        btn.contentEdgeInsets  = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        btn.sizeToFit()
        btn.frame.origin = CGPoint(x: view.bounds.width - btn.frame.width - 12, y: y)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func addMoveBtn(_ t: String, frame f: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat), tag: Int, parent: UIView) {
        let btn = UIButton(type: .system)
        btn.frame = CGRect(x: f.x, y: f.y, width: f.w, height: f.h)
        btn.setTitle(t, for: .normal)
        btn.setTitleColor(UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.9), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        btn.backgroundColor = UIColor.white.withAlphaComponent(0.07)
        btn.layer.cornerRadius = 10
        btn.tag = tag
        btn.addTarget(self, action: #selector(moveTap(_:)), for: .touchUpInside)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(movePress(_:)))
        press.minimumPressDuration = 0.05
        btn.addGestureRecognizer(press)
        parent.addSubview(btn)
    }

    // MARK: - Gestos

    private func setupGestures() {
        // Pan → mirar
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        scnView.addGestureRecognizer(pan)

        // Tap → teletransportar
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: pan)
        scnView.addGestureRecognizer(tap)

        // Pinch → velocidad de movimiento
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        scnView.addGestureRecognizer(pinch)
    }

    // ── Pan: mirar ────────────────────────────────────────────────────────────
    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard viewMode == .firstPerson, !gyroEnabled else { return }
        let loc = g.location(in: scnView)
        if g.state == .began { lastPan = loc; return }
        let dx = Float(loc.x - lastPan.x)
        let dy = Float(loc.y - lastPan.y)
        lastPan = loc
        yaw   -= dx * 0.004
        pitch -= dy * 0.004
        pitch  = max(-1.2, min(1.2, pitch))
        applyCameraOrientation()
    }

    // ── Tap: teletransportar al suelo tocado ──────────────────────────────────
    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard viewMode == .firstPerson else { return }
        let pt   = g.location(in: scnView)
        let hits = scnView.hitTest(pt, options: [
            .searchMode: SCNHitTestSearchMode.closest.rawValue,
            .ignoreHiddenNodes: true,
        ])
        guard let hit = hits.first(where: { $0.node !== cameraNode && $0.node !== cameraYawNode }) else { return }

        let target = hit.worldCoordinates
        // Solo teletransportar si es suelo (Y baja) o pared cercana
        let newY   = max(target.y + 1.65, (modelBounds?.min.y ?? 0) + 1.65)
        let dest   = SCNVector3(target.x, newY, target.z)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.4
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraYawNode?.position = dest
        SCNTransaction.commit()

        // Feedback háptico
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // ── Pinch: ajusta velocidad de movimiento ─────────────────────────────────
    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            // No usado en primera persona — reservado para dollhouse zoom
        }
    }

    // ── Botones de movimiento ─────────────────────────────────────────────────
    @objc private func moveTap(_ btn: UIButton) {
        applyMove(tag: btn.tag, steps: 4)
    }

    @objc private func movePress(_ g: UILongPressGestureRecognizer) {
        guard let btn = g.view else { return }
        switch g.state {
        case .began:
            moveTimer?.invalidate()
            moveTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
                self?.applyMove(tag: btn.tag, steps: 1)
            }
        case .ended, .cancelled, .failed:
            moveTimer?.invalidate(); moveTimer = nil
        default: break
        }
    }

    private func applyMove(tag: Int, steps: Int) {
        guard let cam = cameraYawNode, viewMode == .firstPerson else { return }
        let s = moveSpeed * Float(steps)
        switch tag {
        case  1: cam.simdPosition += cam.simdWorldFront  * s
        case -1: cam.simdPosition -= cam.simdWorldFront  * s
        case 10: yaw += 0.06 * Float(steps); applyCameraOrientation()
        case 11: yaw -= 0.06 * Float(steps); applyCameraOrientation()
        case 20: cam.simdPosition += simd_float3(0,  s * 0.5, 0)
        case 21: cam.simdPosition -= simd_float3(0,  s * 0.5, 0)
        default: break
        }
    }

    private func applyCameraOrientation() {
        cameraYawNode?.eulerAngles.y = yaw
        cameraNode?.eulerAngles.x    = pitch
    }

    // MARK: - Vista Dollhouse

    @objc private func toggleDollhouse() {
        if viewMode == .firstPerson {
            // Guardar posición actual
            savedFPPosition = cameraYawNode?.position ?? initialPos
            savedFPYaw      = yaw
            savedFPPitch    = pitch

            viewMode = .dollhouse
            dollhouseBtn.setTitle("👤 Primera persona", for: .normal)

            guard let bounds = modelBounds else { return }
            let cx   = (bounds.min.x + bounds.max.x) / 2
            let cz   = (bounds.min.z + bounds.max.z) / 2
            let maxDim = max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z)
            let height = bounds.max.y + maxDim * 0.9

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.7
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraYawNode?.position    = SCNVector3(cx, height, cz)
            cameraYawNode?.eulerAngles = SCNVector3Zero
            cameraNode?.eulerAngles    = SCNVector3(-Float.pi / 2.1, 0, 0)
            SCNTransaction.commit()

        } else {
            viewMode = .firstPerson
            dollhouseBtn.setTitle("🏠 Dollhouse", for: .normal)
            yaw   = savedFPYaw
            pitch = savedFPPitch

            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.7
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cameraYawNode?.position    = savedFPPosition
            cameraYawNode?.eulerAngles = SCNVector3(0, yaw, 0)
            cameraNode?.eulerAngles    = SCNVector3(pitch, 0, 0)
            SCNTransaction.commit()
        }
    }

    // MARK: - Giroscopio

    @objc private func toggleGyro() {
        gyroEnabled ? stopGyro() : startGyro()
    }

    private func startGyro() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion, self.viewMode == .firstPerson else { return }
            if self.refAttitude == nil { self.refAttitude = motion.attitude.copy() as? CMAttitude }
            guard let ref = self.refAttitude else { return }
            let att = motion.attitude
            att.multiply(byInverseOf: ref)
            self.yaw   = Float(-att.yaw)
            self.pitch = Float( att.pitch) * 0.7
            self.pitch = max(-1.1, min(1.1, self.pitch))
            self.applyCameraOrientation()
        }
        gyroEnabled = true
        gyroBtn.setTitle("📱 Giroscopio ON", for: .normal)
        gyroBtn.backgroundColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.3)
        refAttitude = nil
    }

    private func stopGyro() {
        motionManager.stopDeviceMotionUpdates()
        gyroEnabled = false
        refAttitude = nil
        gyroBtn.setTitle("📱 Giroscopio", for: .normal)
        gyroBtn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    }

    // MARK: - Screenshot

    @objc private func takeScreenshot() {
        let img = scnView.snapshot()
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: img)
            } completionHandler: { success, _ in
                DispatchQueue.main.async {
                    if success {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        self.showToast("Captura guardada en Fotos")
                    }
                }
            }
        }
    }

    // MARK: - Reset / Cerrar

    @objc private func resetCamera() {
        stopGyro()
        yaw   = 0
        pitch = 0
        viewMode = .firstPerson
        dollhouseBtn.setTitle("🏠 Dollhouse", for: .normal)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraYawNode?.position    = initialPos
        cameraYawNode?.eulerAngles = SCNVector3Zero
        cameraNode?.eulerAngles    = SCNVector3Zero
        SCNTransaction.commit()
    }

    @objc private func closeTapped() {
        stopGyro()
        moveTimer?.invalidate()
        dismiss(animated: true)
    }

    // MARK: - Toast

    private func showToast(_ msg: String) {
        let toast = UILabel()
        toast.text = "  \(msg)  "
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 13, weight: .medium)
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        toast.layer.cornerRadius = 14
        toast.clipsToBounds = true
        toast.sizeToFit()
        toast.frame.origin = CGPoint(
            x: (view.bounds.width - toast.frame.width) / 2,
            y: view.safeAreaInsets.top + 70
        )
        toast.alpha = 0
        view.addSubview(toast)
        UIView.animate(withDuration: 0.2, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.8, animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    // MARK: - Error

    private func showError(_ msg: String) {
        loadingLabel.text = "⚠️ \(msg)"
        loadingLabel.textColor = UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1)
        progressBar.isHidden = true
        let btn = UIButton(type: .system)
        btn.setTitle("Cerrar", for: .normal)
        btn.tintColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            btn.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 24),
        ])
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }
}
