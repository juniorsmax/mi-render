// ObjectContextMenu.swift
// Menú contextual flotante que aparece al seleccionar una entidad en SceneViewer.
// Opciones: Move | Replace Material | Measure | Export | Delete
// Desaparece al tocar fuera o al seleccionar una acción.

import UIKit

// MARK: - ObjectContextAction

enum ObjectContextAction: String, CaseIterable {
    case move            = "move"
    case replaceMaterial = "replaceMaterial"
    case measure         = "measure"
    case export          = "export"
    case delete          = "delete"

    var displayName: String {
        switch self {
        case .move:            return "Move"
        case .replaceMaterial: return "Material"
        case .measure:         return "Measure"
        case .export:          return "Export"
        case .delete:          return "Delete"
        }
    }

    var systemImage: String {
        switch self {
        case .move:            return "move.3d"
        case .replaceMaterial: return "paintbrush.fill"
        case .measure:         return "ruler"
        case .export:          return "square.and.arrow.up"
        case .delete:          return "trash"
        }
    }

    var isDestructive: Bool { self == .delete }
}

// MARK: - ObjectContextMenuDelegate

protocol ObjectContextMenuDelegate: AnyObject {
    func contextMenu(_ menu: ObjectContextMenu, didSelect action: ObjectContextAction)
    func contextMenuDidDismiss(_ menu: ObjectContextMenu)
}

// MARK: - ObjectContextMenu

class ObjectContextMenu: UIView {

    // MARK: - Propiedades

    weak var delegate: ObjectContextMenuDelegate?
    private let buttonHeight: CGFloat = 42
    private let menuWidth:    CGFloat = 160
    private let cornerRadius: CGFloat = 12

    // MARK: - Subvistas

    private let blurView: UIVisualEffectView = {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterialDark))
        v.layer.cornerRadius = 12
        v.clipsToBounds = true
        return v
    }()

    private let stackView: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let dimBackground: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
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
        layer.shadowColor   = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius  = 12
        layer.shadowOffset  = CGSize(width: 0, height: 4)

        addSubview(blurView)
        blurView.contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -6),
            stackView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
        ])

        for (i, action) in ObjectContextAction.allCases.enumerated() {
            let row = makeRow(action: action)
            stackView.addArrangedSubview(row)

            // Separador entre ítems (excepto el último)
            if i < ObjectContextAction.allCases.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.white.withAlphaComponent(0.10)
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                stackView.addArrangedSubview(sep)
            }
        }
    }

    private func makeRow(action: ObjectContextAction) -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: action.systemImage))
        icon.tintColor = action.isDestructive
            ? UIColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.9)
            : UIColor.white.withAlphaComponent(0.85)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = action.displayName
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = action.isDestructive
            ? UIColor(red: 1.0, green: 0.30, blue: 0.30, alpha: 0.95)
            : .white
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
        ])

        // Tap
        let tap = UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        container.addGestureRecognizer(tap)
        container.tag = ObjectContextAction.allCases.firstIndex(of: action) ?? 0
        container.isUserInteractionEnabled = true

        // Highlight en press
        let press = UILongPressGestureRecognizer(target: self, action: #selector(rowPressed(_:)))
        press.minimumPressDuration = 0
        container.addGestureRecognizer(press)

        return container
    }

    // MARK: - Mostrar / Ocultar

    /// Muestra el menú en `point` dentro de `parentView`.
    func show(at point: CGPoint, in parentView: UIView) {
        // Dim background invisible (toca fuera → cerrar)
        dimBackground.frame = parentView.bounds
        parentView.addSubview(dimBackground)
        dimBackground.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(dismiss))
        )

        // Calcular tamaño
        let menuHeight = CGFloat(ObjectContextAction.allCases.count) * buttonHeight
            + CGFloat(ObjectContextAction.allCases.count - 1) * 0.5
            + 12
        frame = CGRect(
            x: min(point.x, parentView.bounds.width - menuWidth - 8),
            y: min(point.y, parentView.bounds.height - menuHeight - 8),
            width:  menuWidth,
            height: menuHeight
        )
        blurView.frame = bounds

        parentView.addSubview(self)

        // Animación de aparición
        transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        alpha = 0
        UIView.animate(withDuration: 0.22,
                       delay: 0,
                       usingSpringWithDamping: 0.72,
                       initialSpringVelocity: 0.5) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    @objc func dismiss() {
        UIView.animate(withDuration: 0.15,
                       animations: {
            self.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            self.alpha = 0
        }) { _ in
            self.removeFromSuperview()
            self.dimBackground.removeFromSuperview()
            self.delegate?.contextMenuDidDismiss(self)
        }
    }

    // MARK: - Acciones

    @objc private func rowTapped(_ gesture: UITapGestureRecognizer) {
        guard let idx = gesture.view?.tag,
              idx < ObjectContextAction.allCases.count else { return }
        let action = ObjectContextAction.allCases[idx]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.contextMenu(self, didSelect: action)
        dismiss()
    }

    @objc private func rowPressed(_ gesture: UILongPressGestureRecognizer) {
        guard let view = gesture.view else { return }
        UIView.animate(withDuration: 0.10) {
            view.backgroundColor = gesture.state == .began
                ? UIColor.white.withAlphaComponent(0.08)
                : .clear
        }
    }
}
