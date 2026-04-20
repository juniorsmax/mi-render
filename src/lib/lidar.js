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
    floorArea:    raw.areaSqM      ?? raw.floorArea   ?? 0,
    wallArea:     raw.wallArea      ?? 0,
    ceilingArea:  raw.ceilingArea   ?? 0,
    windowArea:   raw.windowArea    ?? 0,
    doorArea:     raw.doorArea      ?? 0,
    tableArea:    raw.tableArea     ?? 0,
    seatArea:     raw.seatArea      ?? 0,
    otherArea:    raw.otherArea     ?? 0,
    totalVolume:  raw.volume        ?? raw.totalVolume ?? 0,
    perimeter:    raw.perimeterM    ?? raw.perimeter   ?? 0,
    avgHeight:    raw.avgHeight     ?? 2.5,
    walls:        raw.walls         ?? [],
    doors:        raw.doors         ?? [],
    windows:      raw.windows       ?? [],
    openings:     raw.openings      ?? [],
    wallCount:    raw.wallCount     ?? raw.walls?.length ?? 0,
    objects:      raw.objects       ?? [],
    confidence:   raw.confidence    ?? 'high',
    scanMode:     'lidar-native',
    usdzPath:     raw.usdzPath      ?? null,
    usdzExported: !!(raw.usdzPath   || raw.usdzExported),
    meshAnchorsCount: raw.meshAnchorsCount ?? 0,
  }
}

// ── Fotogrametría on-device (iOS 17+) ─────────────────────────────────────────

/**
 * Abre la cámara para capturar fotos y procesa un modelo 3D texturizado
 * mediante Object Capture API (PhotogrammetrySession).
 * Devuelve { usdzPath, photoCount, scanMode: 'photogrammetry' }
 */
/**
 * Abre el recorrido interior en primera persona (SceneKit)
 * path — ruta local al archivo USDZ
 */
export async function startWalkthrough(path) {
  return callNative('startWalkthrough', { path })
}

export async function startPhotogrammetry() {
  const result = await callNative('startPhotogrammetry', {})
  if (!result) return null
  return {
    usdzPath:     result.usdzPath   ?? null,
    usdzExported: !!result.usdzPath,
    photoCount:   result.photoCount ?? 0,
    scanMode:     'photogrammetry',
    floorArea:    0,
    wallArea:     0,
    wallCount:    0,
    walls:        [],
    doors:        [],
    windows:      [],
    openings:     [],
    confidence:   'high',
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
    try { return await callNative('stopScan', {}) } catch {}
  }
}

// ── Etiquetas para UI ─────────────────────────────────────────────────────────

// ── Persistencia espacial ──────────────────────────────────────────────────────

/**
 * Guarda el ARWorldMap actual con un nombre
 * @param {string} name — nombre del mapa (ej. "salon-v1")
 */
export async function saveWorldMap(name = 'worldmap') {
  return callNative('saveWorldMap', { name })
}

// ── Medición de distancias ────────────────────────────────────────────────────

/**
 * Mide la distancia entre dos puntos 3D en el espacio AR
 * @param {{ x, y, z }} pointA
 * @param {{ x, y, z }} pointB
 * @returns {{ distanceM: number, formatted: string }}
 */
export async function measureDistance(pointA, pointB) {
  return callNative('measureDistance', { pointA, pointB })
}

// ── Exportación de malla 3D ───────────────────────────────────────────────────

/**
 * Exporta la malla 3D capturada como archivo OBJ
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportOBJ(name = 'mi-render-mesh') {
  return callNative('exportOBJ', { name })
}

/**
 * Exporta la malla 3D capturada como archivo PLY (nube de puntos)
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportPLY(name = 'mi-render-mesh') {
  return callNative('exportPLY', { name })
}

/**
 * Exporta la malla 3D capturada como archivo STL (impresión 3D)
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportSTL(name = 'mi-render-mesh') {
  return callNative('exportSTL', { name })
}

/**
 * Exporta el último escaneo RoomPlan como USDZ (AR QuickLook)
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportUSDZ(name = 'mi-render-scan') {
  return callNative('exportUSDZ', { name })
}

/**
 * Exporta el plano de la habitación como archivo DXF (AutoCAD)
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportDXF(name = 'mi-render-plan') {
  return callNative('exportDXF', { name })
}

/**
 * Exporta la malla 3D capturada como archivo DAE (Collada)
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportDAE(name = 'mi-render-mesh') {
  return callNative('exportDAE', { name })
}

/**
 * Exporta el plano de la habitación como archivo SVG vectorial
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportSVG(name = 'mi-render-plan') {
  return callNative('exportSVG', { name })
}

/**
 * Exporta el plano de la habitación como PDF arquitectónico A4
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportPDF(name = 'mi-render-plan') {
  return callNative('exportPDF', { name })
}

/**
 * Exporta la malla 3D capturada como archivo GLTF (web 3D estándar)
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportGLTF(name = 'mi-render-mesh') {
  return callNative('exportGLTF', { name })
}

/**
 * Exporta la malla 3D capturada como archivo GLB (GLTF binario)
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportGLB(name = 'mi-render-mesh') {
  return callNative('exportGLB', { name })
}

/**
 * Exporta el escaneo completo en todos los formatos disponibles
 * OBJ, PLY, STL, USDZ, DAE, DXF, SVG, PDF, GLTF, GLB
 * @param {string} name — prefijo para todos los archivos
 * @returns {{ files: Array<{path, format}>, count: number }}
 */
