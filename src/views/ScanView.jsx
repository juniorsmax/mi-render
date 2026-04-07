import { useState, useRef, useEffect, useCallback } from 'react'
import { useCamera } from '../hooks/useCamera'
import { shoelace } from '../lib/shoelace'
import './ScanView.css'

/**
 * ScanView — camera-based room scanner (no WebXR needed)
 *
 * Steps:
 *  'permission'  → ask for camera access
 *  'corners'     → live camera + tap floor corners (3+ points)
 *  'scale'       → tap 2 reference points + enter real distance → compute m²
 *  'manual'      → fallback: width × length input
 */
export function ScanView({ onComplete, onCancel, initialStep = 'permission' }) {
  const [step, setStep] = useState(initialStep)
  const [corners, setCorners] = useState([])        // pixel coords [{x,y}]
  const [refPoints, setRefPoints] = useState([])    // 2 reference pixel points
  const [refDist, setRefDist] = useState('')        // real distance in meters
  const { videoRef, cameraState, errorMsg, start, stop } = useCamera()
  const canvasRef = useRef(null)
  const overlayRef = useRef(null)
  const frozenImageRef = useRef(null) // ImageData of frozen frame for scale step

  // ── Draw loop: corners + polygon on live camera ───────────────────
  useEffect(() => {
    if (step !== 'corners') return
    let rafId
    function draw() {
      const canvas = canvasRef.current
      const video = videoRef.current
      if (!canvas || !video) { rafId = requestAnimationFrame(draw); return }
      canvas.width = canvas.offsetWidth
      canvas.height = canvas.offsetHeight
      const ctx = canvas.getContext('2d')
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      drawPolygon(ctx, corners, canvas.width, canvas.height)
      rafId = requestAnimationFrame(draw)
    }
    rafId = requestAnimationFrame(draw)
    return () => cancelAnimationFrame(rafId)
  }, [step, corners, videoRef])

  // ── Draw frozen frame + corners + ref points for scale step ──────
  useEffect(() => {
    if (step !== 'scale') return
    const canvas = canvasRef.current
    if (!canvas) return
    canvas.width = canvas.offsetWidth
    canvas.height = canvas.offsetHeight
    const ctx = canvas.getContext('2d')

    // Restore frozen frame
    if (frozenImageRef.current) {
      ctx.putImageData(frozenImageRef.current, 0, 0)
    }
    // Draw corners
    drawPolygon(ctx, corners, canvas.width, canvas.height)
    // Draw ref points
    drawRefPoints(ctx, refPoints)
  }, [step, refPoints, corners])

  // ── Freeze frame when moving to scale step ────────────────────────
  function freezeAndNextStep() {
    const canvas = canvasRef.current
    const video = videoRef.current
    if (!canvas || !video) return

    canvas.width = canvas.offsetWidth
    canvas.height = canvas.offsetHeight
    const ctx = canvas.getContext('2d')

    // Draw video frame into canvas
    const vw = video.videoWidth, vh = video.videoHeight
    const cw = canvas.width, ch = canvas.height
    // Cover-fit
    const scale = Math.max(cw / vw, ch / vh)
    const dw = vw * scale, dh = vh * scale
    const dx = (cw - dw) / 2, dy = (ch - dh) / 2
    ctx.drawImage(video, dx, dy, dw, dh)

    frozenImageRef.current = ctx.getImageData(0, 0, cw, ch)
    stop() // stop camera stream
    setStep('scale')
  }

  // ── Tap handler for corners step ──────────────────────────────────
  const handleCornerTap = useCallback((e) => {
    if (step !== 'corners') return
    const rect = canvasRef.current.getBoundingClientRect()
    const touch = e.touches?.[0] ?? e
    const x = touch.clientX - rect.left
    const y = touch.clientY - rect.top
    setCorners((prev) => [...prev, { x, y }])
  }, [step])

  // ── Tap handler for scale step (ref points) ───────────────────────
  const handleRefTap = useCallback((e) => {
    if (step !== 'scale' || refPoints.length >= 2) return
    const rect = canvasRef.current.getBoundingClientRect()
    const touch = e.touches?.[0] ?? e
    const x = touch.clientX - rect.left
    const y = touch.clientY - rect.top
    setRefPoints((prev) => [...prev, { x, y }])
  }, [step, refPoints.length])

  // ── Calculate and finish ──────────────────────────────────────────
  function handleCalculate() {
    const d = parseFloat(refDist)
    if (isNaN(d) || d <= 0 || refPoints.length < 2) return

    const px = refPoints[1].x - refPoints[0].x
    const py = refPoints[1].y - refPoints[0].y
    const pixelDist = Math.sqrt(px * px + py * py)
    if (pixelDist < 5) return // points too close

    const scale = d / pixelDist           // meters per pixel
    const pixelArea = shoelace(corners.map((p) => ({ x: p.x, z: p.y })))
    const areaSqM = parseFloat((pixelArea * scale * scale).toFixed(2))

    onComplete({ areaSqM, points: corners })
  }

  // ── STEP: permission ──────────────────────────────────────────────
  if (step === 'permission') {
    return (
      <div className="scan-start-root">
        <div className="scan-start-content safe-top safe-bottom">
          <div className="scan-icon">📷</div>
          <h2>Escaneo de habitación</h2>
          <p className="text-muted" style={{ textAlign: 'center' }}>
            Abre la cámara, apunta al suelo y toca las esquinas de la estancia.
            Sin WebXR — funciona en cualquier iPhone.
          </p>

          <div className="scan-steps glass">
            <ScanStep n={1} text="Apunta la cámara al suelo de la habitación" />
            <ScanStep n={2} text="Toca las 4 esquinas del suelo en orden" />
            <ScanStep n={3} text="Marca una distancia de referencia conocida" />
          </div>

          {cameraState === 'error' && (
            <div className="scan-diag glass scan-diag-warn">⚠️ {errorMsg}</div>
          )}

          <div className="scan-actions">
            <button
              className="btn btn-primary btn-lg"
              onClick={async () => {
                await start()
                setStep('corners')
              }}
              disabled={cameraState === 'requesting'}
            >
              {cameraState === 'requesting' ? 'Abriendo cámara…' : 'Abrir cámara'}
            </button>
            <button className="btn btn-ghost" onClick={() => setStep('manual')}>
              Introducir m² manualmente
            </button>
            <button className="btn btn-ghost btn-sm" onClick={onCancel}>Volver</button>
          </div>
        </div>
      </div>
    )
  }

  // ── STEP: corners (live camera) ───────────────────────────────────
  if (step === 'corners') {
    return (
      <div className="scan-camera-root">
        {/* Live camera */}
        <video
          ref={videoRef}
          className="scan-video"
          playsInline
          muted
          autoPlay
        />

        {/* Tap canvas */}
        <canvas
          ref={canvasRef}
          className="scan-canvas"
          onPointerDown={handleCornerTap}
          onTouchStart={(e) => { e.preventDefault(); handleCornerTap(e) }}
        />

        {/* HUD top */}
        <div className="scan-hud-top safe-top">
          <div className="scan-tap-badge">
            {corners.length === 0
              ? 'Toca las esquinas del suelo en orden'
              : `${corners.length} esquina${corners.length !== 1 ? 's' : ''} marcada${corners.length !== 1 ? 's' : ''}`
            }
          </div>
        </div>

        {/* HUD bottom */}
        <div className="scan-hud-bottom safe-bottom">
          <button
            className="btn btn-ghost"
            onClick={() => setCorners((p) => p.slice(0, -1))}
            disabled={corners.length === 0}
          >
            ↩ Deshacer
          </button>
          <button
            className="btn btn-primary"
            onClick={freezeAndNextStep}
            disabled={corners.length < 3}
          >
            Listo ({corners.length})
          </button>
        </div>
      </div>
    )
  }

  // ── STEP: scale reference ─────────────────────────────────────────
  if (step === 'scale') {
    const canProceed = refPoints.length === 2 && parseFloat(refDist) > 0
    return (
      <div className="scan-camera-root">
        {/* Frozen frame canvas */}
        <canvas ref={canvasRef} className="scan-canvas scan-canvas-static"
          onPointerDown={handleRefTap}
          onTouchStart={(e) => { e.preventDefault(); handleRefTap(e) }}
          style={{ touchAction: 'none' }}
        />

        {/* HUD top */}
        <div className="scan-hud-top safe-top">
          <div className="scan-tap-badge">
            {refPoints.length === 0 && 'Toca el inicio de una pared conocida'}
            {refPoints.length === 1 && 'Toca el final de esa pared'}
            {refPoints.length === 2 && '✓ Referencia marcada'}
          </div>
        </div>

        {/* Scale form */}
        <div className="scan-scale-form glass safe-bottom">
          <p style={{ fontSize: 13, marginBottom: 8 }}>
            ¿Cuánto mide esa distancia en metros?
          </p>
          <div className="scale-input-row">
            <input
              type="number"
              placeholder="Ej. 3.50"
              min="0.1"
              step="0.01"
              value={refDist}
              onChange={(e) => setRefDist(e.target.value)}
              inputMode="decimal"
            />
            <span style={{ color: 'var(--color-text-muted)', fontWeight: 600 }}>m</span>
          </div>
          <div className="scale-actions">
            <button className="btn btn-ghost btn-sm" onClick={() => {
              setRefPoints([])
              setStep('corners')
              setCorners([])
              start().then(() => {})
            }}>
              ↩ Re-escanear
            </button>
            <button
              className="btn btn-primary"
              onClick={handleCalculate}
              disabled={!canProceed}
            >
              Calcular m²
            </button>
          </div>
        </div>
      </div>
    )
  }

  // ── STEP: manual ──────────────────────────────────────────────────
  if (step === 'manual') {
    return <ManualForm onComplete={onComplete} onBack={() => setStep('permission')} />
  }

  return null
}

