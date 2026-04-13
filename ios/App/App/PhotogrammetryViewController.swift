// PhotogrammetryViewController.swift
// Captura fotos para fotogrametría on-device (iOS 17+)
// Usa AVCaptureSession + RealityKit.PhotogrammetrySession
// Genera USDZ texturizado desde múltiples fotos del espacio.
// Zerbitecni · mi-render

import UIKit
import AVFoundation
import RealityKit

@available(iOS 17.0, *)
class PhotogrammetryViewController: UIViewController {

    var onResult: (([String: Any]?) -> Void)?

    // Camera
    private let captureSession = AVCaptureSession()
    private let photoOutput    = AVCapturePhotoOutput()
    private var previewLayer:  AVCaptureVideoPreviewLayer!

    // State
    private var imageDir:     URL!
    private var capturedURLs: [URL] = []
    private var isProcessing  = false

    // UI
    private var counterLabel: UILabel!
    private var processBtn:   UIButton!
    private var progressView: UIProgressView!
    private var statusLabel:  UILabel!
    private var uiReady       = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let ts = Int(Date().timeIntervalSince1970)
        imageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("photogram-\(ts)", isDirectory: true)
        try? FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)

        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        if !uiReady { uiReady = true; setupUI() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        DispatchQueue.global(qos: .userInitiated).async { self.captureSession.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        captureSession.stopRunning()
    }

    // MARK: - Camera setup

    private func setupCamera() {
        captureSession.sessionPreset = .photo

        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam) else { return }

        captureSession.addInput(input)

        photoOutput.isHighResolutionCaptureEnabled = true
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        // Depth data si el dispositivo lo soporta
        if photoOutput.isDepthDataDeliverySupported {
            photoOutput.isDepthDataDeliveryEnabled = true
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    // MARK: - UI

    private func setupUI() {
        let w   = view.bounds.width
        let h   = view.bounds.height
        let top = view.safeAreaInsets.top + 12

        // ── Botón cerrar ──────────────────────────────────────────────
        let closeBtn = circleButton("✕", color: .white)
        closeBtn.frame = CGRect(x: 16, y: top, width: 44, height: 44)
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)

        // ── Contador ──────────────────────────────────────────────────
        counterLabel = UILabel()
        counterLabel.text = "0 fotos · mueve el iPhone por toda la habitación"
        counterLabel.textColor = .white
        counterLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        counterLabel.textAlignment = .center
        counterLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        counterLabel.layer.cornerRadius = 16
        counterLabel.clipsToBounds = true
        counterLabel.frame = CGRect(x: (w - 320) / 2, y: top + 4, width: 320, height: 34)
        view.addSubview(counterLabel)

        // ── Botón procesar (arriba derecha) ───────────────────────────
        processBtn = UIButton(type: .system)
        processBtn.setTitle("Procesar →", for: .normal)
        processBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        processBtn.setTitleColor(UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1), for: .normal)
        processBtn.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        processBtn.layer.cornerRadius = 20
        processBtn.layer.borderWidth  = 1.5
        processBtn.layer.borderColor  = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 0.45).cgColor
        processBtn.frame = CGRect(x: w - 126, y: top + 2, width: 110, height: 40)
        processBtn.isEnabled = false
        processBtn.alpha = 0.4
        processBtn.addTarget(self, action: #selector(processTapped), for: .touchUpInside)
        view.addSubview(processBtn)

        // ── Indicaciones ──────────────────────────────────────────────
        let instructLabel = UILabel()
        instructLabel.text = "Muévete lentamente por la habitación fotografiando cada pared, techo y suelo desde varios ángulos"
        instructLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        instructLabel.font = .systemFont(ofSize: 11)
        instructLabel.textAlignment = .center
        instructLabel.numberOfLines = 2
        instructLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        instructLabel.layer.cornerRadius = 10
        instructLabel.clipsToBounds = true
        instructLabel.frame = CGRect(x: 20, y: h - 200, width: w - 40, height: 44)
        view.addSubview(instructLabel)

        // ── Obturador ─────────────────────────────────────────────────
        let ring = UIView(frame: CGRect(x: (w - 84) / 2, y: h - 140, width: 84, height: 84))
        ring.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        ring.layer.cornerRadius = 42
        view.addSubview(ring)

        let shutter = UIButton(type: .custom)
        shutter.backgroundColor = .white
        shutter.layer.cornerRadius = 34
        shutter.frame = CGRect(x: 8, y: 8, width: 68, height: 68)
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        ring.addSubview(shutter)

        // ── Hint ──────────────────────────────────────────────────────
        let hint = UILabel()
        hint.text = "Toca para capturar · Mínimo 20 fotos para procesar"
        hint.textColor = UIColor.white.withAlphaComponent(0.4)
        hint.font = .systemFont(ofSize: 11)
        hint.textAlignment = .center
        hint.frame = CGRect(x: 0, y: h - 50, width: w, height: 18)
        view.addSubview(hint)

        // ── Progress (oculto al inicio) ───────────────────────────────
        progressView = UIProgressView()
        progressView.progressTintColor = UIColor(red: 0.94, green: 0.65, blue: 0, alpha: 1)
        progressView.trackTintColor    = UIColor.white.withAlphaComponent(0.15)
        progressView.layer.cornerRadius = 3
        progressView.clipsToBounds = true
        progressView.frame = CGRect(x: 32, y: h / 2 + 20, width: w - 64, height: 6)
        progressView.isHidden = true
        view.addSubview(progressView)

        statusLabel = UILabel()
        statusLabel.text = ""
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 3
        statusLabel.frame = CGRect(x: 32, y: h / 2 - 30, width: w - 64, height: 48)
        statusLabel.isHidden = true
        view.addSubview(statusLabel)
    }

    private func circleButton(_ title: String, color: UIColor) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.tintColor = color
        btn.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        btn.layer.cornerRadius = 22
        return btn
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        captureSession.stopRunning()
        dismiss(animated: true) { [weak self] in self?.onResult?(nil) }
    }

    @objc private func shutterTapped() {
        let settings = AVCapturePhotoSettings()
        if photoOutput.isDepthDataDeliverySupported {
            settings.isDepthDataDeliveryEnabled = true
        }
        photoOutput.capturePhoto(with: settings, delegate: self)

        // Flash visual
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)
        UIView.animate(withDuration: 0.05, animations: { flash.alpha = 0.55 }) { _ in
            UIView.animate(withDuration: 0.10) { flash.alpha = 0 } completion: { _ in flash.removeFromSuperview() }
        }
    }

    @objc private func processTapped() {
        guard !isProcessing, capturedURLs.count >= 20 else { return }
        isProcessing = true
        captureSession.stopRunning()

        DispatchQueue.main.async {
            self.view.subviews.filter { !($0 is UIProgressView) && !($0 === self.statusLabel) }.forEach { $0.isHidden = true }
            self.progressView.isHidden = false
            self.statusLabel.isHidden  = false
            self.statusLabel.text = "Iniciando fotogrametría…\nEsto puede tardar varios minutos."
        }

        Task { await runPhotogrammetry() }
    }

    // MARK: - Photogrammetry

    private func runPhotogrammetry() async {
        let docsDir    = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportsDir = docsDir.appendingPathComponent("Exports")
        try? FileManager.default.createDirectory(at: exportsDir, withIntermediateDirectories: true)
        let outputURL  = exportsDir.appendingPathComponent("fotograma-\(Int(Date().timeIntervalSince1970)).usdz")

        do {
            var config = PhotogrammetrySession.Configuration()
            config.sampleOrdering   = .unordered
            config.featureSensitivity = .high

            let session = try PhotogrammetrySession(input: imageDir, configuration: config)
            try session.process(requests: [
                .modelFile(url: outputURL, detail: .medium)
            ])

            for try await output in session.outputs {
                switch output {

                case .processingComplete:
                    await MainActor.run {
                        self.progressView.progress = 1.0
                        self.statusLabel.text = "✓ Modelo listo"
                    }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    let count = capturedURLs.count
                    await MainActor.run {
                        self.dismiss(animated: true) { [weak self] in
                            self?.onResult?([
                                "usdzPath":   outputURL.path,
                                "photoCount": count,
                                "scanMode":   "photogrammetry",
                                "floorArea":  Double(0),
                                "usdzExported": true,
                            ])
                        }
                    }
                    return

                case .requestProgress(_, fractionComplete: let f):
                    let pct = Int(f * 100)
                    await MainActor.run {
                        self.progressView.progress = Float(f)
                        self.statusLabel.text = "Procesando modelo 3D… \(pct)%"
                    }

                case .requestError(_, error: let e):
                    await MainActor.run {
                        self.statusLabel.text = "Error: \(e.localizedDescription)"
                    }
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await MainActor.run {
                        self.dismiss(animated: true) { [weak self] in
                            self?.onResult?(["error": e.localizedDescription])
                        }
                    }
                    return

                default:
                    break
                }
            }

        } catch {
            await MainActor.run {
                self.statusLabel.text = "Error al procesar: \(error.localizedDescription)"
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self.dismiss(animated: true) { [weak self] in
                    self?.onResult?(["error": error.localizedDescription])
                }
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

@available(iOS 17.0, *)
extension PhotogrammetryViewController: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation() else { return }
        let name = String(format: "img_%04d.heic", capturedURLs.count + 1)
        let url  = imageDir.appendingPathComponent(name)
        guard (try? data.write(to: url)) != nil else { return }
        capturedURLs.append(url)
        DispatchQueue.main.async { self.updateCounter() }
    }

    private func updateCounter() {
        let n     = capturedURLs.count
        let ready = n >= 20
        counterLabel.text = ready
            ? "\(n) fotos — ¡listo para procesar!"
            : "\(n)/20 fotos — \(20 - n) más para procesar"
        processBtn.isEnabled = ready
        processBtn.alpha     = ready ? 1.0 : 0.4
    }
}
