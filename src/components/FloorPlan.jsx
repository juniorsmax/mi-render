import { useEffect, useRef, useMemo } from 'react'

/**
 * FloorPlan — Renderiza plano 2D desde datos RoomPlan
 * Agente: Luna (UI) + Ares (datos)
 *
 * Props:
 *   walls    — [{posX, posZ, angle, width, height, confidence}]
 *   doors    — [{posX, posZ, angle, width, isOpen}]
 *   windows  — [{posX, posZ, angle, width}]
 *   openings — [{posX, posZ, angle, width}]
 *   size     — tamaño del canvas en px (default 320)
 *   padding  — padding interior (default 24)
 */
export function FloorPlan({ walls = [], doors = [], windows = [], openings = [], size = 320, padding = 24 }) {
  const canvasRef = useRef(null)

  // Calcula bounding box de todas las paredes
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

    // ── Fondo oscuro con grid de puntos ────────────────────────────────────────
    ctx.fillStyle = '#0c0a08'
    ctx.fillRect(0, 0, size, size)

    // Grid de puntos sutil
    const gridSpacing = 20
    ctx.fillStyle = 'rgba(240,165,0,0.1)'
    for (let x = gridSpacing; x < size - gridSpacing; x += gridSpacing) {
      for (let z = gridSpacing; z < size - gridSpacing; z += gridSpacing) {
        ctx.beginPath()
        ctx.arc(x, z, 1, 0, Math.PI * 2)
        ctx.fill()
      }
    }

    // Escala: metros → píxeles
    const rangeX = (bounds.maxX - bounds.minX) || 1
    const rangeZ = (bounds.maxZ - bounds.minZ) || 1
    const drawArea = size - padding * 2
    const scaleX = drawArea / rangeX
    const scaleZ = drawArea / rangeZ
    const s = Math.min(scaleX, scaleZ) * 0.88

    const offX = padding + (drawArea - rangeX * s) / 2
    const offZ = padding + (drawArea - rangeZ * s) / 2

    function toScreen(x, z) {
      return {
        sx: offX + (x - bounds.minX) * s,
        sy: offZ + (z - bounds.minZ) * s,
      }
    }

    // ── Área del suelo (relleno sutil) ─────────────────────────────────────────
    if (walls.length >= 2) {
      ctx.save()
      ctx.beginPath()
      const pts = walls.map(w => {
        const { sx, sy } = toScreen(w.posX ?? 0, w.posZ ?? 0)
        return { sx, sy }
      })
      const cx = pts.reduce((a, p) => a + p.sx, 0) / pts.length
      const cy = pts.reduce((a, p) => a + p.sy, 0) / pts.length
      pts.sort((a, b) => Math.atan2(a.sy - cy, a.sx - cx) - Math.atan2(b.sy - cy, b.sx - cx))
      ctx.moveTo(pts[0].sx, pts[0].sy)
      pts.slice(1).forEach(p => ctx.lineTo(p.sx, p.sy))
      ctx.closePath()
      ctx.fillStyle = 'rgba(240,165,0,0.04)'
      ctx.fill()
      ctx.restore()
    }

    // ── Paredes — amber brillante con glow ────────────────────────────────────
    walls.forEach(wall => {
      const { posX = 0, posZ = 0, angle = 0, width = 0, confidence = 'high' } = wall
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      const alpha = confidence === 'high' ? 1 : confidence === 'medium' ? 0.75 : 0.5
      const lw    = confidence === 'high' ? 4.5 : confidence === 'medium' ? 3.5 : 3

      ctx.save()
      // Glow exterior
      ctx.shadowColor = `rgba(240,165,0,${0.45 * alpha})`
      ctx.shadowBlur  = 10
      ctx.strokeStyle = `rgba(240,165,0,${alpha})`
      ctx.lineWidth   = lw
      ctx.lineCap     = 'square'
      ctx.beginPath()
      ctx.moveTo(p1.sx, p1.sy)
      ctx.lineTo(p2.sx, p2.sy)
      ctx.stroke()
      ctx.restore()
    })

    // ── Ventanas — azul suave ─────────────────────────────────────────────────
    windows.forEach(win => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = win
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      ctx.save()
      // Rompe la pared con fondo oscuro
      ctx.strokeStyle = '#0c0a08'
      ctx.lineWidth   = 7
      ctx.lineCap     = 'butt'
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()

      // Línea principal de ventana
      ctx.shadowColor = 'rgba(96,165,250,0.5)'
      ctx.shadowBlur  = 6
      ctx.strokeStyle = '#60a5fa'
      ctx.lineWidth   = 2
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()

      // Marca central perpendicular
      const mid  = toScreen(posX, posZ)
      const perp = { x: -sin * 5, y: cos * 5 }
      ctx.strokeStyle = '#60a5fa'
      ctx.lineWidth   = 1.5
      ctx.beginPath()
      ctx.moveTo(mid.sx - perp.x, mid.sy - perp.y)
      ctx.lineTo(mid.sx + perp.x, mid.sy + perp.y)
      ctx.stroke()
      ctx.restore()
    })

    // ── Puertas — teal ────────────────────────────────────────────────────────
    doors.forEach(door => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = door
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      ctx.save()
      // Rompe la pared
      ctx.strokeStyle = '#0c0a08'
      ctx.lineWidth = 7
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()

      // Arco de apertura
      const doorLen  = Math.sqrt((p2.sx - p1.sx) ** 2 + (p2.sy - p1.sy) ** 2)
      const arcAngle = Math.atan2(p2.sy - p1.sy, p2.sx - p1.sx)

      ctx.shadowColor = 'rgba(45,212,191,0.4)'
      ctx.shadowBlur  = 6
      ctx.strokeStyle = '#2dd4bf'
      ctx.lineWidth   = 1.2
      ctx.setLineDash([3, 2])
      ctx.beginPath()
      ctx.arc(p1.sx, p1.sy, doorLen, arcAngle, arcAngle + Math.PI / 2)
      ctx.stroke()
      ctx.setLineDash([])

      // Hoja de puerta
      ctx.strokeStyle = '#2dd4bf'
      ctx.lineWidth   = 1.8
      ctx.beginPath()
      ctx.moveTo(p1.sx, p1.sy)
      ctx.lineTo(
        p1.sx + Math.cos(arcAngle + Math.PI / 2) * doorLen,
        p1.sy + Math.sin(arcAngle + Math.PI / 2) * doorLen
      )
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
      ctx.strokeStyle = '#0c0a08'
      ctx.lineWidth = 7
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()
      ctx.restore()
    })

    // ── Escala visual (línea + metros) ────────────────────────────────────────
    const scaleBarMeters = 1  // 1 metro
    const scaleBarPx = scaleBarMeters * s
    const sbX = padding, sbY = size - padding + 4
    if (scaleBarPx > 8) {
      ctx.save()
      ctx.strokeStyle = 'rgba(240,165,0,0.55)'
      ctx.lineWidth = 1.5
      ctx.lineCap = 'round'
      // Línea horizontal
      ctx.beginPath(); ctx.moveTo(sbX, sbY); ctx.lineTo(sbX + scaleBarPx, sbY); ctx.stroke()
      // Ticks extremos
      ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(sbX, sbY - 3); ctx.lineTo(sbX, sbY + 3); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(sbX + scaleBarPx, sbY - 3); ctx.lineTo(sbX + scaleBarPx, sbY + 3); ctx.stroke()
      // Texto
      ctx.fillStyle = 'rgba(240,165,0,0.6)'
      ctx.font = '500 9px -apple-system, sans-serif'
      ctx.textAlign = 'left'
      ctx.textBaseline = 'top'
      ctx.fillText(`${scaleBarMeters} m`, sbX, sbY + 5)
      ctx.restore()
    }

    // ── Brújula N ─────────────────────────────────────────────────────────────
    const ncx = size - 22, ncy = size - 22, nr = 13
    ctx.save()
    // Fondo del círculo
    ctx.fillStyle = 'rgba(240,165,0,0.08)'
    ctx.beginPath(); ctx.arc(ncx, ncy, nr, 0, Math.PI * 2); ctx.fill()
    // Borde
    ctx.strokeStyle = 'rgba(240,165,0,0.3)'
    ctx.lineWidth = 1
    ctx.stroke()
    // Flecha Norte (arriba = amber)
    ctx.fillStyle = 'rgba(240,165,0,0.9)'
    ctx.beginPath()
    ctx.moveTo(ncx, ncy - nr + 3)
    ctx.lineTo(ncx - 4, ncy + 2)
    ctx.lineTo(ncx, ncy - 1)
    ctx.closePath()
    ctx.fill()
    // Flecha Sur (abajo = muted)
    ctx.fillStyle = 'rgba(100,90,80,0.7)'
    ctx.beginPath()
    ctx.moveTo(ncx, ncy + nr - 3)
    ctx.lineTo(ncx + 4, ncy - 2)
    ctx.lineTo(ncx, ncy + 1)
    ctx.closePath()
    ctx.fill()
    // Letra N
    ctx.fillStyle = 'rgba(240,165,0,0.85)'
    ctx.font = 'bold 8px -apple-system, sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText('N', ncx, ncy - nr - 6)
    ctx.restore()

  }, [walls, doors, windows, openings, bounds, size, padding])

  return (
    <canvas
      ref={canvasRef}
      style={{
        borderRadius: 10,
        display: 'block',
        maxWidth: '100%',
        background: '#0c0a08',
        position: 'relative',
        zIndex: 1,
      }}
    />
  )
}
