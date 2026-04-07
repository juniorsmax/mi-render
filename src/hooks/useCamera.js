import { useRef, useState, useCallback } from 'react'

export function useCamera() {
  const videoRef = useRef(null)
  const streamRef = useRef(null)
  const [state, setState] = useState('idle') // 'idle' | 'requesting' | 'active' | 'error'
  const [errorMsg, setErrorMsg] = useState(null)

  const start = useCallback(async () => {
    setState('requesting')
    setErrorMsg(null)
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: { ideal: 'environment' },
          width: { ideal: 1920 },
          height: { ideal: 1080 },
        },
        audio: false,
      })
      streamRef.current = stream
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        await videoRef.current.play()
      }
      setState('active')
    } catch (err) {
      setState('error')
      setErrorMsg(
        err.name === 'NotAllowedError'
          ? 'Permiso de cámara denegado. Ve a Ajustes → Safari → Cámara y permite el acceso.'
          : err.message
      )
    }
  }, [])

  const stop = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
  }, [])

  return { videoRef, cameraState: state, errorMsg, start, stop }
}
