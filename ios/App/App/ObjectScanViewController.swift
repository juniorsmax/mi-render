// ObjectScanViewController.swift
// Controlador de escaneo de objetos 3D con ARKit .mesh.
// Muestra el feed de cámara en ARView y captura la malla cuando el usuario pulsa Capturar.

import UIKit
import ARKit
import RealityKit
import simd

class ObjectScanViewController: UIViewController {

    var onResult: (([String: Any]?) -> Void)?

    private var arView: ARView!
    private var statusLabel: UILabel!

    // ── Ciclo de vida ────────────────────────────────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.environment.sceneUnderstanding.options = [.occlusion]
        view.addSubview(arView)

        setupHUD()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else {
            config.sceneReconstruction = .mesh
        }
        config.environmentTexturing = .automatic
        arView.session.run(config)
        arView.session.delegate = self
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }

    // ── HUD ──────────────────────────────────────────────────────────────────

    private func setupHUD() {
        // Status label
        statusLabel = UILabel()
        statusLabel.text = "Mueve el iPhone alrededor del objeto"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.masksToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        // Capture button
        let captureBtn = makeButton(title: "Capturar", accent: true)
        captureBtn.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureBtn)

        // Cancel button
        let cancelBtn = makeButton(title: "Cancelar", accent: false)
        cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.85),
            statusLabel.heightAnchor.constraint(equalToConstant: 38),

            captureBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureBtn.widthAnchor.constraint(equalToConstant: 180),
            captureBtn.heightAnchor.constraint(equalToConstant: 52),

            cancelBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cancelBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
        ])
    }

    private func makeButton(title: String, accent: Bool) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        if accent {
            btn.backgroundColor = UIColor(red: 0.42, green: 0.56, blue: 1.0, alpha: 1.0)
            btn.setTitleColor(.white, for: .normal)
            btn.layer.cornerRadius = 14
        } else {
            btn.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        }
        return btn
    }

    // ── Acciones ─────────────────────────────────────────────────────────────

    @objc private func captureTapped() {
        guard let frame = arView.session.currentFrame else {
            dismiss(animated: true)
            onResult?(["dimensions": "0m × 0m × 0m", "meshFaces": 0, "meshVertices": 0, "anchorCount": 0])
            return
        }

        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }

        var totalFaces    = 0
        var totalVertices = 0
        var minX: Float = .infinity,  maxX: Float = -.infinity
        var minY: Float = .infinity,  maxY: Float = -.infinity
        var minZ: Float = .infinity,  maxZ: Float = -.infinity

        for anchor in meshAnchors {
            totalFaces    += anchor.geometry.faces.count
            totalVertices += anchor.geometry.vertices.count

            let transform = anchor.transform
            let vSrc = anchor.geometry.vertices
            for i in 0..<vSrc.count {
                let byteOffset = i * vSrc.stride + vSrc.offset
                let ptr = vSrc.buffer.contents()
                    .advanced(by: byteOffset)
                    .assumingMemoryBound(to: Float.self)
                let local = simd_float4(ptr[0], ptr[1], ptr[2], 1)
                let world = transform * local
                minX = min(minX, world.x); maxX = max(maxX, world.x)
                minY = min(minY, world.y); maxY = max(maxY, world.y)
                minZ = min(minZ, world.z); maxZ = max(maxZ, world.z)
            }
        }

        let w = meshAnchors.isEmpty ? 0 : (maxX - minX)
        let h = meshAnchors.isEmpty ? 0 : (maxY - minY)
        let d = meshAnchors.isEmpty ? 0 : (maxZ - minZ)

        // Store anchors for later export
        MeshManager.shared.setMeshAnchors(meshAnchors)

        let result: [String: Any] = [
            "dimensions":  String(format: "%.2fm × %.2fm × %.2fm", w, h, d),
            "boundingBox": ["width": w, "height": h, "depth": d],
            "meshFaces":    totalFaces,
            "meshVertices": totalVertices,
            "anchorCount":  meshAnchors.count,
            "confidence":   "medium",
        ]

        arView.session.pause()
        dismiss(animated: true)
        onResult?(result)
    }

    @objc private func cancelTapped() {
        arView.session.pause()
        dismiss(animated: true)
        onResult?(nil)
    }
}

// ── ARSessionDelegate ─────────────────────────────────────────────────────────

extension ObjectScanViewController: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let newMesh = anchors.compactMap { $0 as? ARMeshAnchor }
        if !newMesh.isEmpty {
            DispatchQueue.main.async {
                self.statusLabel.text = "Capturando malla 3D…"
            }
        }
    }
}
