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

import { Suspense, useRef, useState, useEffect, useCallback } from 'react'
import { Canvas, useFrame, useThree } from '@react-three/fiber'
import {
  OrbitControls,
  PerspectiveCamera,
  Html,
  Environment,
  ContactShadows,
} from '@react-three/drei'
import * as THREE from 'three'
import { exportUSDZ, openViewer } from '../lib/lidar'
import { Capacitor } from '@capacitor/core'
import './Room3DView.css'

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

  // Calcular bbox del suelo para centrarlo en escena
  const floorW = result?.floorArea ? Math.sqrt(result.floorArea) * 1.2 : 4
  const floorD = floorW

  return (
    <group>
      {/* Suelo */}
      <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
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
  const transform = wall.transform  // simd_float4x4 → array 16 floats col-major
  const dimX = wall.dimensions?.[0] ?? wall.width  ?? 3
  const dimY = wall.dimensions?.[1] ?? height
  const dimZ = wall.dimensions?.[2] ?? 0.2

  const matrix = transform ? buildMatrix(transform) : null

  return (
    <mesh castShadow receiveShadow matrixAutoUpdate={false}
      ref={el => { if (el && matrix) el.matrix.copy(matrix) }}>
      <boxGeometry args={[dimX, dimY, Math.max(dimZ, 0.12)]} />
      <meshStandardMaterial color={WALL_COLOR} roughness={0.85} metalness={0} />
    </mesh>
  )
}

// Superficie genérica (puerta/ventana)
function SurfaceMesh({ surface, color, opacity }) {
  const transform = surface.transform
  const dimX = surface.dimensions?.[0] ?? surface.width  ?? 1
  const dimY = surface.dimensions?.[1] ?? surface.height ?? 2
  const dimZ = surface.dimensions?.[2] ?? 0.1
  const matrix = transform ? buildMatrix(transform) : null

  return (
    <mesh matrixAutoUpdate={false}
      ref={el => { if (el && matrix) el.matrix.copy(matrix) }}>
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

// ─── Componente principal ────────────────────────────────────────────────────

export function Room3DView({ result, projectName = 'Habitación', onBack, onAccept }) {
  const orbitRef   = useRef()
  const joystick   = useRef({ x: 0, y: 0 })

  const [walkMode,   setWalkMode]   = useState(false)
  const [floorType,  setFloorType]  = useState('parquet')  // 'parquet' | 'tile'
  const [showLayers, setShowLayers] = useState(false)
  const [layers, setLayers] = useState({
    furniture: true,
    ceil:      false,
    measures:  false,
    textures:  false,
  })
  const [activeBar, setActiveBar] = useState(null)  // 'measure'|'plan'|'export'|'comment'|'video'
  const [exporting,  setExporting] = useState(false)

  // Toggle individual de capa
  function toggleLayer(key) {
    setLayers(prev => ({ ...prev, [key]: !prev[key] }))
  }

  // Reset a vista top-down
  function resetCamera() {
    if (!orbitRef.current) return
    orbitRef.current.reset()
    orbitRef.current.setAzimuthalAngle(0)
    orbitRef.current.setPolarAngle(0.1)
    orbitRef.current.object.position.set(0, 12, 0.1)
    orbitRef.current.target.set(0, 0, 0)
    orbitRef.current.update()
  }

  // Exportar USDZ
  async function handleExportUSDZ() {
    setExporting(true)
    try {
      await exportUSDZ({ name: projectName })
    } catch { /* silencio */ }
    setExporting(false)
  }

  // Abrir visor nativo
  async function handleOpenNativeViewer() {
    try { await openViewer({}) } catch { /* silencio */ }
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
          {/* Toggle suelo */}
          <button className="r3d-btn-sm" onClick={() => setFloorType(f => f === 'parquet' ? 'tile' : 'parquet')}>
            {floorType === 'parquet' ? '🪵' : '⬜'}
          </button>
          {/* Reset cámara top-down */}
          <button className="r3d-btn-sm" onClick={resetCamera}>⊙</button>
          {/* Toggle layers */}
          <button className="r3d-btn-sm r3d-btn-active" onClick={() => setShowLayers(v => !v)}>
            ⊞
          </button>
        </div>
      </div>

      {/* ── Canvas 3D ── */}
      <div className="r3d-canvas-wrap">
        <Canvas shadows dpr={[1, 2]}
          gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping }}>
          <color attach="background" args={['#ddeeff']} />
          <fog attach="fog" args={['#ddeeff', 15, 35]} />

          <StudioLights />

          <Suspense fallback={null}>
            <DollhouseScene result={result} layers={layers} floorType={floorType} />
          </Suspense>

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
                />
              </>
          }
        </Canvas>
      </div>

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

      {/* ── Botón recorrido (primera persona) ── */}
      <button className={`r3d-walk-btn ${walkMode ? 'active' : ''}`}
        onClick={() => setWalkMode(v => !v)}>
        {walkMode ? '⏹ Salir' : '🚶 Recorrido'}
      </button>

      {/* Joystick en modo recorrido */}
      {walkMode && <VirtualJoystick joystickRef={joystick} />}

      {/* ── Barra inferior estilo Polycam ── */}
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
              setActiveBar(v => v === id ? null : id)
              if (id === 'export') handleExportUSDZ()
            }}>
            <span className="r3d-bar-icon">{icon}</span>
            <span className="r3d-bar-label">{label}</span>
          </button>
        ))}
      </div>

      {/* ── Botón aceptar / continuar ── */}
      <button className="r3d-accept-btn" onClick={onAccept}>
        Continuar →
      </button>

      {/* ── Métricas flotantes (esquina superior derecha) ── */}
      <div className="r3d-metrics">
        <div className="r3d-metric">{(result?.floorArea ?? 0).toFixed(1)} m²</div>
        {result?.wallCount > 0 && (
          <div className="r3d-metric">{result.wallCount} paredes</div>
        )}
      </div>

      {exporting && (
        <div className="r3d-exporting">Exportando USDZ…</div>
      )}
    </div>
  )
}
