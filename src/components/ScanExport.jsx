import { useRef, useState, useEffect } from 'react'
import { FloorPlan } from './FloorPlan'
import { Icon } from './Icon'
import { Capacitor } from '@capacitor/core'
import { exportOBJ, exportPLY, exportSTL, exportDAE, exportSVG, exportDXF, exportPDF as exportPDFNative, exportGLTF, exportGLB, exportAllFormats, saveWorldMap, exportUSDZ as exportUSDZNative, startWalkthrough, getWallMetrics, getSurfaceAreas, getRoomSegmentation, getAutoVolume, exportIFC, exportOptimizedUSDZ, openViewer } from '../lib/lidar'
import './ScanExport.css'

async function shareOrSavePDF(blob, filename) {
  const file = new File([blob], filename, { type: 'application/pdf' })
  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    await navigator.share({ files: [file], title: filename })
  } else {
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url; a.download = filename; a.click()
    setTimeout(() => URL.revokeObjectURL(url), 5000)
  }
}

/**
 * ScanExport — Pantalla de resultados + exportación
 * Agentes: Luna (UI) + Atlas (datos) + Ares (export)
 *
 * Muestra:
 *  - Badge de modo de escaneo
 *  - Plano 2D de la habitación (FloorPlan)
 *  - Tarjetas de métricas con animación escalonada
 *  - Tabla de detalles
 *  - Botones de exportación
 */
