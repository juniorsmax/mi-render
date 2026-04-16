// SpatialCanvasView.swift
// Contenedor principal de la interfaz espacial de SceneViewer.
//
// Responsabilidades:
//   • Host de SceneViewerViewController (addChild)
//   • RadialModeSelector flotante (esquina inferior derecha)
//   • SideInspectorPanel (deslizable desde la derecha)
//   • ObjectContextMenu (contextual al tocar una entidad)
//   • SceneTimelineBar (barra inferior expandible)
//
// Uso:
//   let canvas = SpatialCanvasViewController()
//   navigationController?.pushViewController(canvas, animated: true)

import UIKit
import RealityKit

// MARK: - SpatialCanvasViewController

class SpatialCanvasViewController: UIViewController {

    // MARK: - Subcontrolador

    private let sceneViewer = SceneViewerViewController()

    // MARK: - Overlays

    private var radialSelector: RadialModeSelector!
    private var inspectorPanel: SideInspectorPanel!
    private var timelineBar:    SceneTimelineBar!

    // Estado de UI persistido
    private static let defaultsKeyRadialPos = "mi_render_radial_x_pct"

    // MARK: - Ciclo de vida

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        embedSceneViewer()
        setupRadialSelector()
        setupInspectorPanel()
        setupTimelineBar()
        observeLayerChanges()
        observeTimelineSeek()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Embed SceneViewer

    private func embedSceneViewer() {
        addChild(sceneViewer)
        sceneViewer.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneViewer.view)
        NSLayoutConstraint.activate([
            sceneViewer.view.topAnchor.constraint(equalTo: view.topAnchor),
            sceneViewer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneViewer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneViewer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        sceneViewer.didMove(toParent: self)
    }

    // MARK: - RadialModeSelector

    private func setupRadialSelector() {
        radialSelector = RadialModeSelector()
        radialSelector.delegate = self
        radialSelector.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(radialSelector)

        // Posición: esquina inferior derecha, sobre la timeline bar
        NSLayoutConstraint.activate([
            radialSelector.widthAnchor.constraint(equalToConstant: 60),
            radialSelector.heightAnchor.constraint(equalToConstant: 60),
            radialSelector.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            radialSelector.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                    constant: -76),
        ])

        // Arrastrar para reposicionar
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragRadialSelector(_:)))
        radialSelector.addGestureRecognizer(pan)
    }

    @objc private func dragRadialSelector(_ gesture: UIPanGestureRecognizer) {
        guard let superview = radialSelector.superview else { return }
        let translation = gesture.translation(in: superview)
        if gesture.state == .changed {
            let newCenter = CGPoint(
                x: max(36, min(superview.bounds.width - 36,  radialSelector.center.x + translation.x)),
                y: max(36, min(superview.bounds.height - 36, radialSelector.center.y + translation.y))
            )
            radialSelector.center = newCenter
            gesture.setTranslation(.zero, in: superview)
        }
        if gesture.state == .ended {
            let pct = radialSelector.center.x / superview.bounds.width
            UserDefaults.standard.set(Float(pct), forKey: Self.defaultsKeyRadialPos)
        }
    }

    // MARK: - SideInspectorPanel

    private func setupInspectorPanel() {
        inspectorPanel = SideInspectorPanel()
        view.addSubview(inspectorPanel)

        NSLayoutConstraint.activate([
            inspectorPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            inspectorPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inspectorPanel.widthAnchor.constraint(equalToConstant: 240),
            inspectorPanel.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                   constant: -80),
        ])
        inspectorPanel.alpha = 0
        inspectorPanel.transform = CGAffineTransform(translationX: 240, y: 0)
    }

    /// Muestra el inspector con datos derivados del modo de capa activo.
    func showInspectorForCurrentMode() {
        let mode = SceneLayerManager.shared.currentMode
        var data = InspectorData()
        data.objectName       = mode.displayName
        data.semanticCategory = mode.rawValue

        // Si hay un plan guardado, poblar dimensiones
        if let plan = FloorPlan2DGenerator.shared.loadSaved(), !plan.segments.isEmpty {
            let w = plan.maxBounds.x - plan.minBounds.x
            let h = plan.maxBounds.y - plan.minBounds.y
            data.roomDimensions = String(format: "%.1f × %.1f m", w, h)
            let avg = plan.segments.map { $0.length }.reduce(0, +) / Float(plan.segments.count)
            data.wallLength = String(format: "%.2f m (avg)", avg)
            data.surfaceType = "Pared LiDAR"
        }

        inspectorPanel.show(with: data)
    }

    // MARK: - SceneTimelineBar

    private func setupTimelineBar() {
        timelineBar = SceneTimelineBar()
        view.addSubview(timelineBar)

        NSLayoutConstraint.activate([
            timelineBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            timelineBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            timelineBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Datos demo: usar timestamp actual como referencia
        let now = Date()
        let start = now.addingTimeInterval(-300) // 5 min atrás
        let versions: [SceneTimelineVersion] = [
            SceneTimelineVersion(id: "v1", timestamp: start,                    label: "v1"),
            SceneTimelineVersion(id: "v2", timestamp: start.addingTimeInterval(120), label: "v2"),
            SceneTimelineVersion(id: "v3", timestamp: now,                       label: "v3"),
        ]
        timelineBar.configure(scanStart: start, scanEnd: now, versions: versions)
    }

    // MARK: - Observar cambios de capa

    private func observeLayerChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onLayerChanged(_:)),
            name: .sceneLayerDidChange,
            object: nil
        )
    }

    @objc private func onLayerChanged(_ note: Notification) {
        guard let mode = note.object as? SceneLayerMode else { return }
        radialSelector.highlightMode(mode)
        showInspectorForCurrentMode()
    }

    // MARK: - Observar seek del timeline

    private func observeTimelineSeek() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onTimelineSeek(_:)),
            name: .sceneTimelineSeek,
            object: nil
        )
    }

    @objc private func onTimelineSeek(_ note: Notification) {
        guard let progress = (note.object as? NSNumber)?.floatValue else { return }
        // Delegar al SceneViewer si está en modo walkthrough
        if SceneLayerManager.shared.currentMode == .walkthrough {
            // SceneViewer maneja NavigationPlaybackController internamente
            NotificationCenter.default.post(
                name: .sceneTimelineSeek,
                object: NSNumber(value: progress)
            )
        }
    }

    // MARK: - Mostrar ObjectContextMenu

    func showContextMenu(at point: CGPoint) {
        let menu = ObjectContextMenu()
        menu.delegate = self
        menu.show(at: point, in: view)
    }
}

