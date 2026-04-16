// SceneLayerTogglePanel.swift
// Panel de capas de visualización con 6 botones:
// Mesh | Semantic | 2D Plan | 3D Plan | Walkthrough | Nodes
//
// Se monta en la parte inferior de SceneViewerViewController.
// Delega la selección a SceneLayerManager.shared.switchMode(to:).
// Actualiza estado visual al recibir .sceneLayerDidChange.

import UIKit

class SceneLayerTogglePanel: UIView {

    // MARK: - Subvistas

    private var scrollView: UIScrollView!
    private var stackView:  UIStackView!
    private var modeButtons: [SceneLayerMode: UIButton] = [:]

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        observeChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        observeChanges()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func setup() {
        backgroundColor = UIColor(white: 0.05, alpha: 0.88)
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        // Blur de fondo
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blurView.layer.cornerRadius = 16
        blurView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        blurView.clipsToBounds = true
        insertSubview(blurView, at: 0)

        scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for mode in SceneLayerMode.allCases {
            let btn = makeButton(for: mode)
            stackView.addArrangedSubview(btn)
            modeButtons[mode] = btn
        }

        updateSelectedState(for: SceneLayerManager.shared.currentMode)
    }

    private func makeButton(for mode: SceneLayerMode) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = mode.displayName
        config.image = UIImage(systemName: mode.systemImage)
        config.imagePadding = 4
        config.imagePlacement = .leading
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.10)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)

        let button = UIButton(configuration: config)
        button.tag = SceneLayerMode.allCases.firstIndex(of: mode) ?? 0
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        return button
    }

    // MARK: - Acciones

    @objc private func buttonTapped(_ sender: UIButton) {
        guard sender.tag < SceneLayerMode.allCases.count else { return }
        let mode = SceneLayerMode.allCases[sender.tag]
        SceneLayerManager.shared.switchMode(to: mode)
    }

    // MARK: - Observar cambios

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onLayerChanged(_:)),
            name: .sceneLayerDidChange,
            object: nil
        )
    }

    @objc private func onLayerChanged(_ note: Notification) {
        guard let mode = note.object as? SceneLayerMode else { return }
        updateSelectedState(for: mode)
    }

    // MARK: - Estado visual

    func updateSelectedState(for mode: SceneLayerMode) {
        for (m, btn) in modeButtons {
            let selected = (m == mode)
            var config = btn.configuration ?? UIButton.Configuration.filled()
            config.baseBackgroundColor = selected
                ? UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.92)
                : UIColor.white.withAlphaComponent(0.10)
            config.baseForegroundColor = .white
            btn.configuration = config
        }
    }
}
