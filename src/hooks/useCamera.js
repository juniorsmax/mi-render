import { useRef, useState, useCallback } from 'react'
import { Capacitor } from '@capacitor/core'

/**
 * useCamera — acceso a cámara compatible con web y Capacitor iOS
 *
 * En iOS nativo (Capacitor) getUserMedia funciona via WKWebView
 * pero requiere NSCameraUsageDescription en Info.plist (ya añadido).
 *
 * Estrategia de facingMode:
 *  - Primero intenta 'environment' (cámara trasera, ideal para escanear)
 *  - Si falla, reintenta sin restricción de facingMode
 */
export function useCamera() {
  const videoRef  = useRef(null)
  const streamRef = useRef(null)
  const [state, setState]       = useState('idle')
  const [errorMsg, setErrorMsg] = useState(null)

  const start = useCallback(async () => {
    setState('requesting')
    setErrorMsg(null)

    // En iOS nativo necesitamos un pequeño delay para que el permiso se resuelva
    if (Capacitor.isNativePlatform()) {
      await new Promise((r) => setTimeout(r, 300))
    }

    // Intento 1: cámara trasera HD
    const constraints = [
      {
        video: {
          facingMode: { ideal: 'environment' },
          width:  { ideal: 1920 },
          height: { ideal: 1080 },
        },
        audio: false,
      },
      // Intento 2: cámara trasera sin resolución específica
      {
        video: { facingMode: 'environment' },
        audio: false,
      },
      // Intento 3: cualquier cámara disponible
      {
        video: true,
        audio: false,
      },
    ]

    let stream = null
    let lastErr = null

    for (const constraint of constraints) {
      try {
        stream = await navigator.mediaDevices.getUserMedia(constraint)
        break
      } catch (err) {
        lastErr = err
      }
    }

    if (!stream) {
      setState('error')
      const err = lastErr
      if (err?.name === 'NotAllowedError') {
        setErrorMsg(
          Capacitor.isNativePlatform()
            ? 'Permiso denegado. Ve a Ajustes del iPhone → mi-render → Cámara y actívala.'
            : 'Permiso denegado. Ve a Ajustes → Safari → Cámara y permite el acceso.'
        )
      } else if (err?.name === 'NotFoundError') {
        setErrorMsg('No se encontró ninguna cámara en este dispositivo.')
      } else if (err?.name === 'NotReadableError') {
        setErrorMsg('La cámara está siendo usada por otra app. Ciérrala e inténtalo de nuevo.')
      } else {
        setErrorMsg('Error al acceder a la cámara: ' + (err?.message ?? 'desconocido'))
      }
      return
    }

    streamRef.current = stream

    if (videoRef.current) {
      videoRef.current.srcObject = stream
      videoRef.current.setAttribute('playsinline', '')
      videoRef.current.setAttribute('muted', '')
      try {
        await videoRef.current.play()
      } catch (playErr) {
        // En iOS a veces play() necesita interacción del usuario — ignorar
      }
    }

    setState('active')
  }, [])

  const stop = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    if (videoRef.current) videoRef.current.srcObject = null
    setState('idle')
  }, [])

  return { videoRef, cameraState: state, errorMsg, start, stop }
}
