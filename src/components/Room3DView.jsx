/**
 * Room3DView.jsx — Vista 3D interactiva estilo Polycam (dollhouse)
 * Sustituye a ScanExport cuando el escaneo es LiDAR nativo.
 *
 * Features:
 *  - Dollhouse 3D con Three.js / @react-three/fiber
 *  - Paredes blancas mate, suelo parquet/baldosa, techo oculto por defecto
 *  - Iluminación estudio (key + fill + rim)
 *  - OrbitControls: rotar / pinch-zoom / reset top-down
 *  - Toggle capas: muebles / techo / medidas / texturas
 *  - Modo recorrido (primera persona, joystick virtual)
 *  - Barra inferior: Medir · Plano 2D · Exportar · Comentario · Vídeo
 *  - Carga USDZ si está disponible
 *
 * Props:
 *  result       — objeto parseLiDARResult ({ walls, doors, windows, floorArea, … })
 *  projectName  — string
 *  onBack       — función para volver al ScanExport clásico
 *  onAccept     — función llamada al aceptar (continúa flujo presupuesto)
 */

import { Suspense, useRef, useState, useEffect, createContext, useContext } from 'react'
import { Canvas, useFrame, useThree } from '@react-three/fiber'
import {
  OrbitControls,
  PerspectiveCamera,
  Html,
  ContactShadows,
} from '@react-three/drei'
import * as THREE from 'three'
import { exportUSDZ, exportMeshUSDZ, openViewer } from '../lib/lidar'
import { Capacitor } from '@capacitor/core'
import './Room3DView.css'

// Contexto para raycasting del modo Medir
const MeasureCtx = createContext(null)

// ─── Paleta de objetos detectados ────────────────────────────────────────────

const OBJ_STYLES = {
  bed:         { color: '#d4a574', emissive: '#b8864e', label: '🛏 Cama'      },
  sofa:        { color: '#8b7355', emissive: '#6b5535', label: '🛋 Sofá'      },
  chair:       { color: '#a0896b', emissive: '#806949', label: '🪑 Silla'     },
  table:       { color: '#c4a882', emissive: '#a48862', label: '🪵 Mesa'      },
  television:  { color: '#1a1a2e', emissive: '#000010', label: '📺 TV'        },
  refrigerator:{ color: '#e8e8e8', emissive: '#c8c8c8', label: '🧊 Nevera'   },
  washerDryer: { color: '#dde8f0', emissive: '#bdc8d0', label: '🫧 Lavadora' },
  dishwasher:  { color: '#e0e8e0', emissive: '#c0c8c0', label: '🍽 Lavavaj.' },
  oven:        { color: '#c8c0b0', emissive: '#a8a090', label: '🍳 Horno'    },
  stove:       { color: '#b8b0a0', emissive: '#989080', label: '🔥 Cocina'   },
  sink:        { color: '#d0dce8', emissive: '#b0bcc8', label: '🚿 Lavabo'   },
  toilet:      { color: '#f0f0ee', emissive: '#d0d0ce', label: '🚽 WC'       },
  bathtub:     { color: '#e8f0f8', emissive: '#c8d0d8', label: '🛁 Bañera'   },
  fireplace:   { color: '#8b4513', emissive: '#6b2500', label: '🔥 Chimenea' },
  stairs:      { color: '#c8c0b0', emissive: '#a8a090', label: '🪜 Escalera' },
  storage:     { color: '#b8a898', emissive: '#988878', label: '📦 Armario'  },
}
const OBJ_DEFAULT = { color: '#aaaaaa', emissive: '#888888', label: '📦 Obj.' }

// ─── Constantes de diseño ────────────────────────────────────────────────────

const WALL_COLOR    = '#f5f5f0'   // blanco mate cálido
const FLOOR_PARQUET = '#c8a96e'   // madera parquet
const FLOOR_TILE    = '#e8e4dc'   // baldosa clara
const CEIL_COLOR    = '#fafaf8'
const DOOR_COLOR    = '#b8956a'
const WIN_COLOR     = '#a8cce8'
const WALL_H        = 2.5          // altura por defecto si no viene en result

// ─── Escena dollhouse ────────────────────────────────────────────────────────

