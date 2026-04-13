import { useState, useRef, useEffect, useCallback } from 'react'
import { useCamera } from '../hooks/useCamera'
import { shoelace } from '../lib/shoelace'
import { sanitizeNumber, sanitizeName } from '../lib/security'
import { getScanMode, SCAN_MODE_LABELS, startLiDARScan, startObjectScan, startPhotogrammetry } from '../lib/lidar'
import { Icon } from '../components/Icon.jsx'
import { ScanExport } from '../components/ScanExport.jsx'
import './ScanView.css'

/**
 * ScanView — escáner estilo Polycam
 * Agentes: Luna (UI) + Ares (Escáner) + Vera (Diseño) + Kai (LiDAR nativo)
 *
 * Pasos:
 *  'permission' → pantalla de inicio con consejos
 *  'scanning'   → LiDAR nativo en progreso (RoomPlan toma el control)
 *  'corners'    → cámara fullscreen + toque de esquinas (fallback cámara)
 *  'scale'      → panel inferior para introducir distancia de referencia
 *  'manual'     → formulario ancho × largo
 *  'result'     → resultados del escaneo LiDAR
 */
export function ScanView({ onComplete, onCancel, initialStep = 'permission' }) {
  const [step, setStep]           = useState(initialStep)
  const [corners, setCorners]     = useState([])
  const [refPoints, setRefPoints] = useState([])
  const [refDist, setRefDist]     = useState('')
  const [scanMode, setScanMode]   = useState(null)
  const [showTips, setShowTips]   = useState(false)
  const [activeTab, setActiveTab] = useState('espacio')
  const [lidarError, setLidarError] = useState(null)
  const [scanResult, setScanResult] = useState(null)

  const { videoRef, cameraState, errorMsg, start, stop } = useCamera()
  const canvasRef      = useRef(null)
  const frozenImageRef = useRef(null)

  useEffect(() => { getScanMode().then(setScanMode) }, [])

  // ── LiDAR nativo: inicia escaneo de habitación ────────────────────────────
  async function handleStartLiDAR() {
    setLidarError(null)
    setStep('scanning')
    try {
      const result = await startLiDARScan()
      setScanResult(result)
      setStep('result')
    } catch (err) {
      setLidarError(err.message ?? 'Error en el escaneo LiDAR')
      setStep('permission')
    }
  }

  // ── LiDAR nativo: inicia escaneo de objeto 3D ─────────────────────────────
  async function handleStartObjectScan() {
    setLidarError(null)
    setStep('scanning')
    try {
      const result = await startObjectScan()
      setScanResult(result)
      setStep('result')
    } catch (err) {
      setLidarError(err.message ?? 'Error en el escaneo de objeto')
      setStep('permission')
    }
  }

  // ── Fotogrametría on-device (iOS 17+) ─────────────────────────────────────
  async function handleStartPhotogrammetry() {
    setLidarError(null)
    setStep('scanning')
    try {
      const result = await startPhotogrammetry()
      setScanResult(result)
      setStep('result')
    } catch (err) {
      setLidarError(err.message ?? 'Error en la fotogrametría')
      setStep('permission')
    }
  }

  // ── Iniciar escaneo según modo y tab ──────────────────────────────────────
  async function handleStartScan() {
    if (activeTab === 'fotograma') {
      await handleStartPhotogrammetry()
      return
    }
    if (scanMode === 'lidar-native') {
      if (activeTab === 'objeto') {
        await handleStartObjectScan()
      } else {
        await handleStartLiDAR()
      }
    } else {
      await start()
      setStep('corners')
    }
  }

  // ── Draw loop (fallback cámara) ───────────────────────────────────────────
  useEffect(() => {
    if (step !== 'corners') return
    let rafId
    function draw() {
      const canvas = canvasRef.current
      const video  = videoRef.current
      if (!canvas || !video) { rafId = requestAnimationFrame(draw); return }
      canvas.width  = canvas.offsetWidth
      canvas.height = canvas.offsetHeight
      const ctx = canvas.getContext('2d')
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      drawPolygon(ctx, corners)
      rafId = requestAnimationFrame(draw)
    }
    rafId = requestAnimationFrame(draw)
    return () => cancelAnimationFrame(rafId)
  }, [step, corners, videoRef])

  useEffect(() => {
    if (step !== 'scale') return
    const canvas = canvasRef.current
    if (!canvas) return
    canvas.width  = canvas.offsetWidth
    canvas.height = canvas.offsetHeight
    const ctx = canvas.getContext('2d')
    if (frozenImageRef.current) ctx.putImageData(frozenImageRef.current, 0, 0)
    drawPolygon(ctx, corners)
    drawRefPoints(ctx, refPoints)
  }, [step, refPoints, corners])

  function freezeAndNextStep() {
    const canvas = canvasRef.current
    const video  = videoRef.current
    if (!canvas || !video) return
    canvas.width = canvas.offsetWidth
    canvas.height = canvas.offsetHeight
    const ctx = canvas.getContext('2d')
    const vw = video.videoWidth, vh = video.videoHeight
    const cw = canvas.width,     ch = canvas.height
    const s  = Math.max(cw / vw, ch / vh)
    ctx.drawImage(video, (cw - vw*s)/2, (ch - vh*s)/2, vw*s, vh*s)
    frozenImageRef.current = ctx.getImageData(0, 0, cw, ch)
    stop()
    setStep('scale')
  }

  const handleCornerTap = useCallback((e) => {
    if (step !== 'corners') return
    const rect  = canvasRef.current.getBoundingClientRect()
    const touch = e.touches?.[0] ?? e
    setCorners((prev) => [...prev, {
      x: touch.clientX - rect.left,
      y: touch.clientY - rect.top,
    }])
  }, [step])

  const handleRefTap = useCallback((e) => {
    if (step !== 'scale' || refPoints.length >= 2) return
    const rect  = canvasRef.current.getBoundingClientRect()
    const touch = e.touches?.[0] ?? e
    setRefPoints((prev) => [...prev, {
      x: touch.clientX - rect.left,
      y: touch.clientY - rect.top,
    }])
  }, [step, refPoints.length])

  function handleCalculate() {
    const d = sanitizeNumber(refDist, { min: 0.01, max: 100 })
    if (d === null || refPoints.length < 2) return
    const px = refPoints[1].x - refPoints[0].x
    const py = refPoints[1].y - refPoints[0].y
    const pixelDist = Math.sqrt(px*px + py*py)
    if (pixelDist < 5) return
    const scale    = d / pixelDist
    const pixelArea = shoelace(corners.map((p) => ({ x: p.x, z: p.y })))
    const areaSqM  = parseFloat((pixelArea * scale * scale).toFixed(2))
    onComplete({ floorArea: areaSqM, areaSqM, points: corners, scanMode: 'camera' })
  }

  const modeInfo = scanMode ? SCAN_MODE_LABELS[scanMode] : null
  const isLiDAR  = scanMode === 'lidar-native'

  // ════════════════════════════════════════════════════
  // STEP: permission — pantalla de inicio
  // ════════════════════════════════════════════════════
  if (step === 'permission') {
    return (
      <div className="scan-start-root">
        <div className="scan-start-content safe-top safe-bottom">
          <div className="scan-icon">
            <Icon name={isLiDAR ? 'lidar' : 'camera'} size={38} />
          </div>

          <div>
            <h2>{activeTab === 'objeto' ? 'Escaneo de objeto 3D' : 'Escaneo de espacio'}</h2>
            {modeInfo && (
              <div style={{ marginTop: 8, display: 'flex', justifyContent: 'center' }}>
                <span className="scan-mode-badge"
                  style={{ color: modeInfo.color, borderColor: modeInfo.color+'66', background: modeInfo.color+'11' }}>
                  <Icon name={isLiDAR ? 'lidar' : 'camera'} size={13} />
                  {modeInfo.label} · {modeInfo.desc}
                </span>
              </div>
            )}
          </div>

          {/* Tabs modo */}
          <div className="scan-mode-tabs" style={{ padding: '4px 0' }}>
            {['espacio', 'objeto', 'fotograma', 'manual'].map((tab) => (
              <div key={tab}
                className={`scan-mode-tab ${activeTab === tab ? 'active' : ''}`}
                onClick={() => setActiveTab(tab)}>
                {tab === 'espacio' ? 'ESPACIO' : tab === 'objeto' ? 'OBJETO' : tab === 'fotograma' ? 'FOTO 3D' : 'MANUAL'}
              </div>
            ))}
          </div>

          {activeTab === 'espacio' && (
            <div className="scan-steps glass">
              {isLiDAR ? (
                <>
                  <ScanStep n={1} text="La cámara LiDAR escanea la habitación automáticamente en 3D" />
                  <ScanStep n={2} text="Mueve el iPhone lentamente por toda la estancia" />
                  <ScanStep n={3} text="Pulsa Listo en la pantalla de escaneo cuando hayas cubierto todo" />
                </>
              ) : (
                <>
                  <ScanStep n={1} text="Apunta al suelo y toca las esquinas de la estancia en orden" />
                  <ScanStep n={2} text="Pulsa el botón grande cuando hayas marcado todas las esquinas" />
                  <ScanStep n={3} text="Toca dos puntos de una pared conocida e introduce su longitud" />
                </>
              )}
            </div>
          )}

          {activeTab === 'objeto' && (
            <div className="scan-steps glass">
              <ScanStep n={1} text="Coloca el objeto en el centro de la habitación con espacio a su alrededor" />
              <ScanStep n={2} text="Mueve el iPhone lentamente alrededor del objeto a 50–80 cm de distancia" />
              <ScanStep n={3} text="Pulsa Capturar cuando hayas cubierto todos los ángulos" />
            </div>
          )}

          {activeTab === 'fotograma' && (
            <div className="scan-steps glass">
              <ScanStep n={1} text="Abre la cámara y fotografía cada pared, techo y suelo desde varios ángulos" />
              <ScanStep n={2} text="Necesitas al menos 20 fotos — cuantas más, mejor calidad" />
              <ScanStep n={3} text="Pulsa Procesar para generar el modelo 3D texturizado (iOS 17+)" />
            </div>
          )}

          {activeTab === 'manual' && (
            <div className="scan-steps glass">
              <ScanStep n={1} text="Introduce el ancho y el largo de la estancia en metros" />
              <ScanStep n={2} text="Puedes usar una cinta métrica o los datos del plano" />
              <ScanStep n={3} text="Pulsa Continuar para guardar la medición" />
            </div>
          )}

          {lidarError && (
            <div className="scan-diag scan-diag-warn">
              <span className="scan-diag-icon"><Icon name="warning" size={18} /></span>
              <span>{lidarError}</span>
            </div>
          )}

          {cameraState === 'error' && !isLiDAR && (
            <div className="scan-diag scan-diag-warn">
              <span className="scan-diag-icon"><Icon name="warning" size={18} /></span>
              <span>{errorMsg}</span>
            </div>
          )}

          <div className="scan-actions">
            {activeTab !== 'manual' ? (
              <button className="btn btn-primary btn-lg"
                onClick={handleStartScan}
                disabled={cameraState === 'requesting'}>
                {cameraState === 'requesting'
                  ? <><span className="spinner" style={{width:16,height:16}} /> Abriendo…</>
                  : activeTab === 'fotograma'
                    ? <>📷 Capturar foto 3D</>
                    : isLiDAR
                      ? <><Icon name="lidar" size={18} /> {activeTab === 'objeto' ? 'Escanear objeto' : 'Escanear habitación'}</>
                      : <><Icon name="camera" size={18} /> Iniciar escaneo</>}
              </button>
            ) : (
              <button className="btn btn-primary btn-lg" onClick={() => setStep('manual')}>
                <Icon name="manual" size={18} /> Introducir manualmente
              </button>
            )}
            <button className="btn btn-ghost btn-sm" onClick={onCancel}>
              <Icon name="back" size={16} /> Volver
            </button>
          </div>
        </div>
      </div>
    )
  }

  // ════════════════════════════════════════════════════
  // STEP: scanning — LiDAR nativo en progreso
  // ════════════════════════════════════════════════════
  if (step === 'scanning') {
    return (
      <div className="scan-scanning-root">
        <div className="scan-scanning-content safe-top safe-bottom">
          {/* Radar animado */}
          <div className="scan-radar-wrap">
            <div className="scan-radar-ring" />
            <div className="scan-radar-ring" />
            <div className="scan-radar-ring" />
            <div className="scan-radar-axes" />
            <div className="scan-radar-sweep" />
            <div className="scan-radar-dot" />
          </div>

          {/* Texto de estado */}
          <div>
            <p className="scan-status-text">Escaneando habitación…</p>
          </div>

          <p className="scan-status-sub">
            Mueve el iPhone lentamente por la estancia.<br />
            Pulsa <strong style={{ color: 'var(--accent)' }}>Listo</strong> en la pantalla de escaneo cuando termines.
          </p>

          {/* Barra de progreso */}
          <div className="scan-progress-bar" />
        </div>
      </div>
    )
  }

  // ════════════════════════════════════════════════════
  // STEP: result — resultados del escaneo LiDAR (plano + stats + export)
  // ════════════════════════════════════════════════════
  if (step === 'result' && scanResult) {
    return <ScanExport
      result={scanResult}
      onAccept={() => onComplete(scanResult)}
      onRescan={() => { setScanResult(null); setStep('permission') }}
    />
  }

  // ════════════════════════════════════════════════════
  // STEP: corners — cámara fullscreen estilo Polycam
  // ════════════════════════════════════════════════════
  if (step === 'corners') {
    return (
      <div className="scan-camera-root">
        <video ref={videoRef} className="scan-video" playsInline muted autoPlay />

        <canvas ref={canvasRef} className="scan-canvas"
          onPointerDown={handleCornerTap}
          onTouchStart={(e) => { e.preventDefault(); handleCornerTap(e) }} />

        <div className="scan-hud-top safe-top">
          <button className="scan-tips-btn" onClick={() => setShowTips(true)}>
            <Icon name="info" size={14} /> Consejos
          </button>
          <button className="scan-close-btn" onClick={onCancel}>
            <Icon name="close" size={16} />
          </button>
        </div>

        <div className="scan-instruction-badge">
          {corners.length === 0 && 'Toca las esquinas del suelo en orden'}
          {corners.length > 0 && corners.length < 3 && `${corners.length} esquina${corners.length>1?'s':''} — toca más`}
          {corners.length >= 3 && `${corners.length} esquinas marcadas — pulsa Listo`}
        </div>

        <div className="scan-hud-bottom">
          <div className="scan-mode-tabs">
            {['espacio','objeto','manual'].map((tab) => (
              <div key={tab} className={`scan-mode-tab ${activeTab===tab?'active':''}`}
                onClick={() => { setActiveTab(tab); if(tab==='manual'){stop();setStep('manual')} }}>
                {tab === 'espacio' ? 'ESPACIO' : tab === 'objeto' ? 'OBJETO' : 'MANUAL'}
              </div>
            ))}
          </div>

          <div className="scan-controls-row">
            <button className="scan-undo-btn" onClick={() => setCorners((p)=>p.slice(0,-1))} disabled={corners.length===0}>
              <Icon name="undo" size={20} />
              <span>Deshacer</span>
            </button>

            <button className={`scan-capture-btn ${corners.length>=3?'has-points':''}`}
              onClick={corners.length>=3 ? freezeAndNextStep : undefined}>
              <div className="scan-capture-inner" />
            </button>

            <button className={`scan-done-btn ${corners.length>=3?'ready':''}`}
              onClick={corners.length>=3 ? freezeAndNextStep : undefined}
              disabled={corners.length<3}>
              <Icon name="check" size={20} />
              <span>Listo</span>
            </button>
          </div>
        </div>

        {showTips && <TipsModal onClose={() => setShowTips(false)} />}
      </div>
    )
  }

  // ════════════════════════════════════════════════════
  // STEP: scale — panel de referencia
  // ════════════════════════════════════════════════════
  if (step === 'scale') {
    const canProceed = refPoints.length === 2 && sanitizeNumber(refDist,{min:0.01}) !== null
    return (
      <div className="scan-camera-root">
        <canvas ref={canvasRef} className="scan-canvas scan-canvas-static"
          onPointerDown={handleRefTap}
          onTouchStart={(e) => { e.preventDefault(); handleRefTap(e) }}
          style={{ touchAction: 'none' }} />

        <div className="scan-hud-top safe-top">
          <button className="scan-tips-btn" onClick={() => setShowTips(true)}>
            <Icon name="info" size={14} /> Consejos
          </button>
          <button className="scan-close-btn" onClick={onCancel}>
            <Icon name="close" size={16} />
          </button>
        </div>

        <div className="scan-instruction-badge">
          {refPoints.length === 0 && 'Toca el inicio de una pared conocida'}
          {refPoints.length === 1 && 'Toca el final de esa misma pared'}
          {refPoints.length === 2 && 'Referencia marcada — introduce la distancia'}
        </div>

        <div className="scan-scale-panel">
          <div className="scan-scale-title">Referencia de escala</div>
          <div className="scan-scale-subtitle">¿Cuánto mide esa distancia en metros?</div>
          <div className="scale-input-row">
            <input type="number" placeholder="Ej. 3.50"
              min="0.01" max="100" step="0.01"
              value={refDist} onChange={(e)=>setRefDist(e.target.value)}
              inputMode="decimal" autoFocus />
            <span className="scale-unit">m</span>
          </div>
          <div className="scale-actions">
            <button className="btn btn-ghost btn-sm" onClick={() => {
              setRefPoints([]); setStep('corners'); setCorners([]); start()
            }}>
              <Icon name="undo" size={14} /> Re-escanear
            </button>
            <button className="btn btn-primary" onClick={handleCalculate} disabled={!canProceed}>
              Calcular m²
            </button>
          </div>
        </div>

        {showTips && <TipsModal onClose={() => setShowTips(false)} />}
      </div>
    )
  }

  // ════════════════════════════════════════════════════
  // STEP: manual
  // ════════════════════════════════════════════════════
  if (step === 'manual') {
    return <ManualForm onComplete={onComplete} onBack={() => setStep('permission')} />
  }

  return null
}

