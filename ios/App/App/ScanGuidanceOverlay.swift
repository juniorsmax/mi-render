// ScanGuidanceOverlay.swift
// Overlay de guía de escaneo estilo Polycam — iOS 16+

import UIKit
import RoomPlan

// MARK: - BadgeView helper

private struct BadgeView {
    let container: UIView
    let label: UILabel
}

// MARK: - ScanGuidanceOverlay

final class ScanGuidanceOverlay: UIView {

    // MARK: Callbacks

    var onClose: (() -> Void)?
    var onPause: (() -> Void)?
    var onDone:  (() -> Void)?
    var onTorch: (() -> Void)?

    // MARK: Private references

    private weak var progressRingLayer: CAShapeLayer?
    private weak var progressLabel: UILabel?
    private weak var guidanceLabel: UILabel?
    private weak var planImageView: UIImageView!
    private weak var pauseButton: UIButton?
    private weak var torchButton: UIButton?

    private var floorBadge: BadgeView?
    private var wallBadge:  BadgeView?
    private var ceilBadge:  BadgeView?
    private var doorBadge:  BadgeView?
    private var winBadge:   BadgeView?

    // Métricas en tiempo real (segunda fila)
    private weak var volLabel:    UILabel?
    private weak var heightLabel: UILabel?
    private weak var perimLabel:  UILabel?

    private var isTorchOn: Bool = false

    // MARK: Init

    init(frame: CGRect, topInset: CGFloat, botInset: CGFloat) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupUI(topInset: topInset, botInset: botInset)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // MARK: Setup

    private func setupUI(topInset: CGFloat, botInset: CGFloat) {
        let w = bounds.width
        let topBarH: CGFloat = topInset + 58
        let botBarH: CGFloat = 96 + botInset

        // ── Top bar ──────────────────────────────────────────────────────────

        let topBar = UIView(frame: CGRect(x: 0, y: 0, width: w, height: topBarH))
        topBar.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        addSubview(topBar)

        // Progress ring
        let ringSize: CGFloat = 56
        let ringView = UIView(frame: CGRect(x: 16, y: topInset + 1, width: ringSize, height: ringSize))
        ringView.backgroundColor = .clear
        topBar.addSubview(ringView)

        let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
        let radius = (ringSize - 10) / 2
        let circlePath = UIBezierPath(
            arcCenter: center, radius: radius,
            startAngle: -.pi / 2, endAngle: 3 * (.pi / 2), clockwise: true
        )

        let trackLayer = CAShapeLayer()
        trackLayer.path        = circlePath.cgPath
        trackLayer.strokeColor = UIColor.white.withAlphaComponent(0.2).cgColor
        trackLayer.fillColor   = UIColor.clear.cgColor
        trackLayer.lineWidth   = 5
        ringView.layer.addSublayer(trackLayer)

        let fillLayer = CAShapeLayer()
        fillLayer.path        = circlePath.cgPath
        fillLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        fillLayer.fillColor   = UIColor.clear.cgColor
        fillLayer.lineWidth   = 5
        fillLayer.lineCap     = .round
        fillLayer.strokeEnd   = 0
        ringView.layer.addSublayer(fillLayer)
        progressRingLayer = fillLayer

        let pctLabel = UILabel(frame: CGRect(x: 0, y: 0, width: ringSize, height: ringSize))
        pctLabel.textAlignment = .center
        pctLabel.font          = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        pctLabel.textColor     = .white
        pctLabel.text          = "0%"
        ringView.addSubview(pctLabel)
        progressLabel = pctLabel

        // Torch button
        let torch = makeCircleBtn(systemName: "flashlight.off.fill")
        torch.frame = CGRect(x: w - 108, y: topInset + 7, width: 44, height: 44)
        torch.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        topBar.addSubview(torch)
        torchButton = torch

        // Close button
        let close = makeCircleBtn(systemName: "xmark")
        close.frame = CGRect(x: w - 58, y: topInset + 7, width: 44, height: 44)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topBar.addSubview(close)

        // Guidance label
        let labelX: CGFloat = 88
        let labelW = w - 108 - labelX
        let gLabel = UILabel(frame: CGRect(x: labelX, y: topInset + 1, width: labelW, height: 58))
        gLabel.textAlignment   = .center
        gLabel.font            = .systemFont(ofSize: 13, weight: .medium)
        gLabel.textColor       = UIColor.white.withAlphaComponent(0.9)
        gLabel.numberOfLines   = 2
        gLabel.adjustsFontSizeToFitWidth = true
        gLabel.minimumScaleFactor = 0.7
        gLabel.text = "Mueve el dispositivo lentamente"
        topBar.addSubview(gLabel)
        guidanceLabel = gLabel

        // ── Bottom bar ────────────────────────────────────────────────────────

        let botBarY = bounds.height - botBarH
        let botBar = UIView(frame: CGRect(x: 0, y: botBarY, width: w, height: botBarH))
        botBar.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        addSubview(botBar)

        // Plan preview
        let planIV = UIImageView(frame: CGRect(x: 12, y: 8, width: 80, height: 80))
        planIV.contentMode    = .scaleAspectFill
        planIV.clipsToBounds  = true
        planIV.layer.cornerRadius = 10
        planIV.backgroundColor  = UIColor.black.withAlphaComponent(0.4)
        planIV.layer.borderWidth = 1
        planIV.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        botBar.addSubview(planIV)
        planImageView = planIV

        // Pause button
        let pauseBtn = UIButton(type: .system)
        let pauseConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .thin)
        pauseBtn.setImage(UIImage(systemName: "pause.circle", withConfiguration: pauseConfig), for: .normal)
        pauseBtn.tintColor = .white
        let pauseSize: CGFloat = 60
        pauseBtn.frame = CGRect(x: (w - pauseSize) / 2, y: 17, width: pauseSize, height: pauseSize)
        pauseBtn.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        botBar.addSubview(pauseBtn)
        pauseButton = pauseBtn