function DollhouseScene({ result, layers, floorType }) {
  const walls   = result?.walls   ?? []
  const doors   = result?.doors   ?? []
  const windows = result?.windows ?? []
  const objects = result?.objects ?? []
  const height  = result?.avgHeight ?? WALL_H
  const onPick  = useContext(MeasureCtx)

  // Calcular bbox del suelo para centrarlo en escena
  const floorW = result?.floorArea ? Math.sqrt(result.floorArea) * 1.2 : 4
  const floorD = floorW

  function handleClick(e) {
    if (!onPick) return
    e.stopPropagation()
    onPick(e.point.clone())
  }

  return (
    <group>
      {/* Suelo (también clickable en modo medir) */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow onClick={handleClick}>
        <planeGeometry args={[floorW * 2, floorD * 2]} />
        <meshStandardMaterial
          color={floorType === 'tile' ? FLOOR_TILE : FLOOR_PARQUET}
          roughness={0.8}
          metalness={0.0}
        />
      </mesh>

      {/* Techo (oculto por defecto, toggle capa) */}
      {layers.ceil && (
        <mesh position={[0, height, 0]} rotation={[Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[floorW * 2, floorD * 2]} />
          <meshStandardMaterial color={CEIL_COLOR} roughness={0.9} transparent opacity={0.6} />
        </mesh>
      )}

      {/* Paredes desde datos RoomPlan */}
      {walls.map((wall, i) => (
        <WallMesh key={`wall-${i}`} wall={wall} height={height} />
      ))}

      {/* Puertas */}
      {doors.map((door, i) => (
        <SurfaceMesh key={`door-${i}`} surface={door} color={DOOR_COLOR} opacity={0.5} />
      ))}

      {/* Ventanas */}
      {windows.map((win, i) => (
        <SurfaceMesh key={`win-${i}`} surface={win} color={WIN_COLOR} opacity={0.45} />
      ))}

      {/* Objetos detectados (muebles, electrodomésticos…) */}
      {layers.furniture && objects.map((obj, i) => (
        <ObjectMesh key={`obj-${i}`} object={obj} />
      ))}

      {/* Etiquetas de medidas */}
      {layers.measures && walls.map((wall, i) => (
        <WallLabel key={`lbl-${i}`} wall={wall} height={height} />
      ))}

      {/* Sombra de contacto */}
      <ContactShadows
        position={[0, 0.01, 0]}
        opacity={0.35}
        scale={floorW * 2.5}
        blur={2}
        far={4}
      />
    </group>
  )
}

// Pared individual desde datos RoomPlan
function WallMesh({ wall, height }) {
  const onPick  = useContext(MeasureCtx)
  const transform = wall.transform
  const dimX = wall.dimensions?.[0] ?? wall.width  ?? 3
  const dimY = wall.dimensions?.[1] ?? height
  const dimZ = wall.dimensions?.[2] ?? 0.2
  const matrix = transform ? buildMatrix(transform) : null

  return (
    <mesh castShadow receiveShadow matrixAutoUpdate={false}
      ref={el => { if (el && matrix) el.matrix.copy(matrix) }}
      onClick={onPick ? (e) => { e.stopPropagation(); onPick(e.point.clone()) } : undefined}>
      <boxGeometry args={[dimX, dimY, Math.max(dimZ, 0.12)]} />
      <meshStandardMaterial color={WALL_COLOR} roughness={0.85} metalness={0} />
    </mesh>
  )
}

// Superficie genérica (puerta/ventana)
function SurfaceMesh({ surface, color, opacity }) {
  const onPick  = useContext(MeasureCtx)
  const transform = surface.transform
  const dimX = surface.dimensions?.[0] ?? surface.width  ?? 1
  const dimY = surface.dimensions?.[1] ?? surface.height ?? 2
  const dimZ = surface.dimensions?.[2] ?? 0.1
  const matrix = transform ? buildMatrix(transform) : null

  return (
    <mesh matrixAutoUpdate={false}
      ref={el => { if (el && matrix) el.matrix.copy(matrix) }}
      onClick={onPick ? (e) => { e.stopPropagation(); onPick(e.point.clone()) } : undefined}>
      <boxGeometry args={[dimX, dimY, Math.max(dimZ, 0.08)]} />
      <meshStandardMaterial color={color} transparent opacity={opacity}
        roughness={0.5} metalness={0.1} />
    </mesh>
  )
}

// Etiqueta HTML de medida flotante en la pared
function WallLabel({ wall, height }) {
  const transform = wall.transform
  const dimX = wall.dimensions?.[0] ?? 3
  const matrix = transform ? buildMatrix(transform) : null

  // Posición: centro de la pared + algo por encima
  const pos = matrix
    ? new THREE.Vector3().setFromMatrixPosition(matrix)
    : new THREE.Vector3(0, height / 2, 0)
  pos.y = height * 0.55

  return (
    <Html position={[pos.x, pos.y, pos.z]} center distanceFactor={8}
      style={{ pointerEvents: 'none' }}>
      <div className="r3d-label">
        {dimX.toFixed(2)} m
      </div>
    </Html>
  )
}

// Objeto detectado por RoomPlan (cama, sofá, mesa, TV, etc.)
function ObjectMesh({ object }) {
  const style   = OBJ_STYLES[object.category] ?? OBJ_DEFAULT
  const matrix  = object.transform ? buildMatrix(object.transform) : null

  // Dimensiones (x=ancho, y=alto, z=prof)
  const dimX = object.dimensions?.[0] ?? 1.0
  const dimY = object.dimensions?.[1] ?? 0.8
  const dimZ = object.dimensions?.[2] ?? 0.6

  // Forma especial para TV: rectángulo muy delgado
  const isTV    = object.category === 'television'
  const isTable = object.category === 'table'

  if (isTV) {
    // TV: panel delgado montado en pared, plus pequeño pie/soporte
    return (
      <group matrixAutoUpdate={false}
        ref={el => { if (el && matrix) el.matrix.copy(matrix) }}>
        {/* Panel principal */}
        <mesh castShadow position={[0, 0, 0]}>
          <boxGeometry args={[dimX, dimY, 0.05]} />
          <meshStandardMaterial color={style.color} emissive={style.emissive}
            emissiveIntensity={0.2} roughness={0.3} metalness={0.6} />
        </mesh>
        {/* Marco exterior */}
        <mesh>
          <boxGeometry args={[dimX + 0.03, dimY + 0.03, 0.04]} />
          <meshStandardMaterial color="#333333" roughness={0.4} metalness={0.5} />
        </mesh>
        {/* Pantalla (emisiva azul tenue) */}
        <mesh position={[0, 0, 0.026]}>
          <boxGeometry args={[dimX * 0.92, dimY * 0.88, 0.002]} />
          <meshStandardMaterial color="#0a1628" emissive="#1a3a6a" emissiveIntensity={0.15} />
        </mesh>
      </group>
    )
  }

  if (isTable) {
    // Mesa: tablero + 4 patas
    const legH   = dimY * 0.75
    const legW   = 0.06
    const topH   = dimY * 0.08
    const ox     = (dimX / 2 - 0.12)
    const oz     = (dimZ / 2 - 0.12)
    const yTop   = -dimY / 2 + legH + topH / 2
    const yLeg   = -dimY / 2 + legH / 2
    return (
      <group matrixAutoUpdate={false}
        ref={el => { if (el && matrix) el.matrix.copy(matrix) }}>
        {/* Tablero */}
        <mesh castShadow position={[0, yTop, 0]}>
          <boxGeometry args={[dimX, topH, dimZ]} />
          <meshStandardMaterial color={style.color} emissive={style.emissive}
            emissiveIntensity={0.05} roughness={0.7} metalness={0.0} />
        </mesh>
        {/* 4 patas */}
        {[[-ox,-oz],[ox,-oz],[-ox,oz],[ox,oz]].map(([px, pz], i) => (
          <mesh key={i} castShadow position={[px, yLeg, pz]}>
            <boxGeometry args={[legW, legH, legW]} />
            <meshStandardMaterial color={style.color} roughness={0.8} metalness={0.0} />
          </mesh>
        ))}
      </group>
    )
  }

  // Forma genérica: caja con bordes redondeados simulados (bevel)
  return (
    <group matrixAutoUpdate={false}
      ref={el => { if (el && matrix) el.matrix.copy(matrix) }}>
      {/* Cuerpo principal */}
      <mesh castShadow receiveShadow>
        <boxGeometry args={[dimX, dimY, dimZ]} />
        <meshStandardMaterial
          color={style.color}
          emissive={style.emissive}
          emissiveIntensity={0.05}
          roughness={0.7}
          metalness={0.05}
        />
      </mesh>
      {/* Línea de borde superior (highlight) */}
      <mesh position={[0, dimY / 2, 0]}>
        <boxGeometry args={[dimX + 0.01, 0.015, dimZ + 0.01]} />
        <meshStandardMaterial color="#ffffff" transparent opacity={0.35} roughness={0.3} />
      </mesh>
    </group>
  )
}

// ─── Luces ───────────────────────────────────────────────────────────────────

function StudioLights() {
  return (
    <>
      <ambientLight intensity={0.6} />
      {/* Key light */}
      <directionalLight position={[5, 8, 5]} intensity={1.2} castShadow
        shadow-mapSize={[1024, 1024]} />
      {/* Fill light */}
      <directionalLight position={[-4, 4, -4]} intensity={0.4} />
      {/* Rim light */}
      <directionalLight position={[0, 6, -8]} intensity={0.3} color="#b8d4ff" />
    </>
  )
}

// ─── Cámara primera persona ──────────────────────────────────────────────────

function FirstPersonCamera({ joystick }) {
  const { camera } = useThree()
  const yaw   = useRef(0)
  const speed = 0.03

  useEffect(() => {
    camera.position.set(0, 1.6, 2)
    camera.rotation.set(0, 0, 0)
  }, [camera])

  useFrame(() => {
    if (!joystick.current) return
    const { x, y } = joystick.current
    const dir = new THREE.Vector3(x, 0, -y).normalize()
    dir.applyQuaternion(camera.quaternion)
    dir.y = 0
    camera.position.addScaledVector(dir, speed)
    camera.position.y = 1.6  // altura fija
  })

  return null
}

// ─── Helpers de transform ────────────────────────────────────────────────────

function buildMatrix(transform) {
  // transform puede ser: array16 col-major float, o {columns:[…]} de simd_float4x4
  let arr
  if (Array.isArray(transform)) {
    arr = transform
  } else if (transform?.columns) {
    // simd_float4x4 serializado como {columns: [[…],[…],[…],[…]]}
    arr = transform.columns.flatMap(c => c)
  } else {
    return null
  }
  const m = new THREE.Matrix4()
  m.set(
    arr[0], arr[4], arr[8],  arr[12],
    arr[1], arr[5], arr[9],  arr[13],
    arr[2], arr[6], arr[10], arr[14],
    arr[3], arr[7], arr[11], arr[15],
  )
  return m
}

// ─── Joystick virtual ────────────────────────────────────────────────────────

function VirtualJoystick({ joystickRef }) {
  const base   = useRef(null)
  const thumb  = useRef(null)
  const active = useRef(null)

  function onTouchStart(e) {
    const touch = e.touches[0]
    active.current = { id: touch.identifier, ox: touch.clientX, oy: touch.clientY }
  }

  function onTouchMove(e) {
    if (!active.current) return
    for (const t of e.touches) {
      if (t.identifier === active.current.id) {
        const dx = Math.max(-1, Math.min(1, (t.clientX - active.current.ox) / 40))
        const dy = Math.max(-1, Math.min(1, (t.clientY - active.current.oy) / 40))
        joystickRef.current = { x: dx, y: dy }
        if (thumb.current) {
          thumb.current.style.transform = `translate(${dx * 20}px, ${dy * 20}px)`
        }
      }
    }
  }

  function onTouchEnd() {
    active.current = null
    joystickRef.current = { x: 0, y: 0 }
    if (thumb.current) thumb.current.style.transform = 'translate(0,0)'
  }

  return (
    <div className="r3d-joystick-wrap"
      onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd}>
      <div ref={base} className="r3d-joystick-base">
        <div ref={thumb} className="r3d-joystick-thumb" />
      </div>
    </div>
  )
}

// ─── Marcadores de medición (dentro del Canvas) ──────────────────────────────

function MeasureMarkers({ pending, measurements }) {
  return (
    <group>
      {/* Punto pendiente (primer clic) */}
      {pending && (
        <mesh position={pending}>
          <sphereGeometry args={[0.06, 12, 12]} />
          <meshBasicMaterial color="#ffcc00" />
        </mesh>
      )}

      {/* Mediciones completadas */}
      {measurements.map((m) => (
        <group key={m.id}>
          {/* Esfera A */}
          <mesh position={m.a}>
            <sphereGeometry args={[0.055, 12, 12]} />
            <meshBasicMaterial color="#ffcc00" />
          </mesh>
          {/* Esfera B */}
          <mesh position={m.b}>
            <sphereGeometry args={[0.055, 12, 12]} />
            <meshBasicMaterial color="#ffcc00" />
          </mesh>
          {/* Línea entre puntos */}
          <MeasureLine a={m.a} b={m.b} />
          {/* Etiqueta distancia */}
          <Html
            position={new THREE.Vector3().addVectors(m.a, m.b).multiplyScalar(0.5)}
            center
            distanceFactor={7}
            style={{ pointerEvents: 'none' }}>
            <div className="r3d-measure-tag">
              {m.dist.toFixed(2)} m
            </div>
          </Html>
        </group>
      ))}
    </group>
  )
}

// Cilindro delgado alineado entre dos puntos
function MeasureLine({ a, b }) {
  const mid = new THREE.Vector3().addVectors(a, b).multiplyScalar(0.5)
  const dir = new THREE.Vector3().subVectors(b, a)
  const len = dir.length()
  const q   = new THREE.Quaternion().setFromUnitVectors(
    new THREE.Vector3(0, 1, 0),
    dir.clone().normalize()
  )
  return (
    <mesh position={mid} quaternion={q}>
      <cylinderGeometry args={[0.012, 0.012, len, 6]} />
      <meshBasicMaterial color="#ffcc00" transparent opacity={0.85} />
    </mesh>
  )
}

// ─── Componente principal ────────────────────────────────────────────────────

export function Room3DView({ result, projectName = 'Habitación', onBack, onAccept }) {
  const orbitRef   = useRef()
  const joystick   = useRef({ x: 0, y: 0 })

  const [walkMode,      setWalkMode]      = useState(false)
  const [floorType,     setFloorType]     = useState('parquet')
  const [showLayers,    setShowLayers]    = useState(false)
  const [layers, setLayers] = useState({
    furniture: true, ceil: false, measures: false, textures: false,
  })
  const [activeBar,     setActiveBar]     = useState(null)
  const [exporting,     setExporting]     = useState(false)
  const [showExport,    setShowExport]    = useState(false)  // menú de export

  // ── Estado de mediciones ──────────────────────────────────────────
  const [measureMode,   setMeasureMode]   = useState(false)
  const [pending,       setPending]       = useState(null)      // THREE.Vector3 primer punto
  const [measurements,  setMeasurements]  = useState([])        // [{id,a,b,dist,label}]
  const [showMPanel,    setShowMPanel]    = useState(false)
  const [editingId,     setEditingId]     = useState(null)
  const [editLabel,     setEditLabel]     = useState('')

  // Activar/desactivar modo medir
  function toggleMeasure() {
    const next = !measureMode
    setMeasureMode(next)
    setPending(null)
    if (next) { setActiveBar('measure'); setShowMPanel(true) }
    else      { setActiveBar(null);      setShowMPanel(false) }
  }

  // Callback de clic en modelo 3D
  function handlePick(point) {
    if (!measureMode) return
    if (!pending) {
      setPending(point)
    } else {
      const dist = pending.distanceTo(point)
      const id   = Date.now()
      setMeasurements(prev => [
        ...prev,
        { id, a: pending, b: point, dist, label: `Medida ${prev.length + 1}` },
      ])
      setPending(null)
    }
  }

  // Editar etiqueta
  function startEdit(m) { setEditingId(m.id); setEditLabel(m.label) }
  function saveEdit(id) {
    setMeasurements(prev => prev.map(m => m.id === id ? { ...m, label: editLabel } : m))
    setEditingId(null)
  }
  function deleteMeasure(id) {
    setMeasurements(prev => prev.filter(m => m.id !== id))
    if (pending) setPending(null)
  }

  function toggleLayer(key) {
    setLayers(prev => ({ ...prev, [key]: !prev[key] }))
  }

  function resetCamera() {
    if (!orbitRef.current) return
    orbitRef.current.reset()
    orbitRef.current.setAzimuthalAngle(0)
    orbitRef.current.setPolarAngle(0.1)
    orbitRef.current.object.position.set(0, 12, 0.1)
    orbitRef.current.target.set(0, 0, 0)
    orbitRef.current.update()
  }

  // Exportar USDZ paramétrico — AR Quick Look, archivos, AirDrop
  async function handleExportAR() {
    setShowExport(false)
    setExporting('ar')
    try { await exportUSDZ({ name: projectName }) } catch { /* silencio */ }
    setExporting(false)
  }

  // Exportar USDZ de malla cruda — Blender, SketchUp, AutoCAD
  async function handleExportMesh() {
    setShowExport(false)
    setExporting('mesh')
    try { await exportMeshUSDZ({ name: projectName + '-mesh' }) } catch { /* silencio */ }
    setExporting(false)
  }

  // Exportar mediciones al presupuesto
  function handleAccept() {
    onAccept?.({ measurements })
  }

  return (
    <div className="r3d-root">
      {/* ── Header ── */}
      <div className="r3d-header">
        <button className="r3d-btn-icon" onClick={onBack}>
          <svg viewBox="0 0 24 24" width="22" height="22"><path d="M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z" fill="currentColor"/></svg>
        </button>
        <span className="r3d-title">{projectName}</span>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="r3d-btn-sm" onClick={() => setFloorType(f => f === 'parquet' ? 'tile' : 'parquet')}>
            {floorType === 'parquet' ? '🪵' : '⬜'}
          </button>
          <button className="r3d-btn-sm" onClick={resetCamera}>⊙</button>
          <button className="r3d-btn-sm r3d-btn-active" onClick={() => setShowLayers(v => !v)}>⊞</button>
        </div>
      </div>

      {/* ── Canvas 3D ── */}
      <div className={`r3d-canvas-wrap ${measureMode ? 'r3d-cursor-cross' : ''}`}>
        <MeasureCtx.Provider value={measureMode ? handlePick : null}>
          <Canvas shadows dpr={[1, 2]}
            gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping }}>
            <color attach="background" args={['#f5f2ea']} />
            <fog attach="fog" args={['#f5f2ea', 18, 38]} />

            <StudioLights />

            <Suspense fallback={null}>
              <DollhouseScene result={result} layers={layers} floorType={floorType} />
            </Suspense>

            <MeasureMarkers pending={pending} measurements={measurements} />

            {walkMode
              ? <FirstPersonCamera joystick={joystick} />
              : <>
                  <PerspectiveCamera makeDefault position={[0, 8, 8]} fov={50} />
                  <OrbitControls
                    ref={orbitRef}
                    enableDamping
                    dampingFactor={0.08}
                    minDistance={1.5}
                    maxDistance={25}
                    maxPolarAngle={Math.PI / 2}
                    enabled={!measureMode}
                  />
                </>
            }
          </Canvas>
        </MeasureCtx.Provider>
      </div>

      {/* ── Overlay instrucciones de medición ── */}
      {measureMode && (
        <div className="r3d-measure-overlay">
          <div className="r3d-measure-hint">
            {pending
              ? '📍 Toca el segundo punto'
              : '📍 Toca el primer punto'}
          </div>
          {pending && (
            <button className="r3d-measure-cancel-pt" onClick={() => setPending(null)}>
              Cancelar punto
            </button>
          )}
        </div>
      )}

      {/* ── Panel de mediciones (lateral) ── */}
      {showMPanel && (
        <div className="r3d-mpanel">
          <div className="r3d-mpanel-header">
            <span>📏 Mediciones</span>
            <button className="r3d-mpanel-close" onClick={() => setShowMPanel(false)}>✕</button>
          </div>

          {measurements.length === 0 ? (
            <p className="r3d-mpanel-empty">
              {measureMode ? 'Toca dos puntos en el modelo' : 'Sin mediciones'}
            </p>
          ) : (
            <div className="r3d-mpanel-list">
              {measurements.map(m => (
                <div key={m.id} className="r3d-mpanel-item">
                  <div className="r3d-mpanel-dist">{m.dist.toFixed(2)} m</div>
                  {editingId === m.id ? (
                    <div className="r3d-mpanel-edit-row">
                      <input
                        className="r3d-mpanel-input"
                        value={editLabel}
                        onChange={e => setEditLabel(e.target.value)}
                        onKeyDown={e => e.key === 'Enter' && saveEdit(m.id)}
                        autoFocus
                      />
                      <button className="r3d-mpanel-save" onClick={() => saveEdit(m.id)}>✓</button>
                    </div>
                  ) : (
                    <div className="r3d-mpanel-label-row">
                      <span className="r3d-mpanel-label" onClick={() => startEdit(m)}>{m.label}</span>
                      <button className="r3d-mpanel-del" onClick={() => deleteMeasure(m.id)}>🗑</button>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}

          {measurements.length > 0 && (
            <div className="r3d-mpanel-footer">
              <button className="r3d-mpanel-export" onClick={handleAccept}>
                Añadir al presupuesto →
              </button>
              <button className="r3d-mpanel-clear"
                onClick={() => { setMeasurements([]); setPending(null) }}>
                Borrar todo
              </button>
            </div>
          )}
        </div>
      )}

      {/* ── Panel capas ── */}
      {showLayers && (
        <div className="r3d-layers">
          {[
            { key: 'furniture', icon: '🛋', label: 'Muebles'  },
            { key: 'ceil',      icon: '🏠', label: 'Techo'    },
            { key: 'measures',  icon: '📐', label: 'Medidas'  },
            { key: 'textures',  icon: '🖼', label: 'Texturas' },
          ].map(({ key, icon, label }) => (
            <button key={key}
              className={`r3d-layer-btn ${layers[key] ? 'on' : ''}`}
              onClick={() => toggleLayer(key)}>
              <span>{icon}</span>
              <span>{label}</span>
              <span className="r3d-eye">{layers[key] ? '👁' : '🚫'}</span>
            </button>
          ))}
        </div>
      )}

      {/* ── Botón recorrido ── */}
      <button className={`r3d-walk-btn ${walkMode ? 'active' : ''}`}
        onClick={() => setWalkMode(v => !v)}>
        {walkMode ? '⏹ Salir' : '🚶 Recorrido'}
      </button>

      {walkMode && <VirtualJoystick joystickRef={joystick} />}

      {/* ── Barra inferior ── */}
      <div className="r3d-bar">
        {[
          { id: 'measure', icon: '📏', label: 'Medir'    },
          { id: 'plan',    icon: '🗺',  label: 'Plano 2D' },
          { id: 'export',  icon: '⬆',  label: 'Exportar' },
          { id: 'comment', icon: '💬', label: 'Nota'     },
          { id: 'video',   icon: '🎬', label: 'Vídeo'    },
        ].map(({ id, icon, label }) => (
          <button key={id}
            className={`r3d-bar-btn ${activeBar === id ? 'active' : ''}`}
            onClick={() => {
              if (id === 'measure') { toggleMeasure(); return }
              if (id === 'export')  { setShowExport(v => !v); return }
              setActiveBar(v => v === id ? null : id)
            }}>
            <span className="r3d-bar-icon">
              {id === 'measure' && measurements.length > 0
                ? <span style={{ position:'relative' }}>
                    {icon}
                    <span className="r3d-bar-badge">{measurements.length}</span>
                  </span>
                : icon}
            </span>
            <span className="r3d-bar-label">{label}</span>
          </button>
        ))}
      </div>

      {/* ── Botón aceptar ── */}
      <button className="r3d-accept-btn" onClick={handleAccept}>
        Continuar →
      </button>

      {/* ── Métricas ── */}
      <div className="r3d-metrics">
        <div className="r3d-metric">{(result?.floorArea ?? 0).toFixed(1)} m²</div>
        {result?.wallCount > 0 && (
          <div className="r3d-metric">{result.wallCount} paredes</div>
        )}
      </div>

      {/* ── Menú exportar 3D ── */}
      {showExport && (
        <div className="r3d-export-menu">
          <div className="r3d-export-title">Exportar modelo</div>

          <button className="r3d-export-opt" onClick={handleExportAR}>
            <span className="r3d-export-icon">📱</span>
            <div>
              <div className="r3d-export-name">AR Quick Look</div>
              <div className="r3d-export-desc">USDZ paramétrico · AirDrop · Archivos · Notas</div>
            </div>
          </button>

          <button className="r3d-export-opt" onClick={handleExportMesh}>
            <span className="r3d-export-icon">🧊</span>
            <div>
              <div className="r3d-export-name">Malla 3D (Blender / SketchUp)</div>
              <div className="r3d-export-desc">USDZ malla cruda · AutoCAD · converters</div>
            </div>
          </button>

          <button className="r3d-export-cancel" onClick={() => setShowExport(false)}>
            Cancelar
          </button>
        </div>
      )}

      {exporting && (
        <div className="r3d-exporting">
          {exporting === 'mesh' ? 'Exportando malla 3D…' : 'Exportando AR USDZ…'}
        </div>
      )}
    </div>
  )
}
