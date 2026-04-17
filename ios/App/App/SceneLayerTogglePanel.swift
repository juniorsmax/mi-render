// SceneLayerTogglePanel.swift
// Panel inferior con dos filas de botones:
//   Fila 1 — Capas:  Mesh | Semantic | 2D Plan | 3D Plan | Walkthrough | Nodes
//   Fila 2 — Estilo: Wire | Solid | Sem. | Tex. | X-Ray
//
// Delega la selección de capa a SceneLayerManager.shared.switchMode(to:).
// Delega la selección de estilo a MeshRenderStyleManager.shared.currentStyle.
// Observa .sceneLayerDidChange y .meshRenderStyleDidChange.

import UIKit

class SceneLayerTogglePanel: UIView {

    // MARK: - Subvistas — fila de capas

    private var layerScrollView: UIScrollView!
    private var layerStackView:  UIStackView!
    private var modeButtons: [SceneLayerMode: UIButton] = [:]

    // MARK: - Subvistas — fila de estilos

    private var styleScrollView: UIScrollView!
    private var styleStackView:  UIStackView!
    private var styleButtons: [MeshRenderStyle: UIButton] = [:]

    // MARK: - Subvistas — botón Assets

    private var assetButton: UIButton!

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
        backgroundColor = .clear
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

