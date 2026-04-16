// RadialModeSelector.swift
// Selector radial flotante con 8 modos.
// Botón central → expande ítems en círculo → colapsa al seleccionar.
// Integra con SceneLayerManager y emite callbacks para acciones de app.

import UIKit

// MARK: - RadialMode

enum RadialMode: String, CaseIterable {
    case scan    = "scan"
    case explore = "explore"
    case edit    = "edit"
    case plan    = "plan"
    case walk    = "walk"
    case nodes   = "nodes"
    case ai      = "ai"
    case export  = "export"

    var displayName: String {
        switch self {
        case .scan:    return "Scan"
        case .explore: return "Explore"
        case .edit:    return "Edit"
        case .plan:    return "Plan"
        case .walk:    return "Walk"
        case .nodes:   return "Nodes"
        case .ai:      return "AI"
        case .export:  return "Export"
        }
    }

    var systemImage: String {
        switch self {
        case .scan:    return "camera.fill"
        case .explore: return "cube.fill"
        case .edit:    return "pencil"
        case .plan:    return "building.2.fill"
        case .walk:    return "play.circle.fill"
        case .nodes:   return "dot.radiowaves.left.and.right"
        case .ai:      return "brain"
        case .export:  return "square.and.arrow.up"
        }
    }

    /// Modos que se mapean directamente a SceneLayerMode.
    var sceneLayerMode: SceneLayerMode? {
        switch self {
        case .explore: return .meshRaw
        case .plan:    return .floorplan3D
        case .walk:    return .walkthrough
        case .nodes:   return .panoramaNodes
        default:       return nil
        }
    }
}

// MARK: - RadialModeSelectorDelegate

protocol RadialModeSelectorDelegate: AnyObject {
    func radialSelector(_ selector: RadialModeSelector, didSelect mode: RadialMode)
}

// MARK: - RadialModeSelector

class RadialModeSelector: UIView {

    // MARK: - Constantes

    private let centerButtonSize: CGFloat = 56
    private let itemButtonSize:   CGFloat = 46
    private let expandRadius:     CGFloat = 120

    // MARK: - Estado

    private(set) var isExpanded: Bool = false
    private var itemButtons: [RadialMode: UIButton] = [:]
    weak var delegate: RadialModeSelectorDelegate?

    // MARK: - Subvistas

    private let centerButton: UIButton = {
        let b = UIButton(type: .custom)
        b.backgroundColor = UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.95)
        b.layer.cornerRadius = 28
        b.layer.shadowColor  = UIColor.black.cgColor
        b.layer.shadowRadius = 8
        b.layer.shadowOpacity = 0.40
        b.layer.shadowOffset  = CGSize(width: 0, height: 3)
        b.setImage(UIImage(systemName: "plus"), for: .normal)
        b.tintColor = .white
        b.imageView?.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        return b
    }()

    private let dimOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        v.alpha = 0
        v.isUserInteractionEnabled = true
        return v
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = true

        // Dim overlay (toca para cerrar)
        dimOverlay.frame = UIScreen.main.bounds
        addSubview(dimOverlay)
        dimOverlay.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(collapse))
        )

        // Items radiales
        for mode in RadialMode.allCases {
            let btn = makeItemButton(for: mode)
            btn.alpha = 0
            btn.transform = .identity
            addSubview(btn)
            itemButtons[mode] = btn
        }

        // Botón central
        centerButton.frame = CGRect(
            x: -centerButtonSize / 2,
            y: -centerButtonSize / 2,
            width: centerButtonSize,
            height: centerButtonSize
        )
        centerButton.addTarget(self, action: #selector(toggleExpand), for: .touchUpInside)
        addSubview(centerButton)
    }

    private func makeItemButton(for mode: RadialMode) -> UIButton {
        let b = UIButton(type: .custom)
        b.frame = CGRect(
            x: -itemButtonSize / 2,
            y: -itemButtonSize / 2,
            width: itemButtonSize,
            height: itemButtonSize
        )
        b.backgroundColor = UIColor(white: 0.12, alpha: 0.92)
        b.layer.cornerRadius = itemButtonSize / 2
        b.layer.borderColor  = UIColor.white.withAlphaComponent(0.18).cgColor
        b.layer.borderWidth  = 1

        // Icono
        b.setImage(UIImage(systemName: mode.systemImage), for: .normal)
        b.tintColor = .white
        b.imageView?.preferredSymbolConfiguration =
            UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        // Etiqueta debajo del icono
        let label = UILabel()
        label.text = mode.displayName
        label.font = .systemFont(ofSize: 9, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: b.centerXAnchor),
            label.topAnchor.constraint(equalTo: b.bottomAnchor, constant: 4),
        ])

        b.tag = RadialMode.allCases.firstIndex(of: mode) ?? 0
        b.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
        return b
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        dimOverlay.frame = superview?.bounds ?? UIScreen.main.bounds
    }

    // MARK: - Expand / Collapse

    @objc func toggleExpand() {
        isExpanded ? collapse() : expand()
    }

    @objc func expand() {
        guard !isExpanded else { return }
        isExpanded = true

        // Rotar ícono central
        UIView.animate(withDuration: 0.25, delay: 0,
                       usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.centerButton.transform = CGAffineTransform(rotationAngle: .pi / 4)
            self.dimOverlay.alpha = 1
        }

        // Expandir ítems en círculo
        let count = RadialMode.allCases.count
        for (i, mode) in RadialMode.allCases.enumerated() {
            guard let btn = itemButtons[mode] else { continue }
            let angle: CGFloat = CGFloat(i) * (2 * .pi / CGFloat(count)) - .pi / 2
            let tx = expandRadius * cos(angle)
            let ty = expandRadius * sin(angle)

            UIView.animate(
                withDuration: 0.30,
                delay: Double(i) * 0.025,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0.4,
                options: [],
                animations: {
                    btn.alpha = 1
                    btn.transform = CGAffineTransform(translationX: tx, y: ty)
                }
            )
        }
    }

    @objc func collapse() {
        guard isExpanded else { return }
        isExpanded = false

        UIView.animate(withDuration: 0.20) {
            self.centerButton.transform = .identity
            self.dimOverlay.alpha = 0
        }

        for (_, btn) in itemButtons {
            UIView.animate(withDuration: 0.20,
                           delay: 0,
                           options: [.curveEaseIn]) {
                btn.alpha = 0
                btn.transform = .identity
            }
        }
    }

    // MARK: - Selección

    @objc private func itemTapped(_ sender: UIButton) {
        guard sender.tag < RadialMode.allCases.count else { return }
        let mode = RadialMode.allCases[sender.tag]

        // Feedback háptico
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Actualizar botón central con ícono del modo seleccionado
        centerButton.setImage(UIImage(systemName: mode.systemImage), for: .normal)

        // Integrar con SceneLayerManager si el modo tiene mapeo
        if let layerMode = mode.sceneLayerMode {
            SceneLayerManager.shared.switchMode(to: layerMode)
        }

        // Emitir al delegate para acciones de app (scan, edit, ai, export)
        delegate?.radialSelector(self, didSelect: mode)

        collapse()
    }

    // MARK: - Highlight del modo activo

    func highlightMode(_ layerMode: SceneLayerMode) {
        for (radialMode, btn) in itemButtons {
            let active = (radialMode.sceneLayerMode == layerMode)
            btn.backgroundColor = active
                ? UIColor(red: 0.15, green: 0.55, blue: 1.0, alpha: 0.92)
                : UIColor(white: 0.12, alpha: 0.92)
        }
    }
}
