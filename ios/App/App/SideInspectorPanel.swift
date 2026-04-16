// SideInspectorPanel.swift
// Panel lateral deslizable (desde la derecha) con propiedades del objeto seleccionado.
// Auto-oculta cuando no hay selección activa.
// Persiste estado de visibilidad en UserDefaults.

import UIKit

// MARK: - InspectorItem

struct InspectorItem {
    let title:    String
    let value:    String
    let icon:     String   // SF Symbol
}

// MARK: - InspectorData

struct InspectorData {
    var objectName:         String = "Sin selección"
    var roomDimensions:     String = "—"
    var wallLength:         String = "—"
    var surfaceType:        String = "—"
    var semanticCategory:   String = "—"

    static let empty = InspectorData()

    var items: [InspectorItem] {[
        InspectorItem(title: "Dimensiones",  value: roomDimensions,   icon: "ruler"),
        InspectorItem(title: "Long. pared",  value: wallLength,       icon: "arrow.left.and.right"),
        InspectorItem(title: "Superficie",   value: surfaceType,      icon: "square.fill"),
        InspectorItem(title: "Semántica",    value: semanticCategory, icon: "tag.fill"),
    ]}
}

// MARK: - SideInspectorPanel

class SideInspectorPanel: UIView {

    // MARK: - Constantes

    private let panelWidth: CGFloat  = 240
    private let autoHideDelay: TimeInterval = 6.0
    private static let defaultsKey = "mi_render_inspector_visible"

    // MARK: - Estado

    private(set) var isVisible: Bool = false
    private var autoHideTimer: Timer?
    private var currentData: InspectorData = .empty

    // MARK: - Subvistas

    private let blurView: UIVisualEffectView = {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
        v.layer.cornerRadius = 16
        v.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        v.clipsToBounds = true
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let closeButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "xmark"), for: .normal)
        b.tintColor = UIColor.white.withAlphaComponent(0.7)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    private let stackView: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 8
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
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
        translatesAutoresizingMaskIntoConstraints = false

        // Blur container
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)

        let content = blurView.contentView

        // Header
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(headerView)

        headerView.addSubview(titleLabel)
        headerView.addSubview(closeButton)

        // Stack de propiedades
        content.addSubview(stackView)

        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            headerView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            headerView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 28),

            // Stack
            stackView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])

        closeButton.addTarget(self, action: #selector(hide), for: .touchUpInside)
        populate(with: .empty)
    }

    // MARK: - API pública

    func show(with data: InspectorData) {
        currentData = data
        populate(with: data)
        guard !isVisible else { return }
        isVisible = true
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)

        transform = CGAffineTransform(translationX: panelWidth, y: 0)
        UIView.animate(withDuration: 0.30,
                       delay: 0,
                       usingSpringWithDamping: 0.80,
                       initialSpringVelocity: 0.4) {
            self.transform = .identity
            self.alpha = 1
        }
        scheduleAutoHide()
    }

    func update(with data: InspectorData) {
        currentData = data
        populate(with: data)
        resetAutoHideTimer()
    }

    @objc func hide() {
        guard isVisible else { return }
        isVisible = false
        autoHideTimer?.invalidate()
        UserDefaults.standard.set(false, forKey: Self.defaultsKey)

        UIView.animate(withDuration: 0.22,
                       delay: 0,
                       options: [.curveEaseIn]) {
            self.transform = CGAffineTransform(translationX: self.panelWidth, y: 0)
            self.alpha = 0
        }
    }

    // MARK: - Populate

    private func populate(with data: InspectorData) {
        titleLabel.text = data.objectName

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Separador bajo título
        let sep = makeSeparator()
        stackView.addArrangedSubview(sep)

        for item in data.items {
            stackView.addArrangedSubview(makeRow(item: item))
        }
    }

    private func makeRow(item: InspectorItem) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let icon = UIImageView(image: UIImage(systemName: item.icon))
        icon.tintColor = UIColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 0.9)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLbl = UILabel()
        titleLbl.text = item.title
        titleLbl.font = .systemFont(ofSize: 11, weight: .regular)
        titleLbl.textColor = UIColor.white.withAlphaComponent(0.55)
        titleLbl.translatesAutoresizingMaskIntoConstraints = false

        let valueLbl = UILabel()
        valueLbl.text = item.value
        valueLbl.font = .systemFont(ofSize: 12, weight: .medium)
        valueLbl.textColor = .white
        valueLbl.textAlignment = .right
        valueLbl.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(titleLbl)
        container.addSubview(valueLbl)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            titleLbl.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            titleLbl.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            valueLbl.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLbl.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLbl.leadingAnchor.constraint(greaterThanOrEqualTo: titleLbl.trailingAnchor, constant: 4),
        ])
        return container
    }

    private func makeSeparator() -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    // MARK: - Auto-hide

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: autoHideDelay,
            repeats: false
        ) { [weak self] _ in self?.hide() }
    }

    private func resetAutoHideTimer() {
        if isVisible { scheduleAutoHide() }
    }
}
