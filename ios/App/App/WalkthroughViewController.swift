// WalkthroughViewController.swift
// Recorrido interior en primera persona de un modelo USDZ.
// Carga el archivo en SceneKit, posiciona la cámara dentro y
// permite navegar con gestos (mirar / moverse / teletransportarse).
// Zerbitecni · mi-render

import UIKit
import SceneKit

class WalkthroughViewController: UIViewController {

    // ── Entrada ───────────────────────────────────────────────────────────────
    var usdzPath: String = ""

    // ── SceneKit ─────────────────────────────────────────────────────────────
    private var scnView:    SCNView!
    private var scene:      SCNScene!
    private var cameraNode: SCNNode!
    private var modelNode:  SCNNode!

    // ── Orientación cámara ────────────────────────────────────────────────────
    private var yaw:   Float = 0      // rotación horizontal (izq/der)
    private var pitch: Float = 0      // inclinación vertical (arriba/abajo)
    private var lastPan = CGPoint.zero

    // ── Estado ────────────────────────────────────────────────────────────────
    private var initialPosition = SCNVector3Zero
    private var moveTimer: Timer?
    private var moveDirection: Float = 0   // +1 adelante, -1 atrás
    private var moveSpeed: Float = 0.04
    private var uiReady = false

    // ── UI ────────────────────────────────────────────────────────────────────
    private var loadingView: UIView!
    private var loadingLabel: UILabel!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupLoadingScreen()
        DispatchQueue.global(qos: .userInitiated).async { self.loadScene() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scnView?.frame = view.bounds
        loadingView?.frame = view.bounds
        if scnView != nil && !uiReady { uiReady = true; setupUI() }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Carga de escena

    private func setupLoadingScreen() {
        loadingView = UIView(frame: view.bounds)
        loadingView.backgroundColor = .black
        view.addSubview(loadingView)

        loadingLabel = UILabel()
        loadingLabel.text = "Cargando modelo 3D…"
        loadingLabel.textColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1)
        loadingLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        loadingLabel.textAlignment = .center
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
        ])
    }

    private func loadScene() {
        let url = URL(fileURLWithPath: usdzPath)
        guard FileManager.default.fileExists(atPath: usdzPath),
              let loaded = try? SCNScene(url: url, options: [
                  SCNSceneSource.LoadingOption.checkConsistency: false,
              ])
        else {
            DispatchQueue.main.async { self.showError("No se encontró el modelo 3D") }
            return
        }

        scene    = loaded
        modelNode = SCNNode()
        scene.rootNode.childNodes.forEach { modelNode.addChildNode($0.clone()) }

        // Materiales de doble cara para ver el interior
        scene.rootNode.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { mat in
                mat.isDoubleSided = true
                mat.cullMode = .front
            }
        }

        // Luz ambiente
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 800
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Calcular posición inicial dentro del modelo
        let (minBB, maxBB) = scene.rootNode.boundingBox
        let cx = (minBB.x + maxBB.x) / 2
        let cz = (minBB.z + maxBB.z) / 2
        let eyeY = minBB.y + 1.65   // altura de los ojos ~1.65m

        initialPosition = SCNVector3(cx, eyeY, cz)

        // Cámara
        let camera        = SCNCamera()
        camera.fieldOfView = 80
        camera.zNear      = 0.01
        camera.zFar       = 200
        camera.wantsHDR   = true

        cameraNode          = SCNNode()
        cameraNode.camera   = camera
        cameraNode.position = initialPosition
        scene.rootNode.addChildNode(cameraNode)

        DispatchQueue.main.async { self.presentScene() }
    }

    private func presentScene() {
        // SceneKit view
        scnView = SCNView(frame: view.bounds)
        scnView.scene            = scene
        scnView.pointOfView      = cameraNode
        scnView.allowsCameraControl = false
        scnView.backgroundColor  = .black
        scnView.autoenablesDefaultLighting = false
        scnView.showsStatistics  = false
        view.insertSubview(scnView, belowSubview: loadingView)

        setupUI()
        uiReady = true

        UIView.animate(withDuration: 0.4) { self.loadingView.alpha = 0 } completion: { _ in
            self.loadingView.removeFromSuperview()
        }
    }

    private func showError(_ msg: String) {
        loadingLabel.text = "⚠️ \(msg)"
        loadingLabel.textColor = UIColor(red: 0.94, green: 0.3, blue: 0.3, alpha: 1)

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("Cerrar", for: .normal)
        closeBtn.tintColor = .white
        closeBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        loadingView.addSubview(closeBtn)
        NSLayoutConstraint.activate([
            closeBtn.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
            closeBtn.topAnchor.constraint(equalTo: loadingLabel.bottomAnchor, constant: 20),
        ])
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }

    // MARK: - UI superpuesta

    private func setupUI() {
        let w   = view.bounds.width
        let top = view.safeAreaInsets.top + 8
        let bot = view.bounds.height - view.safeAreaInsets.bottom - 80

        // ── Barra superior semitransparente ───────────────────────────────────
        let topBar = UIView(frame: CGRect(x: 0, y: 0, width: w, height: top + 52))
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.addSubview(topBar)

        // Cerrar
        let closeBtn = iconButton("✕", at: CGRect(x: 12, y: top + 4, width: 40, height: 40))
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        // Título
        let titleLabel = UILabel(frame: CGRect(x: 60, y: top + 8, width: w - 120, height: 32))
        titleLabel.text = "Recorrido interior"
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        // Reset posición
        let resetBtn = iconButton("⌂", at: CGRect(x: w - 52, y: top + 4, width: 40, height: 40))
        resetBtn.addTarget(self, action: #selector(resetPosition), for: .touchUpInside)
        view.addSubview(resetBtn)

        // ── Instrucción flotante ──────────────────────────────────────────────
        let hint = UILabel(frame: CGRect(x: 20, y: top + 56, width: w - 40, height: 24))
        hint.text = "Desliza para mirar · Botones para moverse"
        hint.textColor = UIColor.white.withAlphaComponent(0.45)
        hint.font = .systemFont(ofSize: 11)
        hint.textAlignment = .center
        view.addSubview(hint)
        UIView.animate(withDuration: 0.5, delay: 3, options: [], animations: { hint.alpha = 0 })

        // ── Controles de movimiento (joystick) ───────────────────────────────
        let ctrlBar = UIView(frame: CGRect(x: 0, y: bot - 10, width: w, height: 90))
        ctrlBar.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        ctrlBar.layer.cornerRadius = 22
        view.addSubview(ctrlBar)

        // Botón atrás
        let backBtn = moveButton("◀", at: CGRect(x: w / 2 - 130, y: 12, width: 60, height: 60))
        backBtn.tag = -1
        addMoveGestures(to: backBtn)
        ctrlBar.addSubview(backBtn)

        // Botón adelante
        let fwdBtn = moveButton("▶", at: CGRect(x: w / 2 + 70, y: 12, width: 60, height: 60))
        fwdBtn.tag = 1
        addMoveGestures(to: fwdBtn)
        ctrlBar.addSubview(fwdBtn)

        // Botón arriba
        let upBtn = moveButton("▲", at: CGRect(x: w / 2 - 30, y: 0, width: 60, height: 42))
        upBtn.tag = 10
        addMoveGestures(to: upBtn)
        ctrlBar.addSubview(upBtn)

        // Botón abajo
        let downBtn = moveButton("▼", at: CGRect(x: w / 2 - 30, y: 44, width: 60, height: 42))
        downBtn.tag = 11
        addMoveGestures(to: downBtn)
        ctrlBar.addSubview(downBtn)

        // ── Gestos de mirar (pan) ─────────────────────────────────────────────
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        scnView?.addGestureRecognizer(panGesture)
    }

    private func iconButton(_ title: String, at frame: CGRect) -> UIButton {
        let btn = UIButton(type: .system)
        btn.frame = frame
        btn.setTitle(title, for: .normal)
        btn.tintColor = .white
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        btn.layer.cornerRadius = 20
        return btn
    }

    private func moveButton(_ title: String, at frame: CGRect) -> UIButton {
        let btn = UIButton(type: .system)
        btn.frame = frame
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.9), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        btn.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        btn.layer.cornerRadius = 12
        return btn
    }

    private func addMoveGestures(to btn: UIButton) {
        let press   = UILongPressGestureRecognizer(target: self, action: #selector(handleMove(_:)))
        press.minimumPressDuration = 0.05
        btn.addGestureRecognizer(press)
        btn.addTarget(self, action: #selector(moveTap(_:)), for: .touchUpInside)
    }

    // MARK: - Gestos

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let loc = gesture.location(in: scnView)

        if gesture.state == .began {
            lastPan = loc
            return
        }

        let dx = Float(loc.x - lastPan.x)
        let dy = Float(loc.y - lastPan.y)
        lastPan = loc

        yaw   -= dx * 0.004
        pitch -= dy * 0.004
        pitch  = max(-Float.pi / 2.2, min(Float.pi / 2.2, pitch))

        cameraNode?.eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    @objc private func handleMove(_ gesture: UILongPressGestureRecognizer) {
        guard let btn = gesture.view else { return }
        switch gesture.state {
        case .began:
            startMoving(tag: btn.tag)
        case .ended, .cancelled, .failed:
            stopMoving()
        default: break
        }
    }

    @objc private func moveTap(_ btn: UIButton) {
        // Movimiento puntual al tocar brevemente
        applyMovement(tag: btn.tag, steps: 3)
    }

    private func startMoving(tag: Int) {
        stopMoving()
        moveTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.applyMovement(tag: tag, steps: 1)
        }
    }

    private func stopMoving() {
        moveTimer?.invalidate()
        moveTimer = nil
    }

    private func applyMovement(tag: Int, steps: Int) {
        guard let cam = cameraNode else { return }
        let spd = moveSpeed * Float(steps)

        switch tag {
        case 1:   // Adelante
            let fwd = cam.simdWorldFront
            cam.simdPosition += fwd * spd
        case -1:  // Atrás
            let fwd = cam.simdWorldFront
            cam.simdPosition -= fwd * spd
        case 10:  // Arriba
            cam.simdPosition += simd_float3(0, spd * 0.6, 0)
        case 11:  // Abajo
            cam.simdPosition -= simd_float3(0, spd * 0.6, 0)
        default: break
        }
    }

    @objc private func resetPosition() {
        guard let cam = cameraNode else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        cam.position    = initialPosition
        cam.eulerAngles = SCNVector3Zero
        SCNTransaction.commit()
        yaw   = 0
        pitch = 0
    }

    @objc private func closeTapped() {
        stopMoving()
        dismiss(animated: true)
    }
}
