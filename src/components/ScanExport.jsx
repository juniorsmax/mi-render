import { useRef, useState } from 'react'
import { FloorPlan } from './FloorPlan'
import { Icon } from './Icon'
import { Capacitor } from '@capacitor/core'
import { exportOBJ, exportPLY, exportSTL, saveWorldMap } from '../lib/lidar'
import './ScanExport.css'

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
  } = result

  // ── Exportar PDF via print ─────────────────────────────────────────────────
  function handleExportPDF() {
    const printWindow = window.open('', '_blank')
    const canvas = reportRef.current?.querySelector('canvas')
    const planDataUrl = canvas?.toDataURL('image/png') ?? ''
    const date = new Date().toLocaleDateString('es-ES', { day: '2-digit', month: 'long', year: 'numeric' })

    printWindow.document.write(`
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>Informe de escaneo — ${projectName}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, Helvetica, Arial, sans-serif; color: #1a1a1a; background: #fff; }
    .page { width: 210mm; min-height: 297mm; padding: 20mm 18mm; }
    .header { display: flex; justify-content: space-between; align-items: flex-start; padding-bottom: 12px; border-bottom: 2px solid #1a1a1a; margin-bottom: 20px; }
    .title h1 { font-size: 22px; font-weight: 700; }
    .title p  { font-size: 12px; color: #666; margin-top: 4px; }
    .brand { font-size: 13px; font-weight: 700; color: #f0a500; }
    .content { display: flex; gap: 24px; }
    .plan { flex: 1; }
    .plan img { width: 100%; border: 1px solid #ddd; }
    .stats { width: 200px; }
    .stats h2 { font-size: 13px; font-weight: 700; margin-bottom: 12px; }
    .stat-row { display: flex; justify-content: space-between; padding: 5px 0; border-bottom: 1px solid #eee; font-size: 12px; }
    .stat-row .label { color: #555; }
    .stat-row .value { font-weight: 600; }
    .footer { margin-top: 24px; padding-top: 12px; border-top: 1px solid #eee; font-size: 10px; color: #999; text-align: center; }
    .date { font-size: 11px; color: #888; }
  </style>
</head>
<body>
  <div class="page">
    <div class="header">
      <div class="title">
        <h1>${projectName}</h1>
        ${address ? `<p>${address}</p>` : ''}
        <p class="date">Generado el ${date}</p>
      </div>
      <div class="brand">mi-render · zerbitecni</div>
    </div>
    <div class="content">
      <div class="plan">
        ${planDataUrl ? `<img src="${planDataUrl}" alt="Plano 2D">` : '<p style="color:#999;font-size:12px;">Plano no disponible</p>'}
      </div>
      <div class="stats">
        <h2>Métricas</h2>
        <div class="stat-row"><span class="label">Superficie total</span><span class="value">${floorArea.toFixed(1)} m²</span></div>
        <div class="stat-row"><span class="label">Área de paredes</span><span class="value">${wallArea.toFixed(1)} m²</span></div>
        <div class="stat-row"><span class="label">Área de ventanas</span><span class="value">${windowArea.toFixed(2)} m²</span></div>
        <div class="stat-row"><span class="label">Volumen total</span><span class="value">${totalVolume.toFixed(2)} m³</span></div>
        <div class="stat-row"><span class="label">Perímetro</span><span class="value">${perimeter.toFixed(1)} m</span></div>
        <div class="stat-row"><span class="label">Altura media</span><span class="value">${avgHeight.toFixed(2)} m</span></div>
        <div class="stat-row"><span class="label">Nº paredes</span><span class="value">${wallCount}</span></div>
        <div class="stat-row"><span class="label">Puertas</span><span class="value">${doors.length}</span></div>
        <div class="stat-row"><span class="label">Ventanas</span><span class="value">${windows.length}</span></div>
        ${latitude != null ? `<div class="stat-row"><span class="label">Latitud</span><span class="value">${latitude.toFixed(6)} N</span></div>` : ''}
        ${longitude != null ? `<div class="stat-row"><span class="label">Longitud</span><span class="value">${longitude.toFixed(6)} E</span></div>` : ''}
        ${altitude != null ? `<div class="stat-row"><span class="label">Altitud</span><span class="value">${Math.round(altitude)} m</span></div>` : ''}
      </div>
    </div>
    <div class="footer">
      Resultados estimados por sensor LiDAR. Generado con mi-render · zerbitecni.com
    </div>
  </div>
  <script>window.onload=()=>window.print()</script>
</body>
</html>`)
    printWindow.document.close()
  }

  // ── Exportar USDZ (share sheet nativa) ────────────────────────────────────
  async function handleExportUSDZ() {
    if (!Capacitor.isNativePlatform()) {
      alert('La exportación USDZ solo está disponible en la app iOS')
      return
    }
    try {
      await Capacitor.nativePromise('LiDARPlugin', 'exportUSDZ', {})
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
      if (format === 'obj') await exportOBJ(name)
      if (format === 'ply') await exportPLY(name)
      if (format === 'stl') await exportSTL(name)
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
        {walls.length > 0 && (
          <div className="scan-export-plan">
            <div className="scan-export-plan-label">
              <Icon name="plan" size={13} />
              Plano de planta
            </div>
            <FloorPlan
              walls={walls}
              doors={doors}
              windows={windows}
              openings={openings}
              size={Math.min(window.innerWidth - 56, 360)}
              padding={28}
            />
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
            value={`${totalVolume.toFixed(1)}`}
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
        </div>

        {/* Botones de exportación */}
        <div className="scan-export-actions">
          <ExportBtn
            iconText="PDF"
            label="Informe PDF"
            sub="Plano + métricas para imprimir"
            onClick={handleExportPDF}
          />
          {usdzExported && (
            <ExportBtn
              iconText="3D"
              label="Modelo USDZ"
              sub="Modelo 3D para AR Quick Look"
              onClick={handleExportUSDZ}
              accent
            />
          )}

          {/* Exportación de malla 3D — solo nativo */}
          {Capacitor.isNativePlatform() && (
            <div className="export-3d-group">
              <div className="export-3d-label">
                <Icon name="scan" size={11} /> Malla 3D
              </div>
              <div className="export-3d-row">
                {['obj', 'ply', 'stl'].map(fmt => (
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

        {/* Acciones principales */}
        <div className="scan-export-main-actions">
          <button className="btn btn-primary btn-lg" onClick={onAccept}>
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
