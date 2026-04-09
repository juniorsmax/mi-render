import { useEffect, useRef, useMemo, useState, useCallback } from 'react'

/**
 * FloorPlan — Renderiza plano 2D desde datos RoomPlan
 * Editable: click en pared para seleccionar y ver/editar dimensiones
 *
 * Props:
 *   walls       — [{posX, posZ, angle, width, height, confidence}]
 *   doors       — [{posX, posZ, angle, width, isOpen}]
 *   windows     — [{posX, posZ, angle, width}]
 *   openings    — [{posX, posZ, angle, width}]
 *   size        — tamaño canvas px (default 320)
 *   padding     — padding interior (default 24)
 *   editable    — habilitar selección y edición (default false)
 *   onWallChange — callback(index, updatedWall) al editar dimensión
 */
export function FloorPlan({
  walls = [], doors = [], windows = [], openings = [],
  size = 320, padding = 24,
  editable = false, onWallChange
}) {
  const canvasRef  = useRef(null)
  const [selectedWall, setSelectedWall] = useState(null)
  const [editValue,    setEditValue]    = useState('')
  const [editField,    setEditField]    = useState('width') // 'width' | 'height'

  // Calcula bounding box
  const bounds = useMemo(() => {
    const pts = []
    ;[...walls, ...doors, ...windows, ...openings].forEach(({ posX = 0, posZ = 0, angle = 0, width = 0 }) => {
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      pts.push({ x: posX + cos * hw, z: posZ + sin * hw })
      pts.push({ x: posX - cos * hw, z: posZ - sin * hw })
    })
    if (pts.length === 0) return { minX: -3, maxX: 3, minZ: -3, maxZ: 3 }
    return {
      minX: Math.min(...pts.map(p => p.x)),
      maxX: Math.max(...pts.map(p => p.x)),
      minZ: Math.min(...pts.map(p => p.z)),
      maxZ: Math.max(...pts.map(p => p.z)),
    }
  }, [walls, doors, windows, openings])

  // Función de proyección metros→píxeles (reutilizada en hit-test)
  const getTransform = useCallback(() => {
    const rangeX  = (bounds.maxX - bounds.minX) || 1
    const rangeZ  = (bounds.maxZ - bounds.minZ) || 1
    const drawArea = size - padding * 2
    const s = Math.min(drawArea / rangeX, drawArea / rangeZ) * 0.88
    const offX = padding + (drawArea - rangeX * s) / 2
    const offZ = padding + (drawArea - rangeZ * s) / 2
    return {
      s, offX, offZ,
      toScreen: (x, z) => ({
        sx: offX + (x - bounds.minX) * s,
        sy: offZ + (z - bounds.minZ) * s,
      })
    }
  }, [bounds, size, padding])

  // Hit-test: devuelve índice de la pared más cercana al click
  const hitTestWall = useCallback((canvasX, canvasY) => {
    const { toScreen } = getTransform()
    let bestIdx = -1, bestDist = 14 // px threshold

    walls.forEach((wall, i) => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = wall
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      // Distancia punto-segmento
      const dx = p2.sx - p1.sx, dy = p2.sy - p1.sy
      const len2 = dx * dx + dy * dy
      if (len2 === 0) return
      const t = Math.max(0, Math.min(1, ((canvasX - p1.sx) * dx + (canvasY - p1.sy) * dy) / len2))
      const px = p1.sx + t * dx - canvasX
      const py = p1.sy + t * dy - canvasY
      const dist = Math.sqrt(px * px + py * py)
      if (dist < bestDist) { bestDist = dist; bestIdx = i }
    })

    return bestIdx
  }, [walls, getTransform])

  // Click sobre canvas
  function handleCanvasClick(e) {
    if (!editable) return
    const canvas = canvasRef.current
    if (!canvas) return
    const rect = canvas.getBoundingClientRect()
    const dpr  = window.devicePixelRatio || 1
    const cx = (e.clientX - rect.left) * (canvas.width  / rect.width  / dpr)
    const cy = (e.clientY - rect.top)  * (canvas.height / rect.height / dpr)

    const idx = hitTestWall(cx, cy)
    if (idx === -1) { setSelectedWall(null); return }
    setSelectedWall(idx)
    setEditValue((walls[idx].width ?? 0).toFixed(2))
    setEditField('width')
  }

  // Confirmar edición de dimensión
  function handleEditConfirm() {
    if (selectedWall === null || !onWallChange) return
    const val = parseFloat(editValue)
    if (isNaN(val) || val <= 0) return
    const updated = { ...walls[selectedWall], [editField]: val }
    onWallChange(selectedWall, updated)
    setSelectedWall(null)
  }

  // ── Renderizado canvas ──────────────────────────────────────────────────────
  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    const dpr = window.devicePixelRatio || 1
    canvas.width  = size * dpr
    canvas.height = size * dpr
    canvas.style.width  = size + 'px'
    canvas.style.height = size + 'px'
    ctx.scale(dpr, dpr)
    ctx.clearRect(0, 0, size, size)

    // Fondo
    ctx.fillStyle = '#0c0a08'
    ctx.fillRect(0, 0, size, size)

    // Grid puntos
    ctx.fillStyle = 'rgba(240,165,0,0.1)'
    for (let x = 20; x < size - 20; x += 20)
      for (let z = 20; z < size - 20; z += 20) {
        ctx.beginPath(); ctx.arc(x, z, 1, 0, Math.PI * 2); ctx.fill()
      }

    const { s, toScreen } = getTransform()

    // Área del suelo
    if (walls.length >= 2) {
      ctx.save()
      const pts = walls.map(w => toScreen(w.posX ?? 0, w.posZ ?? 0))
      const cx2 = pts.reduce((a, p) => a + p.sx, 0) / pts.length
      const cy2 = pts.reduce((a, p) => a + p.sy, 0) / pts.length
      pts.sort((a, b) => Math.atan2(a.sy - cy2, a.sx - cx2) - Math.atan2(b.sy - cy2, b.sx - cx2))
      ctx.beginPath()
      ctx.moveTo(pts[0].sx, pts[0].sy)
      pts.slice(1).forEach(p => ctx.lineTo(p.sx, p.sy))
      ctx.closePath()
      ctx.fillStyle = 'rgba(240,165,0,0.04)'
      ctx.fill()
      ctx.restore()
    }

    // ── Paredes ──────────────────────────────────────────────────────────────
    walls.forEach((wall, i) => {
      const { posX = 0, posZ = 0, angle = 0, width = 0, height = 0, confidence = 'high' } = wall
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      const isSelected = selectedWall === i
      const alpha = confidence === 'high' ? 1 : confidence === 'medium' ? 0.75 : 0.5
      const lw    = isSelected ? 6 : (confidence === 'high' ? 4.5 : 3.5)
      const color = isSelected ? '#2dd4bf' : `rgba(240,165,0,${alpha})`

      ctx.save()
      ctx.shadowColor = isSelected ? 'rgba(45,212,191,0.6)' : `rgba(240,165,0,${0.45 * alpha})`
      ctx.shadowBlur  = isSelected ? 14 : 10
      ctx.strokeStyle = color
      ctx.lineWidth   = lw
      ctx.lineCap     = 'square'
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()
      ctx.restore()

      // Cota de dimensión sobre la pared seleccionada
      if (isSelected && editable) {
        const mid = toScreen(posX, posZ)
        const labelW = width.toFixed(2) + ' m'
        const labelH = height > 0 ? `h: ${height.toFixed(2)} m` : ''
        ctx.save()
        ctx.font = 'bold 10px -apple-system, sans-serif'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'bottom'
        ctx.fillStyle = '#2dd4bf'
        ctx.shadowColor = 'rgba(0,0,0,0.8)'
        ctx.shadowBlur = 3
        ctx.fillText(labelW, mid.sx, mid.sy - 8)
        if (labelH) ctx.fillText(labelH, mid.sx, mid.sy - 20)
        ctx.restore()
      } else if (editable && width > 0) {
        // Mostrar dimensión pequeña en todas las paredes cuando editable
        const mid = toScreen(posX, posZ)
        ctx.save()
        ctx.font = '9px -apple-system, sans-serif'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'bottom'
        ctx.fillStyle = 'rgba(240,165,0,0.5)'
        ctx.fillText(width.toFixed(1) + 'm', mid.sx, mid.sy - 6)
        ctx.restore()
      }
    })

    // ── Ventanas ─────────────────────────────────────────────────────────────
    windows.forEach(win => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = win
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)
      ctx.save()
      ctx.strokeStyle = '#0c0a08'; ctx.lineWidth = 7; ctx.lineCap = 'butt'
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()
      ctx.shadowColor = 'rgba(96,165,250,0.5)'; ctx.shadowBlur = 6
      ctx.strokeStyle = '#60a5fa'; ctx.lineWidth = 2
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()
      const mid  = toScreen(posX, posZ)
      const perp = { x: -sin * 5, y: cos * 5 }
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.moveTo(mid.sx - perp.x, mid.sy - perp.y)
      ctx.lineTo(mid.sx + perp.x, mid.sy + perp.y)
      ctx.stroke()
      ctx.restore()
    })

    // ── Puertas ──────────────────────────────────────────────────────────────
    doors.forEach(door => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = door
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)
      ctx.save()
      ctx.strokeStyle = '#0c0a08'; ctx.lineWidth = 7
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()
      const doorLen  = Math.sqrt((p2.sx - p1.sx) ** 2 + (p2.sy - p1.sy) ** 2)
      const arcAngle = Math.atan2(p2.sy - p1.sy, p2.sx - p1.sx)
      ctx.shadowColor = 'rgba(45,212,191,0.4)'; ctx.shadowBlur = 6
      ctx.strokeStyle = '#2dd4bf'; ctx.lineWidth = 1.2; ctx.setLineDash([3, 2])
      ctx.beginPath(); ctx.arc(p1.sx, p1.sy, doorLen, arcAngle, arcAngle + Math.PI / 2); ctx.stroke()
      ctx.setLineDash([])
      ctx.lineWidth = 1.8
      ctx.beginPath()
      ctx.moveTo(p1.sx, p1.sy)
      ctx.lineTo(p1.sx + Math.cos(arcAngle + Math.PI / 2) * doorLen, p1.sy + Math.sin(arcAngle + Math.PI / 2) * doorLen)
      ctx.stroke()
      ctx.restore()
    })

    // ── Aberturas ─────────────────────────────────────────────────────────────
    openings.forEach(op => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = op
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)
      ctx.save()
      ctx.strokeStyle = '#0c0a08'; ctx.lineWidth = 7
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()
      ctx.restore()
    })

    // ── Escala visual ─────────────────────────────────────────────────────────
    const scaleBarPx = 1 * s
    const sbX = padding, sbY = size - padding + 4
    if (scaleBarPx > 8) {
      ctx.save()
      ctx.strokeStyle = 'rgba(240,165,0,0.55)'; ctx.lineWidth = 1.5; ctx.lineCap = 'round'
      ctx.beginPath(); ctx.moveTo(sbX, sbY); ctx.lineTo(sbX + scaleBarPx, sbY); ctx.stroke()
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(sbX, sbY - 3); ctx.lineTo(sbX, sbY + 3); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(sbX + scaleBarPx, sbY - 3); ctx.lineTo(sbX + scaleBarPx, sbY + 3); ctx.stroke()
      ctx.fillStyle = 'rgba(240,165,0,0.6)'
      ctx.font = '500 9px -apple-system, sans-serif'
      ctx.textAlign = 'left'; ctx.textBaseline = 'top'
      ctx.fillText('1 m', sbX, sbY + 5)
      ctx.restore()
    }

    // ── Brújula N ─────────────────────────────────────────────────────────────
    const ncx = size - 22, ncy = size - 22, nr = 13
    ctx.save()
    ctx.fillStyle = 'rgba(240,165,0,0.08)'; ctx.beginPath(); ctx.arc(ncx, ncy, nr, 0, Math.PI * 2); ctx.fill()
    ctx.strokeStyle = 'rgba(240,165,0,0.3)'; ctx.lineWidth = 1; ctx.stroke()
    ctx.fillStyle = 'rgba(240,165,0,0.9)'
    ctx.beginPath(); ctx.moveTo(ncx, ncy - nr + 3); ctx.lineTo(ncx - 4, ncy + 2); ctx.lineTo(ncx, ncy - 1); ctx.closePath(); ctx.fill()
    ctx.fillStyle = 'rgba(100,90,80,0.7)'
    ctx.beginPath(); ctx.moveTo(ncx, ncy + nr - 3); ctx.lineTo(ncx + 4, ncy - 2); ctx.lineTo(ncx, ncy + 1); ctx.closePath(); ctx.fill()
    ctx.fillStyle = 'rgba(240,165,0,0.85)'; ctx.font = 'bold 8px -apple-system, sans-serif'
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
    ctx.fillText('N', ncx, ncy - nr - 6)
    ctx.restore()

    // Hint de edición
    if (editable && walls.length > 0 && selectedWall === null) {
      ctx.save()
      ctx.fillStyle = 'rgba(240,165,0,0.4)'
      ctx.font = '9px -apple-system, sans-serif'
      ctx.textAlign = 'center'; ctx.textBaseline = 'top'
      ctx.fillText('Toca una pared para editar', size / 2, padding - 12)
      ctx.restore()
    }

  }, [walls, doors, windows, openings, bounds, size, padding, selectedWall, editable, getTransform])

  return (
    <div style={{ position: 'relative', display: 'inline-block' }}>
      <canvas
        ref={canvasRef}
        onClick={handleCanvasClick}
        style={{
          borderRadius: 10,
          display: 'block',
          maxWidth: '100%',
          background: '#0c0a08',
          cursor: editable ? 'pointer' : 'default',
        }}
      />

      {/* Panel de edición de pared seleccionada */}
      {editable && selectedWall !== null && walls[selectedWall] && (
        <div style={{
          position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
          background: 'rgba(12,10,8,0.95)', border: '1px solid rgba(45,212,191,0.4)',
          borderRadius: 10, padding: '10px 14px', minWidth: 200,
          display: 'flex', flexDirection: 'column', gap: 8,
          backdropFilter: 'blur(8px)',
        }}>
          <div style={{ fontSize: 11, color: '#2dd4bf', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
            Pared {selectedWall + 1}
          </div>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <select
              value={editField}
              onChange={e => {
                setEditField(e.target.value)
                const w = walls[selectedWall]
                setEditValue((e.target.value === 'width' ? w.width : w.height ?? 0).toFixed(2))
              }}
              style={{ background: '#1a1814', color: '#e0d5c0', border: '1px solid rgba(240,165,0,0.2)', borderRadius: 6, padding: '4px 6px', fontSize: 12 }}
            >
              <option value="width">Ancho (m)</option>
              <option value="height">Alto (m)</option>
            </select>
            <input
              type="number"
              value={editValue}
              min="0.01" step="0.01"
              onChange={e => setEditValue(e.target.value)}
              style={{ width: 70, background: '#1a1814', color: '#f0a500', border: '1px solid rgba(240,165,0,0.3)', borderRadius: 6, padding: '4px 8px', fontSize: 13, fontFamily: 'monospace' }}
            />
            <button
              onClick={handleEditConfirm}
              style={{ background: 'rgba(45,212,191,0.15)', color: '#2dd4bf', border: '1px solid rgba(45,212,191,0.3)', borderRadius: 6, padding: '4px 10px', fontSize: 12, cursor: 'pointer' }}
            >
              ✓
            </button>
            <button
              onClick={() => setSelectedWall(null)}
              style={{ background: 'transparent', color: 'rgba(240,165,0,0.4)', border: 'none', fontSize: 16, cursor: 'pointer', padding: '0 4px' }}
            >
              ×
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
