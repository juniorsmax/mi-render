// SceneTimelineBar.swift
// Barra de timeline inferior que muestra:
//   • Hora de inicio / fin del escaneo
//   • Versiones guardadas (puntos clicables)
//   • Progreso del recorrido de cámara
// Observa NavigationPlaybackController vía NotificationCenter.

import UIKit

// MARK: - SceneTimelineVersion

struct SceneTimelineVersion {
    let id:        String
    let timestamp: Date
    let label:     String
}

// MARK: - SceneTimelineBar

class SceneTimelineBar: UIView {

    // MARK: - Notificaciones

    static let playbackProgressNotification = Notification.Name("mi_render_playbackProgress")

    // MARK: - Constantes

    private static let defaultsKeyExpanded = "mi_render_timeline_expanded"

    // MARK: - Estado

    private(set) var isExpanded: Bool = false
    private var versions: [SceneTimelineVersion] = []
    private var progress: Float = 0.0

    // MARK: - Subvistas

    private let blurContainer: UIVisualEffectView = {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        v.layer.cornerRadius = 14
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        v.clipsToBounds = true
        return v
    }()

    // Fila superior: times + toggle
    private let startTimeLabel: UILabel = makeTimeLabel()
    private let endTimeLabel: UILabel   = makeTimeLabel()

