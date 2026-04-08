import { useRef } from 'react'
import { FloorPlan } from './FloorPlan'
import { Icon } from './Icon'
import { Capacitor } from '@capacitor/core'
import './ScanExport.css'

/**
 * ScanExport — Pantalla de resultados + exportación
 * Agentes: Luna (UI) + Atlas (datos) + Ares (export)
 *
 * Muestra:
 *  - Plano 2D de la habitación (FloorPlan)
 *  - Estadísticas completas (como Polycam)
 *  - Botones: PDF, USDZ, Compartir
 */
export function ScanExport({ result, projectName = 'Mi habitación', address = '', onAccept, onRescan }) {
  const reportRef = useRef(null)

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
    latitude,
    longitude,
    altitude,
    usdzExported = false,
  } = result

  // ── Exportar PDF via print ────────────────────────────────────────────────
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
      <div class="brand">mi-render</div>
    </div>
    <div class="content">
      <div class="plan">
        ${planDataUrl ? `<img src="${planDataUrl}" alt="Plano 2D">` : '<p style="color:#999;font-size:12px;">Plano no disponible</p>'}
      </div>
      <div class="stats">
        <h2>Overview</h2>
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
      Los resultados son estimaciones del sensor LiDAR y pueden variar. Generado con mi-render · zerbitecni.com
    </div>
  </div>
  <script>window.onload=()=>window.print()</script>
</body>
</html>`)
    printWindow.document.close()
  }

  // ── Exportar USDZ (share sheet nativa) ───────────────────────────────────
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

  const confidenceColor = { high: '#2dd4bf', medium: '#f0a500', low: '#ef4444' }[confidence] ?? '#6b7280'

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
            <Icon name="lidar" size={11} /> LiDAR · {confidence === 'high' ? 'Alta' : confidence === 'medium' ? 'Media' : 'Baja'} precisión
          </span>
        </div>

        {/* Plano 2D */}
        {walls.length > 0 && (
          <div className="scan-export-plan">
            <div className="scan-export-plan-label">
              <Icon name="plan" size={14} />
              Plano de planta
            </div>
            <FloorPlan
              walls={walls}
              doors={doors}
              windows={windows}
              openings={openings}
              size={Math.min(window.innerWidth - 32, 380)}
              padding={28}
            />
          </div>
        )}

        {/* Stats — estilo Polycam */}
        <div className="scan-export-stats glass">
          <div className="scan-export-stats-title">Overview</div>

          <StatRow label="Superficie total" value={`${floorArea.toFixed(1)} m²`} accent />
          <StatRow label="Área de paredes"  value={`${wallArea.toFixed(1)} m²`} />
          <StatRow label="Área de ventanas" value={`${windowArea.toFixed(2)} m²`} />
          <StatRow label="Volumen total"    value={`${totalVolume.toFixed(2)} m³`} />
          <StatRow label="Perímetro"        value={`${perimeter.toFixed(1)} m`} />
          <StatRow label="Altura media"     value={`${avgHeight.toFixed(2)} m`} />
          <div className="stat-divider" />
          <StatRow label="Nº paredes"  value={wallCount} />
          <StatRow label="Puertas"     value={doors.length} />
          <StatRow label="Ventanas"    value={windows.length} />
          <StatRow label="Aberturas"   value={openings.length} />
          {latitude  != null && <StatRow label="Latitud"  value={`${latitude.toFixed(6)} N`} />}
          {longitude != null && <StatRow label="Longitud" value={`${longitude.toFixed(6)} E`} />}
          {altitude  != null && <StatRow label="Altitud"  value={`${Math.round(altitude)} m`} />}
        </div>

        {/* Botones de exportación */}
        <div className="scan-export-actions">
          <ExportBtn icon="document" label="Informe PDF" sub="Plano + estadísticas" onClick={handleExportPDF} />
          {usdzExported && (
            <ExportBtn icon="model3d" label="Modelo USDZ" sub="3D para AR" onClick={handleExportUSDZ} accent />
          )}
        </div>

        {/* Acciones principales */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10, padding: '0 16px 8px' }}>
          <button className="btn btn-primary btn-lg" onClick={onAccept}>
            <Icon name="check" size={18} /> Usar estos datos para presupuesto
          </button>
          <button className="btn btn-ghost" onClick={onRescan}>
            <Icon name="scan" size={16} /> Re-escanear
          </button>
        </div>

        <div className="scan-export-footer safe-bottom">
          Los resultados son estimaciones del sensor LiDAR. mi-render · zerbitecni.com
        </div>
      </div>
    </div>
  )
}

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

function ExportBtn({ icon, label, sub, onClick, accent }) {
  return (
    <button className={`export-btn ${accent ? 'accent' : ''}`} onClick={onClick}>
      <div className="export-btn-icon">
        <Icon name={icon} size={22} />
      </div>
      <div>
        <div className="export-btn-label">{label}</div>
        <div className="export-btn-sub">{sub}</div>
      </div>
      <Icon name="download" size={18} style={{ marginLeft: 'auto', opacity: 0.6 }} />
    </button>
  )
}