        // Done button
        let doneBtn = UIButton(type: .system)
        doneBtn.frame = CGRect(x: w - 122, y: 27, width: 106, height: 40)
        doneBtn.layer.cornerRadius = 20
        doneBtn.clipsToBounds = true
        doneBtn.backgroundColor = UIColor(red: 0.18, green: 0.83, blue: 0.75, alpha: 0.9)
        let doneImg = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        doneBtn.setImage(doneImg, for: .normal)
        doneBtn.setTitle("  Hecho", for: .normal)
        doneBtn.tintColor = .white
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        botBar.addSubview(doneBtn)

        // ── Barra de métricas en tiempo real (volumen · altura · perímetro) ─────
        //    Posición: 76 pt por encima del bottom bar → espacio para dos strips

        let metricsBarH: CGFloat = 32
        let metricsBarY = botBarY - 76
        let metricsBar = UIView(frame: CGRect(x: 0, y: metricsBarY,
                                              width: w, height: metricsBarH))
        metricsBar.backgroundColor = UIColor.black.withAlphaComponent(0.60)
        addSubview(metricsBar)

        let metricDefs: [(String, String)] = [
            ("cube.fill",    "Vol."),
            ("ruler",        "Alt."),
            ("arrow.triangle.turn.up.right.diamond", "Per."),
        ]
        var metricLabels: [UILabel] = []
        var totalMetricW: CGFloat = 0
        var metricViews: [(UIView, UILabel)] = []

        for (icon, text) in metricDefs {
            let (container, valueLabel) = makeMetricBadge(icon: icon, labelText: text)
            totalMetricW += container.frame.width
            metricViews.append((container, valueLabel))
            metricLabels.append(valueLabel)
        }
        let mSpacing: CGFloat = 10
        totalMetricW += mSpacing * CGFloat(metricDefs.count - 1)
        var mX = (w - totalMetricW) / 2
        for (view, _) in metricViews {
            view.frame.origin.x = mX
            view.frame.origin.y = (metricsBarH - view.frame.height) / 2
            metricsBar.addSubview(view)
            mX += view.frame.width + mSpacing
        }
        volLabel    = metricLabels[0]
        heightLabel = metricLabels[1]
        perimLabel  = metricLabels[2]

        // ── Surface badges strip ───────────────────────────────────────────────

        let stripH: CGFloat = 32
        let stripY = botBarY - 40
        let stripView = UIView(frame: CGRect(x: 0, y: stripY, width: w, height: stripH))
        stripView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        addSubview(stripView)