        // ---- Fila 1: Capas ----
        layerScrollView = UIScrollView()
        layerScrollView.showsHorizontalScrollIndicator = false
        layerScrollView.alwaysBounceHorizontal = true
        layerScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layerScrollView)

        layerStackView = UIStackView()
        layerStackView.axis = .horizontal
        layerStackView.spacing = 6
        layerStackView.alignment = .center
        layerStackView.translatesAutoresizingMaskIntoConstraints = false
        layerScrollView.addSubview(layerStackView)

        for mode in SceneLayerMode.allCases {
            let btn = makeModeButton(for: mode)
            layerStackView.addArrangedSubview(btn)
            modeButtons[mode] = btn
        }

        // Botón Assets — al final de la fila de capas
        assetButton = makeAssetButton()
        layerStackView.addArrangedSubview(assetButton)

        // ---- Separador ----
        let separator = UIView()
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // ---- Fila 2: Estilos ----
        styleScrollView = UIScrollView()
        styleScrollView.showsHorizontalScrollIndicator = false
        styleScrollView.alwaysBounceHorizontal = true
        styleScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(styleScrollView)

        styleStackView = UIStackView()
        styleStackView.axis = .horizontal
        styleStackView.spacing = 5
        styleStackView.alignment = .center
        styleStackView.translatesAutoresizingMaskIntoConstraints = false
        styleScrollView.addSubview(styleStackView)

        for style in MeshRenderStyle.allCases {
            let btn = makeStyleButton(for: style)
            styleStackView.addArrangedSubview(btn)
            styleButtons[style] = btn
        }

        // ---- Constraints ----
        NSLayoutConstraint.activate([
            // Fila 1
            layerScrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            layerScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            layerScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            layerScrollView.heightAnchor.constraint(equalToConstant: 36),

            layerStackView.topAnchor.constraint(equalTo: layerScrollView.contentLayoutGuide.topAnchor),
            layerStackView.bottomAnchor.constraint(equalTo: layerScrollView.contentLayoutGuide.bottomAnchor),
            layerStackView.leadingAnchor.constraint(equalTo: layerScrollView.contentLayoutGuide.leadingAnchor),
            layerStackView.trailingAnchor.constraint(equalTo: layerScrollView.contentLayoutGuide.trailingAnchor),
            layerStackView.heightAnchor.constraint(equalTo: layerScrollView.frameLayoutGuide.heightAnchor),

            // Separador
            separator.topAnchor.constraint(equalTo: layerScrollView.bottomAnchor, constant: 5),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            // Fila 2
            styleScrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 5),
            styleScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            styleScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            styleScrollView.heightAnchor.constraint(equalToConstant: 30),

            styleStackView.topAnchor.constraint(equalTo: styleScrollView.contentLayoutGuide.topAnchor),
            styleStackView.bottomAnchor.constraint(equalTo: styleScrollView.contentLayoutGuide.bottomAnchor),
            styleStackView.leadingAnchor.constraint(equalTo: styleScrollView.contentLayoutGuide.leadingAnchor),
            styleStackView.trailingAnchor.constraint(equalTo: styleScrollView.contentLayoutGuide.trailingAnchor),
            styleStackView.heightAnchor.constraint(equalTo: styleScrollView.frameLayoutGuide.heightAnchor),
        ])

        updateSelectedLayer(SceneLayerManager.shared.currentMode)
        updateSelectedStyle(MeshRenderStyleManager.shared.currentStyle)
    }

    // MARK: - Fábrica de botones — Capas

    private func makeModeButton(for mode: SceneLayerMode) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = mode.displayName
        config.image = UIImage(systemName: mode.systemImage)
        config.imagePadding = 4
        config.imagePlacement = .leading
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.10)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)

        let button = UIButton(configuration: config)
        button.tag = SceneLayerMode.allCases.firstIndex(of: mode) ?? 0
        button.addTarget(self, action: #selector(layerButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    // MARK: - Fábrica de botones — Estilos

    private func makeStyleButton(for style: MeshRenderStyle) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = style.displayName
        config.image = UIImage(systemName: style.systemImage)
        config.imagePadding = 3
        config.imagePlacement = .leading
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        config.baseForegroundColor = UIColor.white.withAlphaComponent(0.85)
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.08)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

        var titleAttr = AttributeContainer()
        titleAttr[AttributeScopes.UIKitAttributes.FontAttribute.self] =
            UIFont.systemFont(ofSize: 11, weight: .medium)
        config.attributedTitle = AttributedString(style.displayName, attributes: titleAttr)

        let button = UIButton(configuration: config)
        button.tag = MeshRenderStyle.allCases.firstIndex(of: style) ?? 0
        button.addTarget(self, action: #selector(styleButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    // MARK: - Fábrica de botón — Assets

    private func makeAssetButton() -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = "Assets"
        config.image = UIImage(systemName: "cube.transparent.fill")
        config.imagePadding = 4
        config.imagePlacement = .leading
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 0.88)
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)

        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(assetButtonTapped), for: .touchUpInside)
        return button
    }

    // MARK: - Acciones

    @objc private func layerButtonTapped(_ sender: UIButton) {
        guard sender.tag < SceneLayerMode.allCases.count else { return }
        SceneLayerManager.shared.switchMode(to: SceneLayerMode.allCases[sender.tag])
    }

    @objc private func styleButtonTapped(_ sender: UIButton) {
        guard sender.tag < MeshRenderStyle.allCases.count else { return }
        MeshRenderStyleManager.shared.currentStyle = MeshRenderStyle.allCases[sender.tag]
    }

    @objc private func assetButtonTapped() {
        NotificationCenter.default.post(name: .assetPlacementRequested, object: nil)
    }

    // MARK: - Observar cambios

    private func observeChanges() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(onLayerChanged(_:)),
            name: .sceneLayerDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(onStyleChanged(_:)),
            name: .meshRenderStyleDidChange, object: nil
        )
    }

    @objc private func onLayerChanged(_ note: Notification) {
        guard let mode = note.object as? SceneLayerMode else { return }
        updateSelectedLayer(mode)
    }

    @objc private func onStyleChanged(_ note: Notification) {
        guard let style = note.object as? MeshRenderStyle else { return }
        updateSelectedStyle(style)
    }

    // MARK: - Estado visual

    func updateSelectedLayer(_ mode: SceneLayerMode) {
        for (m, btn) in modeButtons {
            var config = btn.configuration ?? UIButton.Configuration.filled()
            config.baseBackgroundColor = (m == mode)
                ? UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.92)
                : UIColor.white.withAlphaComponent(0.10)
            config.baseForegroundColor = .white
            btn.configuration = config
        }
    }

    func updateSelectedStyle(_ style: MeshRenderStyle) {
        for (s, btn) in styleButtons {
            var config = btn.configuration ?? UIButton.Configuration.filled()
            let isActive = (s == style)
            config.baseBackgroundColor = isActive
                ? UIColor(red: 0.55, green: 0.25, blue: 0.95, alpha: 0.88)
                : UIColor.white.withAlphaComponent(0.08)
            config.baseForegroundColor = UIColor.white.withAlphaComponent(isActive ? 1.0 : 0.65)
            btn.configuration = config
        }
    }
}
