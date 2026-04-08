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

    // Fondo
    ctx.fillStyle = '#f8f7f5'
    ctx.fillRect(0, 0, size, size)

    // Escala: metros → píxeles
    const rangeX = (bounds.maxX - bounds.minX) || 1
    const rangeZ = (bounds.maxZ - bounds.minZ) || 1
    const drawArea = size - padding * 2
    const scale = Math.min(drawArea / rangeX, drawArea / drawArea) * 0.9
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

    // ── Área del suelo (relleno) ──────────────────────────────────────────────
    if (walls.length >= 2) {
      ctx.save()
      ctx.beginPath()
      const pts = walls.map(w => {
        const { sx, sy } = toScreen(w.posX ?? 0, w.posZ ?? 0)
        return { sx, sy }
      })
      // Ordenar puntos por ángulo para formar polígono
      const cx = pts.reduce((a, p) => a + p.sx, 0) / pts.length
      const cy = pts.reduce((a, p) => a + p.sy, 0) / pts.length
      pts.sort((a, b) => Math.atan2(a.sy - cy, a.sx - cx) - Math.atan2(b.sy - cy, b.sx - cx))
      ctx.moveTo(pts[0].sx, pts[0].sy)
      pts.slice(1).forEach(p => ctx.lineTo(p.sx, p.sy))
      ctx.closePath()
      ctx.fillStyle = 'rgba(220,235,220,0.6)'
      ctx.fill()
      ctx.restore()
    }

    // ── Paredes ───────────────────────────────────────────────────────────────
    walls.forEach(wall => {
      const { posX = 0, posZ = 0, angle = 0, width = 0, confidence = 'high' } = wall
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      ctx.save()
      ctx.strokeStyle = confidence === 'high' ? '#1a1a1a' : confidence === 'medium' ? '#555' : '#999'
      ctx.lineWidth   = confidence === 'high' ? 5 : 4
      ctx.lineCap     = 'square'
      ctx.beginPath()
      ctx.moveTo(p1.sx, p1.sy)
      ctx.lineTo(p2.sx, p2.sy)
      ctx.stroke()
      ctx.restore()
    })

    // ── Ventanas ──────────────────────────────────────────────────────────────
    windows.forEach(win => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = win
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      ctx.save()
      // Rompe la pared y dibuja ventana
      ctx.strokeStyle = '#7ab8f5'
      ctx.lineWidth   = 5
      ctx.lineCap     = 'butt'

      // Fondo blanco sobre la pared
      ctx.globalCompositeOperation = 'source-over'
      ctx.strokeStyle = '#f8f7f5'
      ctx.lineWidth   = 6
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()

      // Líneas de ventana
      ctx.strokeStyle = '#5599dd'
      ctx.lineWidth   = 1.5
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()

      // Centro marcado
      const mid = toScreen(posX, posZ)
      ctx.strokeStyle = '#5599dd'
      ctx.lineWidth   = 3
      const perp = { x: -sin * 4, y: cos * 4 }
      ctx.beginPath()
      ctx.moveTo(mid.sx - perp.x, mid.sy - perp.y)
      ctx.lineTo(mid.sx + perp.x, mid.sy + perp.y)
      ctx.stroke()
      ctx.restore()
    })

    // ── Puertas ───────────────────────────────────────────────────────────────
    doors.forEach(door => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = door
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)

      ctx.save()
      // Fondo blanco sobre la pared
      ctx.strokeStyle = '#f8f7f5'
      ctx.lineWidth = 6
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()

      // Arco de apertura de puerta
      const doorLen = Math.sqrt((p2.sx - p1.sx) ** 2 + (p2.sy - p1.sy) ** 2)
      const arcAngle = Math.atan2(p2.sy - p1.sy, p2.sx - p1.sx)
      ctx.strokeStyle = '#cc6600'
      ctx.lineWidth = 1
      ctx.setLineDash([3, 2])
      ctx.beginPath()
      ctx.arc(p1.sx, p1.sy, doorLen, arcAngle, arcAngle + Math.PI / 2)
      ctx.stroke()
      ctx.setLineDash([])

      // Línea de hoja de puerta
      ctx.strokeStyle = '#cc6600'
      ctx.lineWidth = 1.5
      ctx.beginPath()
      ctx.moveTo(p1.sx, p1.sy)
      ctx.lineTo(
        p1.sx + Math.cos(arcAngle + Math.PI / 2) * doorLen,
        p1.sy + Math.sin(arcAngle + Math.PI / 2) * doorLen
      )
      ctx.stroke()
      ctx.restore()
    })

    // ── Aberturas (openings) ──────────────────────────────────────────────────
    openings.forEach(op => {
      const { posX = 0, posZ = 0, angle = 0, width = 0 } = op
      const hw = width / 2
      const cos = Math.cos(angle), sin = Math.sin(angle)
      const p1 = toScreen(posX + cos * hw, posZ + sin * hw)
      const p2 = toScreen(posX - cos * hw, posZ - sin * hw)
      ctx.save()
      ctx.strokeStyle = '#f8f7f5'
      ctx.lineWidth = 7
      ctx.beginPath(); ctx.moveTo(p1.sx, p1.sy); ctx.lineTo(p2.sx, p2.sy); ctx.stroke()
      ctx.restore()
    })

    // ── Brújula (N) ───────────────────────────────────────────────────────────
    const cx = size - 28, cy = size - 28, r = 12
    ctx.save()
    ctx.fillStyle = '#1a1a1a'
    ctx.font = 'bold 9px -apple-system,sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.beginPath(); ctx.arc(cx, cy - r - 6, 7, 0, Math.PI * 2)
    ctx.fillStyle = 'rgba(26,26,26,0.15)'; ctx.fill()
    ctx.fillStyle = '#1a1a1a'; ctx.fillText('N', cx, cy - r - 6)
    ctx.beginPath(); ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r)
    ctx.strokeStyle = '#1a1a1a'; ctx.lineWidth = 1.5; ctx.stroke()
    ctx.restore()

  }, [walls, doors, windows, openings, bounds, size, padding])

  return (
    <canvas
      ref={canvasRef}
      style={{
        borderRadius: 8,
        display: 'block',
        maxWidth: '100%',
        background: '#f8f7f5',
      }}
    />
  )
}
