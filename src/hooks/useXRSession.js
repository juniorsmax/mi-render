import { useState, useCallback, useRef, useEffect } from 'react'

/**
 * Manages the WebXR immersive-ar session lifecycle.
 *
 * SAFARI REQUIREMENT: requestSession() must be called synchronously inside
 * a user-gesture handler. Any await before requestSession breaks the gesture
 * chain and Safari will reject the session.
 *
 * Strategy:
 *  - isSessionSupported() check runs in useEffect (no gesture needed)
 *  - startSession() skips that check and calls requestSession() immediately
 */
export function useXRSession() {
  // Pre-check state (runs on mount, no gesture needed)
  // 'checking' | 'supported' | 'unsupported' | 'no-xr' | 'no-https'
  const [arCheckState, setArCheckState] = useState('checking')

  // Session state
  const [xrState, setXrState] = useState('idle')
  // 'idle' | 'requesting' | 'active' | 'ended' | 'error'
  const [errorMessage, setErrorMessage] = useState(null)

  // Use both ref (for sync access) and state (for reactivity)
  const [xrSession, setXrSession] = useState(null)
  const sessionRef = useRef(null)

  // ── Pre-check WebXR availability (no gesture required) ────────────
  useEffect(() => {
    async function check() {
      // HTTPS / secure context required
      if (!window.isSecureContext) {
        setArCheckState('no-https')
        return
      }
      // navigator.xr must exist
      if (!navigator.xr) {
        setArCheckState('no-xr')
        return
      }
      try {
        const supported = await navigator.xr.isSessionSupported('immersive-ar')
        setArCheckState(supported ? 'supported' : 'unsupported')
      } catch {
        setArCheckState('unsupported')
      }
    }
    check()
  }, [])

  // ── Start session — called directly from click handler ────────────
  const startSession = useCallback(async () => {
    if (!navigator.xr) return

    setXrState('requesting')
    setErrorMessage(null)

    // Try with depth-sensing options first, fall back without them.
    // Some iOS versions reject unknown session init properties.
    let session = null
    try {
      session = await navigator.xr.requestSession('immersive-ar', {
        requiredFeatures: ['hit-test'],
        optionalFeatures: ['depth-sensing', 'plane-detection'],
        depthSensing: {
          usagePreference: ['cpu-optimized'],
          dataFormatPreference: ['luminance-alpha'],
        },
      })
    } catch {
      // Retry without depthSensing (older iOS / non-LiDAR devices)
      try {
        session = await navigator.xr.requestSession('immersive-ar', {
          requiredFeatures: ['hit-test'],
          optionalFeatures: ['plane-detection'],
        })
      } catch (err) {
        setXrState('error')
        setErrorMessage(err.message || 'No se pudo iniciar la sesión AR')
        return
      }
    }

    sessionRef.current = session
    setXrSession(session)
    setXrState('active')

    session.addEventListener('end', () => {
      sessionRef.current = null
      setXrSession(null)
      setXrState('ended')
    })
  }, [])

  const endSession = useCallback(() => {
    if (sessionRef.current) {
      try { sessionRef.current.end() } catch {}
    }
  }, [])

  return {
    xrSession,
    xrState,
    arCheckState,
    errorMessage,
    startSession,
    endSession,
  }
}