// ── Modal de consejos ──────────────────────────────────────────────────────────
function TipsModal({ onClose }) {
  const TIPS = [
    'Apunta la cámara hacia el suelo de la habitación',
    'Toca cada esquina del suelo siguiendo el perímetro en orden (horario o antihorario)',
    'Cuantas más esquinas marques, más precisa será la medición',
    'Para la referencia de escala, elige una pared recta cuya longitud conozcas',
    'Usa el botón Deshacer si te equivocas al marcar una esquina',
  ]
  return (
    <div className="scan-tips-overlay" onClick={(e)=>e.target===e.currentTarget&&onClose()}>
      <div className="scan-tips-sheet">
        <div className="scan-tips-handle" />
        <div style={{display:'flex',justifyContent:'space-between',alignItems:'center'}}>
          <div className="scan-tips-title">Consejos de escaneo</div>
          <button className="sheet-close" onClick={onClose} style={{position:'static'}}>
            <Icon name="close" size={14} />
          </button>
        </div>
        {TIPS.map((tip, i) => (
          <div key={i} className="scan-tip-item">
            <div className="scan-tip-num">{i+1}</div>
            <div className="scan-tip-text">{tip}</div>
          </div>
        ))}
        <button className="btn btn-primary" onClick={onClose}>Entendido</button>
      </div>
    </div>
  )
}