export function ScanExport({ result, projectName = 'Mi habitación', address = '', onAccept, onRescan }) {
  const reportRef = useRef(null)
  const [exportingFormat, setExportingFormat] = useState(null)
  const [worldMapSaved, setWorldMapSaved]     = useState(false)
  const [wallMetrics, setWallMetrics]         = useState(null)
  const [roomSegments, setRoomSegments]       = useState(null)   // { rooms, totalVolume }
  const [autoVolume, setAutoVolume]           = useState(null)   // { totalVolume }
  const [exportingAdvanced, setExportingAdv]  = useState(null)   // 'ifc' | 'usdz-opt'

  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return
    getWallMetrics()
      .then(data => { if (data?.walls?.length) setWallMetrics(data) })
      .catch(() => {})
    getRoomSegmentation()
      .then(data => { if (data?.roomCount > 0) setRoomSegments(data) })
      .catch(() => {})
    getAutoVolume()
      .then(data => { if (data?.totalVolume > 0) setAutoVolume(data) })
      .catch(() => {})
  }, [])

  if (!result) return null

  const {
    floorArea   = 0,
    wallArea    = 0,
    windowArea  = 0,
    totalVolume = 0,
    perimeter   = 0,
    avgHeight   = 2.5,
    walls       = [],
    doors       = [],
    windows     = [],
    openings    = [],
    wallCount   = 0,
    confidence  = 'high',
    scanMode    = 'lidar',
    latitude,
    longitude,
    altitude,
    usdzExported = false,
    usdzPath     = null,
    photoCount   = 0,
    projectId    = null,
  } = result

  const isPhotogrammetry = scanMode === 'photogrammetry'

  // ── Compartir modelo USDZ fotogramétrico ─────────────────────────────────
  async function handleSharePhotogrammetry() {
    if (!Capacitor.isNativePlatform()) {
      alert('Solo disponible en la app iOS')
      return
    }
    try {
      // El USDZ ya está en disco — lo compartimos vía share sheet → AR Quick Look
      const { Filesystem } = await import('@capacitor/filesystem')
      const { Share }      = await import('@capacitor/share')
      await Share.share({
        title: projectName,
        url:   'file://' + usdzPath,
        dialogTitle: 'Abrir recorrido 3D',
      })
    } catch (err) {
      // Fallback: exportar desde el plugin
      try { await exportUSDZNative(projectName.replace(/\s+/g, '-').toLowerCase()) }
      catch {}
    }
  }

  // ── Exportar PDF del informe de escaneo ───────────────────────────────────
  async function handleExportPDF() {
    try {
      const { default: jsPDF } = await import('jspdf')
      const canvas = reportRef.current?.querySelector('canvas')
      const planDataUrl = canvas?.toDataURL('image/png') ?? null
      const date = new Date().toLocaleDateString('es-ES', { day: '2-digit', month: 'long', year: 'numeric' })

      const doc = new jsPDF({ unit: 'mm', format: 'a4' })
      const W = doc.internal.pageSize.getWidth()

      // Header
      doc.setFillColor(10, 12, 18)
      doc.rect(0, 0, W, 28, 'F')
      doc.setTextColor(240, 165, 0)
      doc.setFontSize(20); doc.setFont('helvetica', 'bold')
      doc.text(projectName || 'Informe de escaneo', 14, 16)
      doc.setTextColor(107, 115, 133)
      doc.setFontSize(8); doc.setFont('helvetica', 'normal')
      doc.text('mi-render · zerbitecni', W - 14, 16, { align: 'right' })
      doc.text(date, W - 14, 22, { align: 'right' })
      if (address) {
        doc.setTextColor(200, 205, 216); doc.setFontSize(9)
        doc.text(address, 14, 22)
      }

      let y = 36

      // Plano 2D
      if (planDataUrl) {
        doc.addImage(planDataUrl, 'PNG', 14, y, 90, 70)
      }

      // Métricas
      const mx = planDataUrl ? 112 : 14
      doc.setTextColor(238, 240, 245); doc.setFontSize(10); doc.setFont('helvetica', 'bold')
      doc.text('Métricas', mx, y + 4)
      doc.setFont('helvetica', 'normal'); doc.setFontSize(9)

      const stats = [
        ['Superficie', `${floorArea.toFixed(1)} m²`],
        ['Área paredes', `${wallArea.toFixed(1)} m²`],
        ['Área ventanas', `${windowArea.toFixed(2)} m²`],
        ['Volumen', `${totalVolume.toFixed(2)} m³`],
        ['Perímetro', `${perimeter.toFixed(1)} m`],
        ['Altura media', `${avgHeight.toFixed(2)} m`],
        ['Paredes', wallCount],
        ['Puertas', doors.length],
        ['Ventanas', windows.length],
        ...(latitude  != null ? [['Latitud',  `${latitude.toFixed(4)} N`]] : []),
        ...(longitude != null ? [['Longitud', `${longitude.toFixed(4)} E`]] : []),
        ...(altitude  != null ? [['Altitud',  `${Math.round(altitude)} m`]] : []),
      ]

      stats.forEach(([label, value], i) => {
        const row = y + 12 + i * 7
        doc.setTextColor(107, 115, 133); doc.text(String(label), mx, row)
        doc.setTextColor(238, 240, 245); doc.text(String(value), mx + 62, row, { align: 'right' })
        doc.setDrawColor(30, 35, 50); doc.line(mx, row + 1.5, mx + 62, row + 1.5)
      })

      // Footer
      const footerY = doc.internal.pageSize.getHeight() - 10
      doc.setFontSize(8); doc.setTextColor(107, 115, 133); doc.setFont('helvetica', 'italic')
      doc.text('Resultados estimados por sensor LiDAR. mi-render · zerbitecni.com', W / 2, footerY, { align: 'center' })

      const filename = `informe-${(projectName || 'escaneo').replace(/\s+/g, '-').toLowerCase()}.pdf`
      const blob = doc.output('blob')
      await shareOrSavePDF(blob, filename)
    } catch (err) {
      console.error('Error generando PDF:', err)
      alert('Error al generar el PDF: ' + err.message)
    }
  }

  // ── Exportar USDZ (share sheet nativa) ────────────────────────────────────
  async function handleExportUSDZ() {
    if (!Capacitor.isNativePlatform()) {
      alert('La exportación USDZ solo está disponible en la app iOS')
      return
    }
    try {
      const name = projectName.replace(/\s+/g, '-').toLowerCase()
      await exportUSDZNative(name)
    } catch (err) {
      console.error('Error exportando USDZ:', err)
    }
  }

  // ── Exportar malla 3D (OBJ / PLY / STL) ───────────────────────────────────
  async function handle3DExport(format) {
    if (!Capacitor.isNativePlatform()) {
      alert(`La exportación ${format.toUpperCase()} solo está disponible en la app iOS`)
      return
    }
    setExportingFormat(format)
    try {
      const name = projectName.replace(/\s+/g, '-').toLowerCase()
      if (format === 'obj')  await exportOBJ(name)
      if (format === 'ply')  await exportPLY(name)
      if (format === 'stl')  await exportSTL(name)
      if (format === 'dae')  await exportDAE(name)
      if (format === 'gltf') await exportGLTF(name)
      if (format === 'glb')  await exportGLB(name)
      if (format === 'svg')  await exportSVG(name)
      if (format === 'dxf')  await exportDXF(name)
      if (format === 'pdf')  await exportPDFNative(name)
    } catch (err) {
      console.error(`Error exportando ${format}:`, err)
    } finally {
      setExportingFormat(null)
    }
  }

  // ── Guardar WorldMap para re-scan futuro ───────────────────────────────────
  async function handleSaveWorldMap() {
    if (!Capacitor.isNativePlatform()) return
    try {
      const name = projectName.replace(/\s+/g, '-').toLowerCase() + '-' + Date.now()
      await saveWorldMap(name)
      setWorldMapSaved(true)
      setTimeout(() => setWorldMapSaved(false), 2500)
    } catch (err) {
      console.error('Error guardando WorldMap:', err)
    }
  }

  const confidenceColor = { high: '#2dd4bf', medium: '#f0a500', low: '#ef4444' }[confidence] ?? '#6b7280'
  const confidenceLabel = { high: 'Alta', medium: 'Media', low: 'Baja' }[confidence] ?? '–'

  const scanModeLabel = scanMode === 'lidar-native' || scanMode === 'lidar'
    ? 'LiDAR'
    : scanMode === 'camera'
      ? 'Cámara'
      : 'Manual'

  const scanModePill = scanMode === 'lidar-native' || scanMode === 'lidar'
    ? 'lidar'
    : scanMode === 'camera'
      ? 'camera'
      : 'manual'

  return (
    <div className="scan-export-root">
      <div className="scan-export-scroll" ref={reportRef}>

        {/* Header */}
        <div className="scan-export-header safe-top">
          <div>
            <h2 className="scan-export-title">{projectName}</h2>
            {address && <p className="scan-export-addr">{address}</p>}
          </div>
          <span className="scan-mode-badge"
            style={{ color: confidenceColor, borderColor: confidenceColor+'55', background: confidenceColor+'11', fontSize: 11 }}>
            <Icon name="lidar" size={11} /> {confidenceLabel} precisión
          </span>
        </div>

        {/* Badge modo de escaneo */}
        <div className="scan-mode-section">
          <div className="scan-mode-row">
            <span className="scan-mode-row-label">Modo de escaneo</span>
            <span className={`scan-mode-pill ${scanModePill}`}>
              <Icon name={scanModePill === 'lidar' ? 'lidar' : scanModePill === 'camera' ? 'camera' : 'manual'} size={11} />
              {scanModeLabel}
            </span>
          </div>
        </div>

        {/* Plano 2D */}
        <div className="scan-export-plan">
          <div className="scan-export-plan-label">
            <Icon name="plan" size={13} />
            Plano de planta
          </div>
          {walls.length > 0 ? (
            <FloorPlan
              walls={walls}
              doors={doors}
              windows={windows}
              openings={openings}
              size={Math.min(window.innerWidth - 56, 360)}
              padding={28}
            />
          ) : (
            <div className="scan-export-plan-empty">
              <div className="scan-export-plan-empty-icon">🏠</div>
              <p className="scan-export-plan-empty-text">No se detectó geometría de habitación</p>
              <p className="scan-export-plan-empty-sub">
                Mueve el iPhone más despacio y cubre todas las paredes, suelo y techo. El escaneo necesita al menos 15–20 segundos.
              </p>
            </div>
          )}
        </div>

        {/* ── Modelo 3D — LiDAR o fotogrametría ───────────────────────── */}
        {usdzPath && (
          <div className="scan-photogram-card glass">
            <div className="scan-photogram-icon">{isPhotogrammetry ? '📷' : '🏠'}</div>
            <div className="scan-photogram-info">
              <div className="scan-photogram-title">
                {isPhotogrammetry ? 'Modelo 3D fotogramétrico' : 'Modelo 3D de la habitación'}
              </div>
              <div className="scan-photogram-sub">
                {isPhotogrammetry
                  ? `${photoCount} fotos procesadas · USDZ con texturas reales`
                  : 'Escaneado con LiDAR · formato USDZ'}
              </div>
            </div>
            <div style={{ display: 'flex', gap: 8, width: '100%', marginTop: 12 }}>
              <button className="btn btn-primary" style={{ flex: 1 }}
                onClick={() => startWalkthrough(usdzPath)}>
                🚶 Recorrido 3D
              </button>
              <button className="btn btn-ghost" style={{ flex: 1 }}
                onClick={handleSharePhotogrammetry}>
                🥽 AR Quick Look
              </button>
            </div>
            <p style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 8, textAlign: 'center', lineHeight: 1.5 }}>
              Recorrido interior · Desliza para mirar · Toca para moverte
            </p>
          </div>
        )}

        {/* ── Habitaciones detectadas ──────────────────────────────────────── */}
        {roomSegments?.rooms?.length > 1 && (
          <div className="rooms-section">
            <div className="rooms-title">
              <Icon name="plan" size={13} />
              {roomSegments.rooms.length} habitaciones detectadas
            </div>
            <div className="rooms-grid">
              {roomSegments.rooms.map((room, i) => (
                <div key={room.id ?? i} className="room-card glass">
                  <div className="room-card-label">{room.label}</div>
                  <div className="room-card-area">{room.area?.toFixed(1)}<span>m²</span></div>
                  {room.volume > 0 && (
                    <div className="room-card-vol">{room.volume?.toFixed(1)} m³</div>
                  )}
                  {room.avgHeight > 0 && (
                    <div className="room-card-h">{room.avgHeight?.toFixed(2)} m alt.</div>
                  )}
                </div>
              ))}
            </div>
            {roomSegments.totalVolume > 0 && (
              <div className="rooms-total">
                Volumen total: <strong>{roomSegments.totalVolume?.toFixed(1)} m³</strong>
              </div>
            )}
          </div>
        )}

        {/* Aviso si todo es cero */}
        {!isPhotogrammetry && floorArea === 0 && walls.length === 0 && (
          <div className="scan-export-warning">
            <span style={{ fontSize: 16 }}>⚠️</span>
            <span>Escaneo incompleto — pulsa <strong>Re-escanear</strong> y mueve el iPhone lentamente por toda la estancia.</span>
          </div>
        )}

        {/* Tarjetas de métricas — 6 cards en grid 3×2 */}
        <div className="scan-export-metrics">
          <MetricCard
            icon={<AreaIcon />}
            iconClass="amber"
            value={`${floorArea.toFixed(1)}`}
            unit="m²"
            label="Superficie"
            accent
          />
          <MetricCard
            icon={<VolumeIcon />}
            iconClass="amber"
            value={(autoVolume?.totalVolume ?? totalVolume).toFixed(1)}
            unit="m³"
            label="Volumen"
          />
          <MetricCard
            icon={<PerimeterIcon />}
            iconClass="teal"
            value={`${perimeter.toFixed(1)}`}
            unit="m"
            label="Perímetro"
            teal
          />
          <MetricCard
            icon={<WallIcon />}
            iconClass="amber"
            value={wallCount}
            label="Paredes"
          />
          <MetricCard
            icon={<DoorIcon />}
            iconClass="teal"
            value={doors.length}
            label="Puertas"
            teal
          />
          <MetricCard
            icon={<WindowIcon />}
            iconClass="blue"
            value={windows.length}
            label="Ventanas"
          />
        </div>

        {/* Stats tabla — detalles */}
        <div className="scan-export-stats glass">
          <div className="scan-export-stats-title">Detalle completo</div>
          <StatRow label="Área de paredes"  value={`${wallArea.toFixed(1)} m²`} />
          <StatRow label="Área de ventanas" value={`${windowArea.toFixed(2)} m²`} />
          <StatRow label="Altura media"     value={`${avgHeight.toFixed(2)} m`} />
          <StatRow label="Aberturas"        value={openings.length} />
          {latitude  != null && <StatRow label="Latitud"  value={`${latitude.toFixed(6)} N`} />}
          {longitude != null && <StatRow label="Longitud" value={`${longitude.toFixed(6)} E`} />}
          {altitude  != null && <StatRow label="Altitud"  value={`${Math.round(altitude)} m`} />}
          {wallMetrics?.walls?.length > 0 && (
            <WallMetricsSection walls={wallMetrics.walls} />
          )}
        </div>

        {/* Botones de exportación */}
        <div className="scan-export-actions">
          <ExportBtn
            iconText="PDF"
            label="Informe PDF"
            sub="Plano + métricas para imprimir"
            onClick={handleExportPDF}
          />
          {(usdzExported || usdzPath) && (
            <ExportBtn
              iconText="3D"
              label="Modelo USDZ"
              sub="Modelo 3D para AR Quick Look"
              onClick={handleExportUSDZ}
              accent
            />
          )}

          {/* Ver modelo 3D guardado — solo si hay projectId nativo */}
          {projectId && Capacitor.isNativePlatform() && (
            <button
              className="export-btn accent"
              onClick={() => openViewer(projectId)}
            >
              <div className="export-btn-icon" style={{ background: 'rgba(45,212,191,0.15)', color: '#2dd4bf' }}>🧊</div>
              <div>
                <div className="export-btn-label">Ver modelo 3D</div>
                <div className="export-btn-sub">Visor nativo · modelo guardado en la app</div>
              </div>
            </button>
          )}

          {/* Exportación de malla 3D — solo nativo */}
          {Capacitor.isNativePlatform() && (
            <div className="export-3d-group">
              <div className="export-3d-label">
                <Icon name="scan" size={11} /> Malla 3D
              </div>
              <div className="export-3d-row">
                {['obj', 'ply', 'stl', 'dae', 'gltf', 'glb'].map(fmt => (
                  <button
                    key={fmt}
                    className={`export-3d-btn ${exportingFormat === fmt ? 'loading' : ''}`}
                    onClick={() => handle3DExport(fmt)}
                    disabled={!!exportingFormat}
                  >
                    {exportingFormat === fmt
                      ? <span className="spinner" style={{ width: 12, height: 12 }} />
                      : fmt.toUpperCase()
                    }
                  </button>
                ))}
              </div>
              <div className="export-3d-label" style={{ marginTop: 8 }}>
                <Icon name="plan" size={11} /> Plano vectorial
              </div>
              <div className="export-3d-row">
                {['svg', 'dxf', 'pdf'].map(fmt => (
                  <button
                    key={fmt}
                    className={`export-3d-btn ${exportingFormat === fmt ? 'loading' : ''}`}
                    onClick={() => handle3DExport(fmt)}
                    disabled={!!exportingFormat}
                  >
                    {exportingFormat === fmt
                      ? <span className="spinner" style={{ width: 12, height: 12 }} />
                      : fmt.toUpperCase()
                    }
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Exportación avanzada — BIM + USDZ optimizado */}
          {Capacitor.isNativePlatform() && (
            <div className="export-advanced-group">
              <div className="export-3d-label">
                <Icon name="scan" size={11} /> Avanzado
              </div>
              <button
                className={`export-btn ${exportingAdvanced === 'ifc' ? 'loading' : ''}`}
                disabled={!!exportingAdvanced}
                onClick={async () => {
                  setExportingAdv('ifc')
                  try {
                    const name = projectName.replace(/\s+/g, '-').toLowerCase()
                    await exportIFC(name, { projectName })
                  } catch (err) {
                    console.error('exportIFC error:', err)
                  } finally { setExportingAdv(null) }
                }}
              >
                <div className="export-btn-icon" style={{ background: 'rgba(99,102,241,0.18)', color: '#818cf8' }}>
                  {exportingAdvanced === 'ifc'
                    ? <span className="spinner" style={{ width: 14, height: 14 }} />
                    : 'IFC'}
                </div>
                <div>
                  <div className="export-btn-label">Exportar IFC (BIM)</div>
                  <div className="export-btn-sub">ArchiCAD · Revit · FreeCAD · Solibri</div>
                </div>
              </button>
              <button
                className={`export-btn ${exportingAdvanced === 'usdz-opt' ? 'loading' : ''}`}
                disabled={!!exportingAdvanced}
                onClick={async () => {
                  setExportingAdv('usdz-opt')
                  try {
                    const name = projectName.replace(/\s+/g, '-').toLowerCase()
                    await exportOptimizedUSDZ(name)
                  } catch (err) {
                    console.error('exportOptimizedUSDZ error:', err)
                  } finally { setExportingAdv(null) }
                }}
              >
                <div className="export-btn-icon" style={{ background: 'rgba(45,212,191,0.15)', color: '#2dd4bf' }}>
                  {exportingAdvanced === 'usdz-opt'
                    ? <span className="spinner" style={{ width: 14, height: 14 }} />
                    : 'AR+'}
                </div>
                <div>
                  <div className="export-btn-label">USDZ Optimizado</div>
                  <div className="export-btn-sub">Materiales PBR · Apple ecosystem ready</div>
                </div>
              </button>
            </div>
          )}

          {/* Guardar entorno espacial */}
          {Capacitor.isNativePlatform() && (
            <button
              className={`export-worldmap-btn ${worldMapSaved ? 'saved' : ''}`}
              onClick={handleSaveWorldMap}
            >
              <Icon name={worldMapSaved ? 'check' : 'scan'} size={16} />
              <div>
                <div className="export-btn-label">
                  {worldMapSaved ? 'Entorno guardado ✓' : 'Guardar entorno AR'}
                </div>
                <div className="export-btn-sub">Permite re-scan y detección de cambios</div>
              </div>
            </button>
          )}
        </div>

        {/* Exportar todo */}
        {Capacitor.isNativePlatform() && (
          <div style={{ padding: '0 14px' }}>
            <button
              className="export-btn accent"
              style={{ width: '100%' }}
              onClick={async () => {
                try {
                  const name = projectName.replace(/\s+/g, '-').toLowerCase()
                  await exportAllFormats(name)
                  alert('Todos los formatos exportados a Documents/Exports')
                } catch (err) {
                  console.error('exportAllFormats error:', err)
                }
              }}
            >
              <div className="export-btn-icon">ALL</div>
              <div>
                <div className="export-btn-label">Exportar todos los formatos</div>
                <div className="export-btn-sub">OBJ · PLY · STL · USDZ · DAE · DXF · SVG · PDF · GLTF · GLB</div>
              </div>
            </button>
          </div>
        )}

        {/* Acciones principales */}
        <div className="scan-export-main-actions">
          <button className="btn btn-primary btn-lg" onClick={() => {
            const canvas = reportRef.current?.querySelector('canvas')
            const thumbnail = canvas ? canvas.toDataURL('image/png', 0.6) : null
            onAccept(thumbnail)
          }}>
            <Icon name="check" size={18} /> Usar para presupuesto
          </button>
          <button className="btn btn-ghost" onClick={onRescan}>
            <Icon name="scan" size={16} /> Re-escanear
          </button>
        </div>

        <div className="scan-export-footer safe-bottom">
          Resultados estimados por sensor LiDAR. mi-render · zerbitecni.com
        </div>
      </div>
    </div>
  )
}

/* ── Tarjeta de métrica ──────────────────────────────────────────────────────── */
function MetricCard({ icon, iconClass = 'amber', value, unit, label, accent, teal }) {
  return (
    <div className="scan-metric-card">
      <div className={`scan-metric-icon ${iconClass}`}>{icon}</div>
      <div className={`scan-metric-value ${accent ? 'accent' : teal ? 'teal' : ''}`}>
        {value}{unit ? <span style={{ fontSize: '0.65em', marginLeft: 2, fontWeight: 600, opacity: 0.7 }}>{unit}</span> : ''}
      </div>
      <div className="scan-metric-label">{label}</div>
    </div>
  )
}

/* ── StatRow ─────────────────────────────────────────────────────────────────── */
function StatRow({ label, value, accent }) {
  return (
    <div className="stat-row">
      <span className="stat-label">{label}</span>
      <span className="stat-value" style={accent ? { color: 'var(--accent)', fontFamily: 'var(--font-mono)', fontSize: '1.05rem' } : {}}>
        {value}
      </span>
    </div>
  )
}

/* ── WallMetricsSection ──────────────────────────────────────────────────────── */
function WallMetricsSection({ walls }) {
  return (
    <>
      <div className="stat-section-header">
        <WallIcon />
        Paredes detectadas
      </div>
      {walls.map((w, i) => (
        <div key={w.id ?? i} className="stat-row wall-row">
          <span className="stat-label">
            <span className="wall-label-pill">{w.label ?? `P${i + 1}`}</span>
          </span>
          <span className="stat-value" style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
            <span style={{ color: 'var(--text-muted)', fontSize: '0.8em' }}>
              {w.dimensions?.width != null && w.dimensions?.height != null
                ? `${w.dimensions.width.toFixed(2)}×${w.dimensions.height.toFixed(2)} m`
                : ''}
            </span>
            <span>{w.area != null ? `${w.area.toFixed(2)} m²` : '—'}</span>
          </span>
        </div>
      ))}
    </>
  )
}

/* ── ExportBtn ───────────────────────────────────────────────────────────────── */
function ExportBtn({ iconText, label, sub, onClick, accent }) {
  return (
    <button className={`export-btn ${accent ? 'accent' : ''}`} onClick={onClick}>
      <div className="export-btn-icon">
        {iconText}
      </div>
      <div>
        <div className="export-btn-label">{label}</div>
        <div className="export-btn-sub">{sub}</div>
      </div>
      <Icon name="download" size={18} style={{ marginLeft: 'auto', opacity: 0.45 }} />
    </button>
  )
}

/* ── Iconos SVG inline para métricas ─────────────────────────────────────────── */
function AreaIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <rect x="2" y="2" width="12" height="12" rx="1.5" stroke="currentColor" strokeWidth="1.5"/>
      <path d="M5 8h6M8 5v6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/>
    </svg>
  )
}
function VolumeIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M8 2L13 5v6L8 14 3 11V5L8 2z" stroke="currentColor" strokeWidth="1.4" strokeLinejoin="round"/>
      <path d="M8 2v12M3 5l5 3 5-3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  )
}
function PerimeterIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <rect x="2.5" y="2.5" width="11" height="11" rx="1" stroke="currentColor" strokeWidth="1.5" strokeDasharray="3 1.5"/>
    </svg>
  )
}
function WallIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M2 4h12M2 8h12M2 12h12M5 4v4M11 8v4M8 4v8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/>
    </svg>
  )
}
function DoorIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <path d="M4 13V3h8v10" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M2 13h12" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/>
      <path d="M10 8.5a.5.5 0 1 1-1 0 .5.5 0 0 1 1 0z" fill="currentColor"/>
    </svg>
  )
}
function WindowIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <rect x="2.5" y="4.5" width="11" height="7" rx="1" stroke="currentColor" strokeWidth="1.4"/>
      <path d="M8 4.5v7M2.5 8h11" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/>
    </svg>
  )
}
