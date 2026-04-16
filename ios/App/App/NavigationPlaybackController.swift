// NavigationPlaybackController.swift
// Recorrido virtual tipo Polycam entre los nodos de cámara registrados.
// Lee NavigationManager.cameraNodes, interpola posición/orientación suavemente
// y controla la cámara orbital de SceneViewer en tiempo real.
//
// Uso desde SceneViewer:
//   playback = NavigationPlaybackController(nodes: NavigationManager.shared.cameraNodes)
//   playback.delegate = self
//   playback.play()

import UIKit
import simd

// MARK: - Delegado de reproducción

protocol NavigationPlaybackDelegate: AnyObject {
    /// Llamado en cada frame de animación con la posición e "interés" de la cámara.
    func playback(_ controller: NavigationPlaybackController,
                  didMoveTo position: SIMD3<Float>,
                  lookingAt target: SIMD3<Float>)
    /// Llamado al terminar el recorrido completo.
    func playbackDidFinish(_ controller: NavigationPlaybackController)
}

// MARK: - NavigationPlaybackController

class NavigationPlaybackController {

    // MARK: Configuración pública

    /// Velocidad de reproducción (metros/segundo, default 1.0 m/s).
    var speed: Float = 1.0

    /// Duración mínima entre nodos en segundos (evita saltos en nodos muy juntos).
    var minSegmentDuration: TimeInterval = 0.4

    /// Activar/desactivar loop automático al terminar.
    var loops: Bool = false

    weak var delegate: NavigationPlaybackDelegate?

    // MARK: Estado

    enum State { case idle, playing, paused, finished }
    private(set) var state: State = .idle

    /// Progreso 0.0–1.0 del recorrido completo.
    var progress: Float {
        guard totalLength > 0 else { return 0 }
        return min(1, traveledDistance / totalLength)
    }

    // MARK: Privado

    private var nodes: [NavigationManager.CameraNode] = []
    private var displayLink: CADisplayLink?
    private var currentSegment: Int = 0
    private var segmentT: Float = 0          // 0.0–1.0 dentro del segmento actual
    private var traveledDistance: Float = 0
    private var totalLength: Float = 0
    private var segmentLengths: [Float] = []

    // MARK: - Init

    init(nodes: [NavigationManager.CameraNode]) {
        self.nodes = nodes
        computeLengths()
    }

    convenience init() {
        self.init(nodes: NavigationManager.shared.cameraNodes)
    }

    // MARK: - Control de reproducción

    func play() {
        guard nodes.count >= 2 else { return }
        if state == .idle || state == .finished {
            currentSegment   = 0
            segmentT         = 0
            traveledDistance = 0
        }
        state = .playing
        startDisplayLink()
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        stopDisplayLink()
    }

    func resume() {
        guard state == .paused else { return }
        state = .playing
        startDisplayLink()
    }

    func stop() {
        state = .idle
        stopDisplayLink()
        currentSegment   = 0
        segmentT         = 0
        traveledDistance = 0
    }

    /// Salta directamente a un nodo concreto (índice en la trayectoria).
    func seek(to nodeIndex: Int) {
        guard nodeIndex < nodes.count else { return }
        currentSegment   = min(nodeIndex, nodes.count - 2)
        segmentT         = 0
        traveledDistance = segmentLengths.prefix(currentSegment).reduce(0, +)
        emitCurrentPose()
    }

    /// Salta a un progreso normalizado (0.0–1.0) del recorrido.
    func seek(toProgress p: Float) {
        let target = max(0, min(1, p)) * totalLength
        var acc: Float = 0
        for i in 0..<segmentLengths.count {
            let next = acc + segmentLengths[i]
            if target <= next || i == segmentLengths.count - 1 {
                currentSegment   = i
                segmentT         = segmentLengths[i] > 0 ? (target - acc) / segmentLengths[i] : 0
                traveledDistance = target
                emitCurrentPose()
                return
            }
            acc = next
        }
    }

    // MARK: - DisplayLink

