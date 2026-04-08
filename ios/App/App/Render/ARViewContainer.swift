// ARViewContainer.swift
// Contenedor SwiftUI del ARView de RealityKit.
// Punto de entrada visual de la experiencia AR.

import SwiftUI
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {

    var onTap: ((CGPoint) -> Void)?

    func makeUIView(context: Context) -> ARView {

        let arView = ARView(frame: .zero)

        // Activar oclusión realista (objetos virtuales detrás de objetos reales)
        arView.environment.sceneUnderstanding.options.insert(.occlusion)

        // Activar física basada en el entorno real
        arView.environment.sceneUnderstanding.options.insert(.physics)

        // Gestor de tap
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // Arrancar escaneo completo
        ScanManager.shared.startFullScan(arView: arView)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    class Coordinator: NSObject {

        var onTap: ((CGPoint) -> Void)?

        init(onTap: ((CGPoint) -> Void)?) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            onTap?(point)
        }
    }
}
