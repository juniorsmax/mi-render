import { useEffect, useRef } from 'react'
import { useHitTest } from '../hooks/useHitTest'
import { shoelace } from '../lib/shoelace'
import './ARCanvas.css'

/**
 * ARCanvas owns the WebGL canvas for the XR session base layer,
 * plus a 2D overlay canvas for drawing the reticle and tapped points.
 */
export function ARCanvas({ xrSession, onScanComplete }) {
  const glCanvasRef = useRef(null)
  const overlayRef = useRef(null)
  const glRef = useRef(null)
  const localRefSpaceRef = useRef(null)

  const { hitPose, tapCount, points } = useHitTest(xrSession, glCanvasRef)

  // Set up WebGL base layer once session is active
  useEffect(() => {
    if (!xrSession || !glCanvasRef.current) return

    const canvas = glCanvasRef.current
    const gl = canvas.getContext('webgl', { xrCompatible: true, alpha: true })
    if (!gl) return
    glRef.current = gl

    const layer = new XRWebGLLayer(xrSession, gl)
    xrSession.updateRenderState({ baseLayer: layer })

    xrSession.requestReferenceSpace('local').then((rs) => {
      localRefSpaceRef.current = rs
    })

    // AR frame loop for reticle drawing
    let rafId

    function drawFrame(time, frame) {
      rafId = xrSession.requestAnimationFrame(drawFrame)

      const overlay = overlayRef.current
      if (!overlay) return
      const ctx = overlay.getContext('2d')
      ctx.clearRect(0, 0, overlay.width, overlay.height)

      // Sync overlay size
      const vp = layer.getViewport(frame.getViewerPose(localRefSpaceRef.current)?.views[0])
      if (vp) {
        overlay.width = canvas.width = vp.width
        overlay.height = canvas.height = vp.height
      }

      // Clear GL (AR composites camera feed; we just need a transparent clear)
      gl.clearColor(0, 0, 0, 0)
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

      // Draw tapped points on overlay
      for (let i = 0; i < points.length; i++) {
        const pt = points[i]
        const screenPt = worldToScreen(pt, frame, localRefSpaceRef.current, vp, canvas)
        if (!screenPt) continue
        ctx.beginPath()
        ctx.arc(screenPt.x, screenPt.y, 8, 0, Math.PI * 2)
        ctx.fillStyle = 'rgba(108, 143, 255, 0.85)'
        ctx.fill()
        ctx.strokeStyle = '#fff'
        ctx.lineWidth = 2
        ctx.stroke()

        // Connect points
        if (i > 0) {
          const prev = worldToScreen(points[i - 1], frame, localRefSpaceRef.current, vp, canvas)
          if (prev) {
            ctx.beginPath()
            ctx.moveTo(prev.x, prev.y)
            ctx.lineTo(screenPt.x, screenPt.y)
            ctx.strokeStyle = 'rgba(108, 143, 255, 0.5)'
            ctx.lineWidth = 2
            ctx.setLineDash([6, 4])
            ctx.stroke()
            ctx.setLineDash([])
          }
        }
      }

      // Draw current hit reticle
      if (hitPose) {
        const pos = hitPose.transform.position
        const screenPt = worldToScreen({ x: pos.x, z: pos.z }, frame, localRefSpaceRef.current, vp, canvas)
        if (screenPt) {
          drawReticle(ctx, screenPt.x, screenPt.y)
        }
      }
    }

    rafId = xrSession.requestAnimationFrame(drawFrame)
    return () => { try { xrSession.cancelAnimationFrame(rafId) } catch {} }
  }, [xrSession, hitPose, points])

  function handleDone() {
    if (points.length < 3) return
    const area = shoelace(points)
    xrSession?.end()
    onScanComplete({ points: [...points], areaSqM: parseFloat(area.toFixed(2)) })
  }

  return (
    <div className="ar-canvas-root">
      <canvas ref={glCanvasRef} className="ar-gl-canvas" />
      <canvas ref={overlayRef} className="ar-overlay-canvas" />
      <div className="ar-hud">
        <div className="ar-hud-top">
          <span className="ar-tap-badge">
            {tapCount === 0 ? 'Toca las esquinas del suelo' : `${tapCount} punto${tapCount !== 1 ? 's' : ''} marcado${tapCount !== 1 ? 's' : ''}`}
          </span>
        </div>
        <div className="ar-hud-bottom">
          <button
            className="btn btn-ghost"
            onClick={() => xrSession?.end()}
          >
            Cancelar
          </button>
          <button
            className="btn btn-primary"
            onClick={handleDone}
            disabled={tapCount < 3}
          >
            Listo ({tapCount} puntos)
          </button>
        </div>
      </div>
    </div>
  )
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function worldToScreen(xzPoint, frame, refSpace, viewport, canvas) {
  if (!frame || !refSpace || !viewport) return null
  const viewerPose = frame.getViewerPose(refSpace)
  if (!viewerPose || viewerPose.views.length === 0) return null
  const view = viewerPose.views[0]

  const proj = view.projectionMatrix
  const viewMat = view.transform.inverse.matrix

  // World point (y=0 floor)
  const wx = xzPoint.x, wy = 0, wz = xzPoint.z, ww = 1

  // View transform
  const vx = viewMat[0]*wx + viewMat[4]*wy + viewMat[8]*wz  + viewMat[12]*ww
  const vy = viewMat[1]*wx + viewMat[5]*wy + viewMat[9]*wz  + viewMat[13]*ww
  const vz = viewMat[2]*wx + viewMat[6]*wy + viewMat[10]*wz + viewMat[14]*ww
  const vw = viewMat[3]*wx + viewMat[7]*wy + viewMat[11]*wz + viewMat[15]*ww

  // Projection
  const cx = proj[0]*vx + proj[4]*vy + proj[8]*vz  + proj[12]*vw
  const cy = proj[1]*vx + proj[5]*vy + proj[9]*vz  + proj[13]*vw
  const cw = proj[3]*vx + proj[7]*vy + proj[11]*vz + proj[15]*vw

  if (Math.abs(cw) < 0.0001) return null
  const ndcX = cx / cw
  const ndcY = cy / cw

  // Behind camera
  if (ndcX < -1.5 || ndcX > 1.5 || ndcY < -1.5 || ndcY > 1.5) return null

  return {
    x: ((ndcX + 1) / 2) * canvas.width,
    y: ((1 - ndcY) / 2) * canvas.height,
  }
}

function drawReticle(ctx, x, y) {
  const r = 18
  ctx.save()
  ctx.translate(x, y)

  // Outer ring
  ctx.beginPath()
  ctx.arc(0, 0, r, 0, Math.PI * 2)
  ctx.strokeStyle = 'rgba(108, 143, 255, 0.9)'
  ctx.lineWidth = 2
  ctx.stroke()

  // Inner dot
  ctx.beginPath()
  ctx.arc(0, 0, 4, 0, Math.PI * 2)
  ctx.fillStyle = 'rgba(108, 143, 255, 0.9)'
  ctx.fill()

  // Cross-hairs
  ctx.strokeStyle = 'rgba(108, 143, 255, 0.6)'
  ctx.lineWidth = 1
  const gap = 6, len = 10
  ctx.beginPath()
  ctx.moveTo(-r - len, 0); ctx.lineTo(-gap, 0)
  ctx.moveTo(gap, 0); ctx.lineTo(r + len, 0)
  ctx.moveTo(0, -r - len); ctx.lineTo(0, -gap)
  ctx.moveTo(0, gap); ctx.lineTo(0, r + len)
  ctx.stroke()

  ctx.restore()
}