        let badgeData: [(icon: String, text: String, color: UIColor)] = [
            ("square.fill",              "Suelo",    UIColor(red: 0.18, green: 0.83, blue: 0.75, alpha: 1)),
            ("rectangle.portrait.fill",  "Paredes",  UIColor.white),
            ("rectangle.fill",           "Techo",    UIColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1)),
            ("door.left.hand.closed",    "Puertas",  UIColor(red: 0.29, green: 0.87, blue: 0.50, alpha: 1)),
            ("window.casement",          "Ventanas", UIColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1)),
        ]

        var createdBadges: [BadgeView] = []
        var totalBadgeW: CGFloat = 0
        var tempViews: [(UIView, BadgeView)] = []

        for item in badgeData {
            let bv = makeBadge(icon: item.icon, text: item.text, color: item.color)
            let bw = bv.container.frame.width
            totalBadgeW += bw
            tempViews.append((bv.container, bv))
            createdBadges.append(bv)
        }

        let spacing: CGFloat = 6
        totalBadgeW += spacing * CGFloat(badgeData.count - 1)
        var curX = (w - totalBadgeW) / 2

        for (view, bv) in tempViews {
            view.frame.origin.x = curX
            view.frame.origin.y = (stripH - view.frame.height) / 2
            stripView.addSubview(view)
            curX += view.frame.width + spacing
            _ = bv
        }

        floorBadge = createdBadges[0]
        wallBadge  = createdBadges[1]
        ceilBadge  = createdBadges[2]
        doorBadge  = createdBadges[3]
        winBadge   = createdBadges[4]
    }

    // MARK: Badge factory

    private func makeBadge(icon: String, text: String, color: UIColor) -> BadgeView {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.62)
        container.layer.cornerRadius = 12
        container.clipsToBounds = true

        let iconCfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        let iconView = UIImageView(image: UIImage(systemName: icon, withConfiguration: iconCfg))
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit

        let textLabel = UILabel()
        textLabel.font = .systemFont(ofSize: 10, weight: .medium)
        textLabel.textColor = color
        textLabel.text = text

        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        valueLabel.text = "—"

        iconView.sizeToFit()
        textLabel.sizeToFit()
        valueLabel.sizeToFit()

        let iconSz: CGFloat = 14
        let pad: CGFloat = 8
        let gap: CGFloat = 3
        let totalW = pad + iconSz + gap + textLabel.frame.width + gap + valueLabel.frame.width + pad
        let h: CGFloat = 24

        container.frame = CGRect(x: 0, y: 0, width: totalW, height: h)

        var cx: CGFloat = pad
        iconView.frame = CGRect(x: cx, y: (h - iconSz) / 2, width: iconSz, height: iconSz)
        container.addSubview(iconView)
        cx += iconSz + gap

        textLabel.frame = CGRect(x: cx, y: (h - textLabel.frame.height) / 2,
                                  width: textLabel.frame.width, height: textLabel.frame.height)
        container.addSubview(textLabel)
        cx += textLabel.frame.width + gap

        valueLabel.frame = CGRect(x: cx, y: (h - valueLabel.frame.height) / 2,
                                   width: valueLabel.frame.width, height: valueLabel.frame.height)
        container.addSubview(valueLabel)

        return BadgeView(container: container, label: valueLabel)
    }

    // MARK: Metric badge factory (icon + texto fijo + valor dinámico)

    private func makeMetricBadge(icon: String, labelText: String) -> (UIView, UILabel) {
        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        container.layer.cornerRadius = 10
        container.clipsToBounds = true

        let iconCfg  = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        let iconView = UIImageView(image: UIImage(systemName: icon, withConfiguration: iconCfg))
        iconView.tintColor = UIColor(red: 0.18, green: 0.83, blue: 0.75, alpha: 1) // teal
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.font      = .systemFont(ofSize: 9, weight: .medium)
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        titleLabel.text      = labelText

        let valueLabel = UILabel()
        valueLabel.font      = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.text      = "—"

        iconView.sizeToFit(); titleLabel.sizeToFit(); valueLabel.sizeToFit()

        let iconSz: CGFloat = 12
        let pad: CGFloat = 7
        let gap: CGFloat = 3
        let totalW = pad + iconSz + gap + titleLabel.frame.width + gap + valueLabel.frame.width + pad
        let h: CGFloat = 22
        container.frame = CGRect(x: 0, y: 0, width: totalW, height: h)

        var cx: CGFloat = pad
        iconView.frame = CGRect(x: cx, y: (h - iconSz) / 2, width: iconSz, height: iconSz)
        container.addSubview(iconView); cx += iconSz + gap
        titleLabel.frame = CGRect(x: cx, y: (h - titleLabel.frame.height) / 2,
                                   width: titleLabel.frame.width, height: titleLabel.frame.height)
        container.addSubview(titleLabel); cx += titleLabel.frame.width + gap
        valueLabel.frame = CGRect(x: cx, y: (h - valueLabel.frame.height) / 2,
                                   width: valueLabel.frame.width, height: valueLabel.frame.height)
        container.addSubview(valueLabel)

        return (container, valueLabel)
    }

    // MARK: Circle button factory

    private func makeCircleBtn(systemName: String) -> UIButton {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        btn.setImage(UIImage(systemName: systemName, withConfiguration: cfg), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        btn.layer.cornerRadius = 22
        btn.clipsToBounds = true
        return btn
    }

    // MARK: Actions

    @objc private func closeTapped() { onClose?() }
    @objc private func pauseTapped() { onPause?() }
    @objc private func doneTapped()  { onDone?() }
    @objc private func torchTapped() { onTorch?() }

    // MARK: Public API

    func updateProgress(_ p: Float, guidance: String) {
        let clamped = max(0, min(1, p))

        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.toValue            = CGFloat(clamped)
        anim.duration           = 0.6
        anim.timingFunction     = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode           = .forwards
        anim.isRemovedOnCompletion = false
        progressRingLayer?.add(anim, forKey: "progress")

        progressLabel?.text = "\(Int(clamped * 100))%"

        let color: UIColor = clamped > 0.8
            ? UIColor(red: 0.18, green: 0.83, blue: 0.75, alpha: 1)
            : clamped > 0.4
            ? UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 1)
            : UIColor.white.withAlphaComponent(0.5)
        progressRingLayer?.strokeColor = color.cgColor

        guidanceLabel?.text = guidance
    }

    // Actualiza la barra de métricas en tiempo real (volumen · altura · perímetro)
    func updateLiveMetrics(volume: Float, height: Float, perimeter: Float) {
        if volume > 0.01 {
            volLabel?.text = String(format: "%.1fm³", volume)
        }
        if height > 0.1 {
            heightLabel?.text = String(format: "%.2fm", height)
        }
        if perimeter > 0.1 {
            perimLabel?.text = String(format: "%.1fm", perimeter)
        }
    }

    func updateSurfaces(_ s: MeshSurfaces, doors: Int, windows: Int) {
        floorBadge?.label.text = String(format: "%.1fm²", s.floor)
        let wallCount = MeasurementManager.shared.wallPlanes.count
        wallBadge?.label.text  = String(format: "%d p.", max(wallCount, s.wall > 0.1 ? 1 : 0))
        ceilBadge?.label.text  = String(format: "%.1fm²", s.ceiling)
        doorBadge?.label.text  = "\(doors)"
        winBadge?.label.text   = "\(windows)"
    }

    func updatePlanPreview(_ image: UIImage?) {
        guard let img = image else { return }
        UIView.transition(with: planImageView, duration: 0.3,
                          options: .transitionCrossDissolve,
                          animations: { self.planImageView.image = img })
    }

    func setPauseState(_ paused: Bool) {
        let name = paused ? "play.circle" : "pause.circle"
        let cfg  = UIImage.SymbolConfiguration(pointSize: 30, weight: .thin)
        pauseButton?.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
    }

    func setTorchState(_ on: Bool) {
        isTorchOn = on
        let name = on ? "flashlight.on.fill" : "flashlight.off.fill"
        let cfg  = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        torchButton?.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
        torchButton?.tintColor = on
            ? UIColor(red: 0.94, green: 0.65, blue: 0.0, alpha: 1)
            : .white
    }
}