    private let toggleButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        b.tintColor = UIColor.white.withAlphaComponent(0.6)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    // Slider de progreso
    private let progressSlider: UISlider = {
        let s = UISlider()
        s.minimumValue = 0
        s.maximumValue = 1
        s.value = 0
        s.minimumTrackTintColor = UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 1.0)
        s.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.20)
        s.thumbTintColor = .white
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // Versiones
    private let versionsScrollView: UIScrollView = {
        let s = UIScrollView()
        s.showsHorizontalScrollIndicator = false
        s.alwaysBounceHorizontal = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let versionsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 8
        s.alignment = .center
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // Etiqueta de progreso
    private let progressLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        l.textColor = UIColor.white.withAlphaComponent(0.55)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // Altura de la barra (colapsada / expandida)
    private var heightConstraint: NSLayoutConstraint?
    private let collapsedHeight: CGFloat = 50
    private let expandedHeight:  CGFloat = 120

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        observeNotifications()
        restoreState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        observeNotifications()
        restoreState()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(blurContainer)
        blurContainer.translatesAutoresizingMaskIntoConstraints = false

        let content = blurContainer.contentView
        content.addSubview(startTimeLabel)
        content.addSubview(endTimeLabel)
        content.addSubview(toggleButton)
        content.addSubview(progressSlider)
        content.addSubview(progressLabel)
        content.addSubview(versionsScrollView)
        versionsScrollView.addSubview(versionsStack)

        NSLayoutConstraint.activate([
            // Blur llena la vista
            blurContainer.topAnchor.constraint(equalTo: topAnchor),
            blurContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Start label
            startTimeLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            startTimeLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),

            // End label
            endTimeLabel.trailingAnchor.constraint(equalTo: toggleButton.leadingAnchor, constant: -8),
            endTimeLabel.centerYAnchor.constraint(equalTo: startTimeLabel.centerYAnchor),

            // Toggle
            toggleButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            toggleButton.centerYAnchor.constraint(equalTo: startTimeLabel.centerYAnchor),
            toggleButton.widthAnchor.constraint(equalToConstant: 28),

            // Slider
            progressSlider.topAnchor.constraint(equalTo: startTimeLabel.bottomAnchor, constant: 8),
            progressSlider.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            progressSlider.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            // Progress label
            progressLabel.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 2),
            progressLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            // Versions
            versionsScrollView.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 8),
            versionsScrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            versionsScrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            versionsScrollView.heightAnchor.constraint(equalToConstant: 28),

            versionsStack.topAnchor.constraint(equalTo: versionsScrollView.contentLayoutGuide.topAnchor),
            versionsStack.bottomAnchor.constraint(equalTo: versionsScrollView.contentLayoutGuide.bottomAnchor),
            versionsStack.leadingAnchor.constraint(equalTo: versionsScrollView.contentLayoutGuide.leadingAnchor),
            versionsStack.trailingAnchor.constraint(equalTo: versionsScrollView.contentLayoutGuide.trailingAnchor),
            versionsStack.heightAnchor.constraint(equalTo: versionsScrollView.frameLayoutGuide.heightAnchor),
        ])

        heightConstraint = heightAnchor.constraint(equalToConstant: collapsedHeight)
        heightConstraint?.isActive = true

        // Ocultar sección expandible por defecto
        progressSlider.alpha   = 0
        progressLabel.alpha    = 0
        versionsScrollView.alpha = 0

        progressSlider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        toggleButton.addTarget(self, action: #selector(toggleExpand), for: .touchUpInside)

        updateProgress(0)
    }

    // MARK: - API pública

    /// Carga datos del escaneo: tiempo de inicio, fin y versiones guardadas.
    func configure(scanStart: Date, scanEnd: Date, versions: [SceneTimelineVersion]) {
        self.versions = versions
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        startTimeLabel.text = "▶ \(fmt.string(from: scanStart))"
        endTimeLabel.text   = "\(fmt.string(from: scanEnd)) ■"
        rebuildVersionDots()
    }

    /// Actualiza el progreso del slider de recorrido (0..1).
    func updateProgress(_ value: Float) {
        progress = value
        progressSlider.value = value
        let pct = Int(value * 100)
        progressLabel.text = "Recorrido \(pct)%"
    }

    // MARK: - Expand / Collapse

    @objc func toggleExpand() {
        isExpanded.toggle()
        UserDefaults.standard.set(isExpanded, forKey: Self.defaultsKeyExpanded)

        heightConstraint?.constant = isExpanded ? expandedHeight : collapsedHeight
        UIView.animate(withDuration: 0.28,
                       delay: 0,
                       usingSpringWithDamping: 0.82,
                       initialSpringVelocity: 0.3) {
            self.superview?.layoutIfNeeded()
            let a: CGFloat = self.isExpanded ? 1 : 0
            self.progressSlider.alpha    = a
            self.progressLabel.alpha     = a
            self.versionsScrollView.alpha = a
            let rot: CGFloat = self.isExpanded ? .pi : 0
            self.toggleButton.transform = CGAffineTransform(rotationAngle: rot)
        }
    }

    // MARK: - Versiones

    private func rebuildVersionDots() {
        versionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for v in versions {
            let dot = makeVersionDot(version: v)
            versionsStack.addArrangedSubview(dot)
        }
    }

    private func makeVersionDot(version: SceneTimelineVersion) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let dot = UIView()
        dot.backgroundColor = UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.9)
        dot.layer.cornerRadius = 6
        dot.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = version.label
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(dot)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            dot.topAnchor.constraint(equalTo: container.topAnchor),
            dot.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),

            label.topAnchor.constraint(equalTo: dot.bottomAnchor, constant: 2),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(versionTapped(_:)))
        container.addGestureRecognizer(tap)
        container.tag = versions.firstIndex(where: { $0.id == version.id }) ?? 0
        container.isUserInteractionEnabled = true
        return container
    }

    // MARK: - Acciones

    @objc private func sliderChanged(_ sender: UISlider) {
        progress = sender.value
        let pct = Int(sender.value * 100)
        progressLabel.text = "Recorrido \(pct)%"
        // Notificar al NavigationPlaybackController
        NotificationCenter.default.post(
            name: .sceneTimelineSeek,
            object: NSNumber(value: sender.value)
        )
    }

    @objc private func versionTapped(_ gesture: UITapGestureRecognizer) {
        guard let idx = gesture.view?.tag, idx < versions.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        NotificationCenter.default.post(
            name: .sceneTimelineVersionSelected,
            object: versions[idx]
        )
    }

    // MARK: - Observar progreso de playback

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPlaybackProgress(_:)),
            name: Self.playbackProgressNotification,
            object: nil
        )
    }

    @objc private func onPlaybackProgress(_ note: Notification) {
        guard let value = (note.object as? NSNumber)?.floatValue else { return }
        DispatchQueue.main.async { self.updateProgress(value) }
    }

    // MARK: - Persistencia

    private func restoreState() {
        isExpanded = UserDefaults.standard.bool(forKey: Self.defaultsKeyExpanded)
        if isExpanded {
            heightConstraint?.constant = expandedHeight
            progressSlider.alpha    = 1
            progressLabel.alpha     = 1
            versionsScrollView.alpha = 1
            toggleButton.transform  = CGAffineTransform(rotationAngle: .pi)
        }
    }

    // MARK: - Helper

    private static func makeTimeLabel() -> UILabel {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        l.textColor = UIColor.white.withAlphaComponent(0.75)
        l.text = "--:--:--"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let sceneTimelineSeek            = Notification.Name("mi_render_timelineSeek")
    static let sceneTimelineVersionSelected = Notification.Name("mi_render_timelineVersion")
}
