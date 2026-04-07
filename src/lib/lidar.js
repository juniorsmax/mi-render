/**
 * lidar.js — Detección y bridge de LiDAR para mi-render
 *
 * Estrategia:
 *  1. En web (Safari): detecta si hay soporte WebXR depth-sensing
 *  2. En Capacitor (nativo iOS): comunica con plugin Swift via Capacitor.call()
 *  3. Fallback: cámara + marcado manual de esquinas (actual)
 *
 * Dispositivos con LiDAR: iPhone 12 Pro+, iPad Pro 2020+
 */

import { Capacitor } from '@capacitor/core'

// ── Detección de capacidades ─────────────────────────────────────────────────

/**
 * Devuelve true si el dispositivo tiene LiDAR disponible via nativo
 */
export async function hasLiDAR() {
  // En entorno nativo Capacitor
  if (Capacitor.isNativePlatform()) {
    try {
      const result = await Capacitor.nativePromise('LiDARPlugin', 'isAvailable', {})
      return result?.available === true
    } catch {
      return false
    }
  }

  // En web: intenta detectar via WebXR depth-sensing
  if ('xr' in navigator) {
    try {
      const supported = await navigator.xr.isSessionSupported('immersive-ar')
      return supported
    } catch {
      return false
    }
  }

  return false
}

/**
 * Devuelve el modo de escaneo disponible
 * @returns {'lidar-native' | 'lidar-web' | 'camera' | 'manual'}
 */
export async function getScanMode() {
  if (Capacitor.isNativePlatform()) {
    try {
      const result = await Capacitor.nativePromise('LiDARPlugin', 'isAvailable', {})
      if (result?.available) return 'lidar-native'
    } catch {}
  }

  if ('xr' in navigator) {
    try {
      const supported = await navigator.xr.isSessionSupported('immersive-ar')
      if (supported) return 'lidar-web'
    } catch {}
  }

  // Verificar cámara disponible
  if (navigator.mediaDevices?.getUserMedia) return 'camera'

  return 'manual'
}

// ── Bridge nativo LiDAR ──────────────────────────────────────────────────────

/**
 * Inicia un escaneo LiDAR nativo via RoomPlan
 * Retorna datos de la habitación (paredes, dimensiones, área)
 */
export async function startLiDARScan() {
  if (!Capacitor.isNativePlatform()) {
    throw new Error('LiDAR nativo solo disponible en iOS')
  }

  try {
    const result = await Capacitor.nativePromise('LiDARPlugin', 'startScan', {})
    return parseLiDARResult(result)
  } catch (err) {
    throw new Error('Error al iniciar escaneo LiDAR: ' + err.message)
  }
}

/**
 * Parsea el resultado del plugin nativo a formato interno
 */
function parseLiDARResult(raw) {
  if (!raw) return null
  return {
    areaSqM: raw.floorArea ?? null,
    roomName: raw.roomName ?? '',
    dimensions: raw.dimensions ?? null,
    walls: raw.walls ?? [],
    pointCloud: raw.pointCloud ?? null,
    scanMode: 'lidar-native',
    confidence: raw.confidence ?? 'medium',
  }
}

// ── Etiquetas para UI ────────────────────────────────────────────────────────

export const SCAN_MODE_LABELS = {
  'lidar-native': { label: 'LiDAR', desc: 'Escaneo 3D preciso', color: '#2dd4bf' },
  'lidar-web':    { label: 'AR Web', desc: 'AR via navegador',   color: '#a78bfa' },
  'camera':       { label: 'Cámara', desc: 'Marcado manual',     color: '#f0a500' },
  'manual':       { label: 'Manual', desc: 'Introduce medidas',  color: '#6b7280' },
}