// ── Manual form ────────────────────────────────────────────────────────────────
function ManualForm({ onComplete, onBack }) {
  const [width, setWidth] = useState('')
  const [length, setLength] = useState('')
  const [roomName, setRoomName] = useState('')

  const w = parseFloat(width), l = parseFloat(length)
  const computed = !isNaN(w) && !isNaN(l) && w > 0 && l > 0 ? (w * l).toFixed(2) : null

  function handleSubmit(e) {
    e.preventDefault()
    if (!computed) return
    onComplete({
      areaSqM: parseFloat(computed),
      roomName,
      dimensions: `${w} m × ${l} m`,
    })
  }

  return (
    <div className="scan-start-root scroll-view">
      <div className="scan-start-content safe-top safe-bottom">
        <div className="scan-icon">📐</div>
        <h2>Medición manual</h2>
        <p className="text-muted">Introduce las dimensiones de la estancia.</p>

        <form className="manual-form glass" onSubmit={handleSubmit}>
          <div className="form-field">
            <label>Nombre de la estancia</label>
            <input type="text" placeholder="Ej. Salón" value={roomName} onChange={(e) => setRoomName(e.target.value)} />
          </div>
          <div className="form-row">
            <div className="form-field">
              <label>Ancho (m)</label>
              <input type="number" placeholder="4.20" min="0.1" step="0.01" value={width} onChange={(e) => setWidth(e.target.value)} required inputMode="decimal" />
            </div>
            <div className="form-field">
              <label>Largo (m)</label>
              <input type="number" placeholder="3.80" min="0.1" step="0.01" value={length} onChange={(e) => setLength(e.target.value)} required inputMode="decimal" />
            </div>
          </div>
          {computed && (
            <div className="manual-result">
              <span className="text-muted">Superficie calculada</span>
              <span className="manual-area text-mono text-accent">{computed} m²</span>
            </div>
          )}
          <div className="form-actions">
            <button type="button" className="btn btn-ghost" onClick={onBack}>← Volver</button>
            <button type="submit" className="btn btn-primary" disabled={!computed}>Continuar →</button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ── Canvas drawing helpers ─────────────────────────────────────────────────────
function drawPolygon(ctx, points, w, h) {
  if (points.length === 0) return

  // Polygon fill
  if (points.length >= 3) {
    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y))
    ctx.closePath()
    ctx.fillStyle = 'rgba(108, 143, 255, 0.18)'
    ctx.fill()
  }

  // Lines
  if (points.length >= 2) {
    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y))
    if (points.length >= 3) ctx.closePath()
    ctx.strokeStyle = 'rgba(108, 143, 255, 0.8)'
    ctx.lineWidth = 2
    ctx.setLineDash([6, 4])
    ctx.stroke()
    ctx.setLineDash([])
  }

  // Dots
  points.forEach((p, i) => {
    ctx.beginPath()
    ctx.arc(p.x, p.y, 10, 0, Math.PI * 2)
    ctx.fillStyle = i === 0 ? 'rgba(52, 211, 153, 0.9)' : 'rgba(108, 143, 255, 0.9)'
    ctx.fill()
    ctx.strokeStyle = '#fff'
    ctx.lineWidth = 2
    ctx.stroke()

    // Number label
    ctx.fillStyle = '#fff'
    ctx.font = 'bold 11px -apple-system, sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(i + 1, p.x, p.y)
  })
}

function drawRefPoints(ctx, points) {
  points.forEach((p, i) => {
    ctx.beginPath()
    ctx.arc(p.x, p.y, 8, 0, Math.PI * 2)
    ctx.fillStyle = 'rgba(251, 191, 36, 0.9)'
    ctx.fill()
    ctx.strokeStyle = '#fff'
    ctx.lineWidth = 2
    ctx.stroke()
  })
  if (points.length === 2) {
    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    ctx.lineTo(points[1].x, points[1].y)
    ctx.strokeStyle = 'rgba(251, 191, 36, 0.9)'
    ctx.lineWidth = 2
    ctx.setLineDash([5, 3])
    ctx.stroke()
    ctx.setLineDash([])
  }
}

function ScanStep({ n, text }) {
  return (
    <div className="home-step">
      <div className="home-step-n">{n}</div>
      <p style={{ fontSize: 13 }}>{text}</p>
    </div>
  )
}
