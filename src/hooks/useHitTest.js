import { useEffect, useRef, useState } from 'react'

/**
 * Manages the WebXR hit-test loop using transient input (screen taps).
 * Each tap auto-generates hit results via requestHitTestSourceForTransientInput.
 *
 * @param {XRSession|null} xrSession
 * @param {React.RefObject<HTMLCanvasElement>} glRef
 * @returns {{ hitPose: XRPose|null, lastTapPose: XRPose|null, tapCount: number }}
 */
export function useHitTest(xrSession, glRef) {
  const [hitPose, setHitPose] = useState(null)
  const [lastTapPose, setLastTapPose] = useState(null)
  const [tapCount, setTapCount] = useState(0)

  const hitTestSourceRef = useRef(null)
  const refSpaceRef = useRef(null)
  const rafIdRef = useRef(null)
  const pointsRef = useRef([])

  useEffect(() => {
    if (!xrSession) return

    let cancelled = false

    async function setup() {
      try {
        const refSpace = await xrSession.requestReferenceSpace('local')
        refSpaceRef.current = refSpace

        const hitSource = await xrSession.requestHitTestSourceForTransientInput({
          profile: 'generic-touchscreen',
        })
        hitTestSourceRef.current = hitSource
      } catch (err) {
        console.warn('[useHitTest] setup error:', err)
        return
      }

      if (cancelled) return

      function onXRFrame(time, frame) {
        if (cancelled) return

        rafIdRef.current = xrSession.requestAnimationFrame(onXRFrame)

        if (!hitTestSourceRef.current || !refSpaceRef.current) return

        const results = frame.getHitTestResultsForTransientInput(hitTestSourceRef.current)

        if (results.length > 0 && results[0].results.length > 0) {
          const pose = results[0].results[0].getPose(refSpaceRef.current)
          if (pose) {
            setHitPose(pose)
            // Each tap fires exactly once per touchstart — record it
            const pos = pose.transform.position
            pointsRef.current.push({ x: pos.x, z: pos.z })
            setLastTapPose(pose)
            setTapCount((c) => c + 1)
          }
        }
      }

      rafIdRef.current = xrSession.requestAnimationFrame(onXRFrame)
    }

    setup()

    return () => {
      cancelled = true
      if (hitTestSourceRef.current) {
        try { hitTestSourceRef.current.cancel() } catch {}
        hitTestSourceRef.current = null
      }
      setHitPose(null)
      setLastTapPose(null)
      setTapCount(0)
      pointsRef.current = []
    }
  }, [xrSession])

  return {
    hitPose,
    lastTapPose,
    tapCount,
    points: pointsRef.current,
  }
}