    private func startDisplayLink() {
        stopDisplayLink()
        let dl = CADisplayLink(target: self, selector: #selector(tick(_:)))
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ dl: CADisplayLink) {
        guard state == .playing, nodes.count >= 2 else { return }

        let seg = segmentLengths[currentSegment]
        let dt  = Float(dl.duration)

        // Avance en t proporcional a velocidad y longitud del segmento
        let dtT = seg > 0 ? (speed * dt) / seg : 1.0
        segmentT += dtT
        traveledDistance += speed * dt

        if segmentT >= 1.0 {
            // Pasar al siguiente segmento
            currentSegment += 1
            segmentT = 0

            if currentSegment >= nodes.count - 1 {
                // Fin del recorrido
                emitPose(at: nodes.count - 1, t: 0)
                if loops {
                    currentSegment   = 0
                    traveledDistance = 0
                } else {
                    state = .finished
                    stopDisplayLink()
                    delegate?.playbackDidFinish(self)
                    return
                }
            }
        }

        emitCurrentPose()
    }

    // MARK: - Interpolación

    private func emitCurrentPose() {
        guard currentSegment < nodes.count - 1 else {
            emitPose(at: nodes.count - 1, t: 0)
            return
        }
        emitPose(at: currentSegment, t: segmentT)
    }

    private func emitPose(at segment: Int, t: Float) {
        guard segment < nodes.count - 1 else {
            let n = nodes[nodes.count - 1]
            delegate?.playback(self,
                               didMoveTo: n.position,
                               lookingAt: n.position + n.forward)
            return
        }

        let a = nodes[segment]
        let b = nodes[segment + 1]
        let smooth = smoothstep(t)

        // Interpolación Catmull-Rom para posición más suave
        let position = catmullRomPosition(segment: segment, t: smooth)

        // Interpolación esférica para la dirección de mirada
        let qa = quaternion(from: a.forward)
        let qb = quaternion(from: b.forward)
        let qInterp = simd_slerp(qa, qb, smooth)
        let forward  = qInterp.act(SIMD3<Float>(0, 0, -1))
        let target   = position + forward

        delegate?.playback(self, didMoveTo: position, lookingAt: target)
    }

    // MARK: - Utilidades matemáticas

    private func smoothstep(_ t: Float) -> Float {
        let x = max(0, min(1, t))
        return x * x * (3 - 2 * x)
    }

    /// Catmull-Rom usando hasta 4 nodos de control alrededor del segmento.
    private func catmullRomPosition(segment: Int, t: Float) -> SIMD3<Float> {
        let p1 = nodes[segment].position
        let p2 = nodes[segment + 1].position
        let p0 = segment > 0 ? nodes[segment - 1].position : p1 - (p2 - p1)
        let p3 = segment + 2 < nodes.count ? nodes[segment + 2].position : p2 + (p2 - p1)

        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (-p0 + 3*p1 - 3*p2 + p3) * t3 +
            (2*p0 - 5*p1 + 4*p2 - p3) * t2 +
            (-p0 + p2) * t +
            2*p1
        )
    }

    /// Construye un cuaternión que orienta -Z hacia `forward`.
    private func quaternion(from forward: SIMD3<Float>) -> simd_quatf {
        let f = simd_normalize(forward)
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(up, f))
        let realUp = simd_cross(f, right)
        let m = simd_float3x3(columns: (right, realUp, -f))
        return simd_quatf(m)
    }

    // MARK: - Precálculo de longitudes

    private func computeLengths() {
        segmentLengths = []
        totalLength    = 0
        guard nodes.count >= 2 else { return }
        for i in 0..<nodes.count - 1 {
            let d = simd_distance(nodes[i].position, nodes[i+1].position)
            segmentLengths.append(max(d, 0.001))
            totalLength += d
        }
    }

    /// Recarga los nodos desde NavigationManager y recalcula longitudes.
    func reloadNodes() {
        nodes = NavigationManager.shared.cameraNodes
        computeLengths()
        stop()
    }

    /// Devuelve las posiciones de todos los nodos para dibujar la trayectoria.
    func trajectoryPositions() -> [SIMD3<Float>] {
        nodes.map { $0.position }
    }

    /// Info de estado para Capacitor bridge.
    func statusDictionary() -> [String: Any] {
        [
            "state":         "\(state)",
            "nodeCount":     nodes.count,
            "progress":      Double(progress),
            "totalLength":   Double(totalLength),
            "currentSegment": currentSegment,
            "speed":         Double(speed),
        ]
    }
}