// ── Formulario manual ──────────────────────────────────────────────────────────
function ManualForm({ onComplete, onBack }) {
  const [width, setWidth]       = useState('')
  const [length, setLength]     = useState('')
  const [roomName, setRoomName] = useState('')
  const w = sanitizeNumber(width,  { min:0.1, max:999 })
  const l = sanitizeNumber(length, { min:0.1, max:999 })
  const computed = w && l ? (w*l).toFixed(2) : null

  function handleSubmit(e) {
    e.preventDefault()
    if (!computed) return
    const area = parseFloat(computed)
    onComplete({ floorArea: area, areaSqM: area, roomName: sanitizeName(roomName)||'Habitación', dimensions:`${w} m × ${l} m`, scanMode:'manual' })
  }

  return (
    <div className="scan-start-root">
      <div className="scan-start-content safe-top safe-bottom">
        <div className="scan-icon"><Icon name="manual" size={38} /></div>
        <h2>Medición manual</h2>
        <p className="muted" style={{fontSize:14}}>Introduce las dimensiones de la estancia.</p>
        <form className="manual-form glass" onSubmit={handleSubmit}>
          <div className="form-field">
            <label>Nombre de la estancia</label>
            <input type="text" placeholder="Ej. Salón" value={roomName} onChange={(e)=>setRoomName(e.target.value)} maxLength={100} />
          </div>
          <div className="form-row">
            <div className="form-field">
              <label>Ancho (m)</label>
              <input type="number" placeholder="4.20" min="0.1" max="999" step="0.01" value={width} onChange={(e)=>setWidth(e.target.value)} inputMode="decimal" />
            </div>
            <div className="form-field">
              <label>Largo (m)</label>
              <input type="number" placeholder="3.80" min="0.1" max="999" step="0.01" value={length} onChange={(e)=>setLength(e.target.value)} inputMode="decimal" />
            </div>
          </div>
          {computed && (
            <div className="manual-result">
              <span className="muted">Superficie calculada</span>
              <span className="manual-area">{computed} m²</span>
            </div>
          )}
          <div className="form-actions">
            <button type="button" className="btn btn-ghost" onClick={onBack}><Icon name="back" size={16} /> Volver</button>
            <button type="submit" className="btn btn-primary" disabled={!computed}>Continuar →</button>
          </div>
        </form>
      </div>
    </div>
  )
}