export async function exportAllFormats(name = 'mi-render-export') {
  return callNative('exportAllFormats', { name })
}

/**
 * Devuelve las superficies calculadas de la última malla ARKit capturada.
 * Clasifica por ARMeshClassification: floor, wall, ceiling, table, seat, window, door, other
 * @returns {{ floorArea, wallArea, ceilingArea, tableArea, seatArea, windowArea, doorArea, otherArea, totalArea }} en m²
 */
export async function getSurfaceAreas() {
  return callNative('getSurfaceAreas', {})
}

/**
 * Calcula el área de cada pared detectada vía ARMeshClassification.wall.
 * Agrupa faces por plano (normal similar + distancia), calcula área y dimensiones.
 * @returns {{ walls: [{id,label,area,width,height,faceCount,normalX,normalZ,...}], wallCount, totalWallArea }}
 */
export async function getWallMetrics() {
  return callNative('getWallMetrics', {})
}

/**
 * Proyecta los vértices .floor del mesh ARKit al plano XZ,
 * calcula el convex hull y simplifica con Douglas-Peucker.
 * @param {{ simplifyEpsilon?: number }} opts — tolerancia D-P en metros (default 0.05)
 * @returns {{ polygon: [{x,z}], area, width, depth, minX, minZ, maxX, maxZ, pointCount }}
 */
export async function getFloorFootprint(opts = {}) {
  return callNative('getFloorFootprint', { simplifyEpsilon: opts.simplifyEpsilon ?? 0.05 })
}

/**
 * Genera una imagen PNG (base64) del plano planta combinando
 * footprint ARKit + paredes RoomPlan. Requiere iOS 16+.
 * @param {{ width?: number, height?: number }} opts — dimensiones en puntos (default 800x800)
 * @returns {{ image: string }} — data URI "data:image/png;base64,..."
 */
export async function renderFloorPlan(opts = {}) {
  return callNative('renderFloorPlan', {
    width:  opts.width  ?? 800,
    height: opts.height ?? 800,
  })
}

// ── Detección de habitaciones múltiples ──────────────────────────────────────

/**
 * Segmenta el mesh del suelo en habitaciones individuales usando flood-fill.
 * Enriquece cada segmento con altura y volumen calculados desde el techo.
 * @param {{ cellSize?: number, minAreaM2?: number }} opts
 * @returns {{ rooms: Array, roomCount: number, totalArea: number, totalVolume: number }}
 */
export async function getRoomSegmentation(opts = {}) {
  return callNative('getRoomSegmentation', {
    cellSize:  opts.cellSize  ?? 0.20,
    minAreaM2: opts.minAreaM2 ?? 0.8,
  })
}

/**
 * Calcula el volumen automático de cada habitación (m³).
 * Usa altura del techo medida por LiDAR, no un valor fijo.
 * @returns {{ volumes: Array<{roomId,label,floorArea,avgHeight,volume}>, totalVolume: number, roomCount: number }}
 */
export async function getAutoVolume() {
  return callNative('getAutoVolume', {})
}

/**
 * Exporta el escaneo como archivo IFC 2x3 (BIM profesional).
 * Compatible con ArchiCAD, Revit, FreeCAD, BIMvision, Solibri.
 * Incluye: proyecto → sitio → edificio → planta → habitaciones + paredes + puertas + ventanas.
 * @param {string} name — nombre del archivo (sin extensión)
 * @param {{ projectName?: string }} opts
 */
export async function exportIFC(name = 'mi-render-bim', opts = {}) {
  return callNative('exportIFC', { name, projectName: opts.projectName ?? 'mi-render' })
}

/**
 * Exporta USDZ optimizado con materiales PBR por clasificación de superficie.
 * Suelo=marrón, paredes=gris, techo=blanco, muebles=tonos cálidos.
 * @param {string} name — nombre del archivo (sin extensión)
 */
export async function exportOptimizedUSDZ(name = 'mi-render-mesh') {
  return callNative('exportOptimizedUSDZ', { name })
}

// ── Proyectos persistentes ────────────────────────────────────────────────────

/**
 * Lista todos los proyectos guardados en Documents/projects/
 * @returns {{ projects: Array, count: number }}
 */
export async function listProjects() {
  return callNative('listProjects', {})
}

/**
 * Abre el visor 3D nativo para un proyecto guardado
 * @param {string|null} projectId — UUID del proyecto (opcional)
 */
export async function openViewer(projectId = null) {
  return callNative('openViewer', projectId ? { projectId } : {})
}

/**
 * Elimina un proyecto guardado del disco
 * @param {string} projectId
 */
export async function deleteProject(projectId) {
  return callNative('deleteProject', { projectId })
}

// ── Etiquetas para UI ─────────────────────────────────────────────────────────

export const SCAN_MODE_LABELS = {
  'lidar-native': { label: 'LiDAR',   desc: 'Escaneo 3D preciso',  color: '#2dd4bf' },
  'lidar-web':    { label: 'AR Web',  desc: 'AR via navegador',    color: '#a78bfa' },
  'camera':       { label: 'Cámara',  desc: 'Marcado manual',      color: '#f0a500' },
  'manual':       { label: 'Manual',  desc: 'Introduce medidas',   color: '#6b7280' },
  'object-mesh':  { label: 'Objeto',  desc: 'Malla 3D capturada',  color: '#f0a500' },
}