// MARK: - RadialModeSelectorDelegate

extension SpatialCanvasViewController: RadialModeSelectorDelegate {

    func radialSelector(_ selector: RadialModeSelector, didSelect mode: RadialMode) {
        switch mode {
        case .scan:
            // Volver al scanning (pop o dismiss)
            navigationController?.popViewController(animated: true)

        case .explore:
            SceneLayerManager.shared.switchMode(to: .meshRaw)

        case .edit:
            inspectorPanel.isVisible
                ? inspectorPanel.hide()
                : showInspectorForCurrentMode()

        case .plan:
            SceneLayerManager.shared.switchMode(to: .floorplan3D)

        case .walk:
            SceneLayerManager.shared.switchMode(to: .walkthrough)

        case .nodes:
            SceneLayerManager.shared.switchMode(to: .panoramaNodes)

        case .ai:
            showAIHint()

        case .export:
            showExportSheet()
        }
    }
}

// MARK: - ObjectContextMenuDelegate

extension SpatialCanvasViewController: ObjectContextMenuDelegate {

    func contextMenu(_ menu: ObjectContextMenu, didSelect action: ObjectContextAction) {
        switch action {
        case .move:
            // Activar gizmo de translación (extensión futura)
            break
        case .replaceMaterial:
            showMaterialPicker()
        case .measure:
            SceneLayerManager.shared.switchMode(to: .floorplan2D)
        case .export:
            showExportSheet()
        case .delete:
            confirmDelete()
        }
    }

    func contextMenuDidDismiss(_ menu: ObjectContextMenu) {}
}

// MARK: - Acciones de menú

private extension SpatialCanvasViewController {

    func showAIHint() {
        let alert = UIAlertController(
            title: "AI Analysis",
            message: "Clasificación semántica activa vía SemanticMeshClassifier.\nUsa la capa 'Semantic' para ver los resultados.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            SceneLayerManager.shared.switchMode(to: .meshSemantic)
            self?.radialSelector.highlightMode(.meshSemantic)
        })
        present(alert, animated: true)
    }

    func showExportSheet() {
        let sheet = UIAlertController(title: "Exportar", message: nil, preferredStyle: .actionSheet)
        let formats = ["SVG", "DXF", "IFC", "USDZ", "OBJ"]
        for fmt in formats {
            sheet.addAction(UIAlertAction(title: fmt, style: .default) { _ in
                // ExportManager puede usar FloorPlan2DGenerator / ObjectCaptureManager
                NotificationCenter.default.post(
                    name: Notification.Name("mi_render_exportRequested"),
                    object: fmt
                )
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(sheet, animated: true)
    }

    func showMaterialPicker() {
        let alert = UIAlertController(title: "Material", message: "Selecciona material para el objeto", preferredStyle: .actionSheet)
        let mats = ["Metal", "Madera", "Cemento", "Vidrio", "Yeso"]
        for mat in mats {
            alert.addAction(UIAlertAction(title: mat, style: .default))
        }
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }

    func confirmDelete() {
        let alert = UIAlertController(
            title: "Eliminar objeto",
            message: "¿Eliminar este elemento del escaneo?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Eliminar", style: .destructive))
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
        present(alert, animated: true)
    }
}