function ScanStep({ n, text }) {
  return (
    <div className="home-step">
      <div className="home-step-n">{n}</div>
      <p>{text}</p>
    </div>
  )
}

// ── Canvas helpers ─────────────────────────────────────────────────────────────
function drawPolygon(ctx, points) {
  if (points.length === 0) return
  if (points.length >= 3) {
    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y))
    ctx.closePath()
    ctx.fillStyle = 'rgba(240,165,0,0.12)'
    ctx.fill()
  }
  if (points.length >= 2) {
    ctx.beginPath()
    ctx.moveTo(points[0].x, points[0].y)
    points.slice(1).forEach((p) => ctx.lineTo(p.x, p.y))
    if (points.length >= 3) ctx.closePath()
    ctx.strokeStyle = 'rgba(240,165,0,0.9)'
    ctx.lineWidth = 2; ctx.setLineDash([6,4]); ctx.stroke(); ctx.setLineDash([])
  }
  points.forEach((p, i) => {
    ctx.beginPath(); ctx.arc(p.x, p.y, 14, 0, Math.PI*2)
    ctx.fillStyle = i===0 ? 'rgba(45,212,191,0.2)' : 'rgba(240,165,0,0.2)'; ctx.fill()
    ctx.beginPath(); ctx.arc(p.x, p.y, 9, 0, Math.PI*2)
    ctx.fillStyle = i===0 ? 'rgba(45,212,191,0.95)' : 'rgba(240,165,0,0.95)'; ctx.fill()
    ctx.strokeStyle='#fff'; ctx.lineWidth=2; ctx.stroke()
    ctx.fillStyle='#0c0a08'; ctx.font='bold 11px -apple-system,sans-serif'
    ctx.textAlign='center'; ctx.textBaseline='middle'; ctx.fillText(i+1, p.x, p.y)
  })
}

function drawRefPoints(ctx, points) {
  points.forEach((p) => {
    ctx.beginPath(); ctx.arc(p.x, p.y, 10, 0, Math.PI*2)
    ctx.fillStyle='rgba(251,191,36,0.95)'; ctx.fill()
    ctx.strokeStyle='#fff'; ctx.lineWidth=2; ctx.stroke()
  })
  if (points.length === 2) {
    ctx.beginPath(); ctx.moveTo(points[0].x, points[0].y); ctx.lineTo(points[1].x, points[1].y)
    ctx.strokeStyle='rgba(251,191,36,0.9)'; ctx.lineWidth=2; ctx.setLineDash([5,3]); ctx.stroke(); ctx.setLineDash([])
  }
}
