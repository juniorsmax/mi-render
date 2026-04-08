/**
 * lidar.js — Detección y bridge de LiDAR para mi-render
 *
 * Estrategia:
 *  1. En Capacitor (nativo iOS): plugin Swift via RoomPlan (habitación) o ARKit .mesh (objeto)
 *  2. En web: detecta WebXR AR
 *  3. Fallback: cámara + marcado manual de esquinas
 *
 * Dispositivos con LiDAR: iPhone 12 Pro+, iPad Pro 2020+
 */

import { Capacitor } from '@capacitor/core'

// ── Helpers de llamada nativa ─────────────────────────────────────────────────

async function callNative(method, args = {}) {
  if (Capacitor.isNativePlatform()) {
    return Capacitor.nativePromise('LiDARPlugin', method, args)
  }
  throw new Error('Solo disponible en iOS nativo')
}

// ── Detección de capacidades ──────────────────────────────────────────────────

/**
 * Devuelve la info completa de capacidades del dispositivo
 */
export async function getDeviceCapabilities() {
  if (Capacitor.isNativePlatform()) {
    try {
      return await callNative('isAvailable', {})
    } catch {
      return { available: false, lidar: false, roomPlan: false, objectScan: false }
    }
  }
  return { available: false, lidar: false, roomPlan: false, objectScan: false }
}

/**
 * Devuelve true si el dispositivo tiene LiDAR disponible via nativo
 */
export async function hasLiDAR() {
  if (Capacitor.isNativePlatform()) {
    try {
      const result = await callNative('isAvailable', {})
      return result?.available === true
    } catch {
      return false
    }
  }

  if ('xr' in navigator) {
    try {
      return await navigator.xr.isSessionSupported('immersive-ar')
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
      const result = await callNative('isAvailable', {})
      if (result?.available) return 'lidar-native'
    } catch {}
  }

  if ('xr' in navigator) {
    try {
      if (await navigator.xr.isSessionSupported('immersive-ar')) return 'lidar-web'
    } catch {}
  }

  if (navigator.mediaDevices?.getUserMedia) return 'camera'

  return 'manual'
}

// ── Bridge nativo LiDAR — Habitación ─────────────────────────────────────────

/**
 * Inicia un escaneo LiDAR de habitación via RoomPlan (iOS 16+)
 * La UI nativa de Apple toma el control; devuelve cuando el usuario presiona "Listo"
 */
export async function startLiDARScan() {
  const result = await callNative('startScan', {})
  return parseLiDARResult(result)
}

/**
 * Parsea el resultado del plugin nativo (habitación) a formato interno
 */
function parseLiDARResult(raw) {
  if (!raw) return null
  return {
    areaSqM:    raw.floorArea  ?? null,
    walls:      raw.walls      ?? [],
    wallCount:  raw.wallCount  ?? 0,
    doors:      raw.doors      ?? [],
    windows:    raw.windows    ?? [],
    scanMode:   'lidar-native',
    confidence: raw.confidence ?? 'medium',
  }
}

// ── Bridge nativo LiDAR — Objeto 3D ──────────────────────────────────────────

/**
 * Inicia un escaneo 3D de objeto via ARKit Scene Reconstruction (.mesh)
 * Devuelve bounding box, número de caras/vértices y dimensiones del objeto
 */
export async function startObjectScan() {
  const result = await callNative('startObjectScan', {})
  return parseObjectResult(result)
}

/**
 * Parsea el resultado del escaneo de objeto
 */
function parseObjectResult(raw) {
  if (!raw) return null
  return {
    scanMode:     'object-mesh',
    dimensions:   raw.dimensions   ?? '',
    boundingBox:  raw.boundingBox  ?? {},
    meshFaces:    raw.meshFaces    ?? 0,
    meshVertices: raw.meshVertices ?? 0,
    anchorCount:  raw.anchorCount  ?? 0,
    confidence:   raw.confidence   ?? 'medium',
  }
}

// ── Parar escaneo ─────────────────────────────────────────────────────────────

export async function stopScan() {
  if (Capacitor.isNativePlatform()) {
    try { await callNative('stopScan', {}) } catch {}
  }
}

// ── Etiquetas para UI ─────────────────────────────────────────────────────────

export const SCAN_MODE_LABELS = {
  'lidar-native': { label: 'LiDAR',   desc: 'Escaneo 3D preciso',  color: '#2dd4bf' },
  'lidar-web':    { label: 'AR Web',  desc: 'AR via navegador',    color: '#a78bfa' },
  'camera':       { label: 'Cámara',  desc: 'Marcado manual',      color: '#f0a500' },
  'manual':       { label: 'Manual',  desc: 'Introduce medidas',   color: '#6b7280' },
  'object-mesh':  { label: 'Objeto',  desc: 'Malla 3D capturada',  color: '#f0a500' },
}
