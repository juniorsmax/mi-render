# LiDAR iOS — Lista Técnica Completa
> Documento en progreso — se actualiza por partes

---

## 1. Reconstrucción de entorno en tiempo real

**API:** `ARWorldTrackingConfiguration.sceneReconstruction`

```swift
let config = ARWorldTrackingConfiguration()
config.sceneReconstruction = .meshWithClassification
session.run(config)
```

Permite:
- Mesh 3D
- Clasificación de superficies
- Volumen espacial
- Detección de obstáculos

---

## 2. Detección de superficies horizontales y verticales

```swift
config.planeDetection = [.horizontal, .vertical]
```

Detecta:
- Suelo
- Paredes
- Mesas
- Techos

---

## 3. Depth map — acceso píxel por píxel

```swift
config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
```

Permite:
- Mediciones precisas
- Detección volumétrica
- Mapas térmicos
- Visión artificial

---

## 4. Acceso nube de puntos LiDAR

```swift
frame.sceneDepth?.depthMap
```

Uso:
- Detección de colisiones
- Tracking de objetos
- IA espacial

---

## 5. Clasificación semántica de superficies

```swift
.meshWithClassification
```

Clasifica:
- `floor`
- `wall`
- `ceiling`
- `seat`
- `table`
- `window`
- `door`

---

## 6. RoomPlan — escaneo estructural automático

```swift
let session = RoomCaptureSession()
session.run(configuration: .init())
```

Genera:
- Paredes
- Ventanas
- Puertas
- Dimensiones
- Estructura

Exportación:
```swift
CapturedRoom.export(to: url)
```
Formato: **USDZ**

---

## 7. Generación automática de planos 2D

Posible vía RoomPlan.

```swift
roomCaptureSession.delegate = self
```

Pipeline:
1. `RoomPlan` → escaneo
2. `CapturedRoom` → estructura
3. Extracción de paredes: `capturedRoom.walls`
4. Construcción de plano: `wall.transform` + `wall.dimensions`
5. Exportación DXF → requiere conversión externa

Pipeline completo:
```
RoomPlan → CapturedRoom → ModelIO → DXF exporter
```

---

---

## 8. Reconstrucción de objetos 3D

```swift
config.sceneReconstruction = .mesh
// Acceso al mesh
// ARMeshAnchor
anchor.geometry.vertices  // vértices
anchor.geometry.faces     // caras
```

Construcción de modelo con ModelIO:
```swift
MDLMesh
```

Exportación: **OBJ / USDZ / PLY**

---

## 9. Texturizado automático

```swift
config.environmentTexturing = .automatic
```

Permite:
- Captura de color real
- Render físico realista
- Oclusión correcta en AR

---

## 10. Oclusión realista

```swift
arView.environment.sceneUnderstanding.options.insert(.occlusion)
```

Permite:
- Objetos virtuales detrás de objetos reales

---

## 11. Exportación profesional de modelos 3D

**Framework:** ModelIO

Pipeline:
```
ARMeshAnchor → MDLMesh → MDLAsset → export
```

```swift
let asset = MDLAsset()
asset.add(mesh)
asset.export(to: url)
```

Formatos compatibles:
- USDZ
- OBJ
- PLY
- STL
- GLTF (mediante conversión externa)

---

## 12. Generación de Digital Twin

Pipeline:
```
mesh reconstruction → clasificación superficies → exportación USDZ
```

Uso: arquitectura, inmobiliaria, metaverso técnico

---

## 13. Medición automática de distancias

```swift
raycastQuery(from:allowing:alignment:)
```

Resultado: distancia exacta entre puntos

---

## 14. Medición volumétrica

Pipeline: `depthMap` + `bounding box`

```swift
depthData.depthMap
```

Permite calcular volumen de objetos

---

## 15. Detección de personas

```swift
config.frameSemantics.insert(.personSegmentation)
```

Uso: apps fitness, rehabilitación, tracking corporal

---

## 16. Tracking de movimiento espacial

```swift
ARBodyTrackingConfiguration()
```

Detecta: posición corporal completa

---

## 17. Generación de mapas de navegación interior

Pipeline: mesh reconstruction → pathfinding

Framework adicional: `GameplayKit`

Uso: navegación indoor

---

## 18. Exportación BIM

RoomPlan provee la base BIM.

Pipeline:
```
CapturedRoom → USDZ → Conversión IFC externa
```

---

## 19. Conversión CAD

Pipeline:
```
mesh → ModelIO → OBJ → DXF converter externo
```

---

## 20. Generación de planos arquitectónicos automáticos

Pipeline real usado en la industria:
```
RoomPlan → CapturedRoom → wall extraction → vectorización → DXF export
```

Detalle:
```swift
capturedRoom.walls          // extracción paredes
wall.dimensions             // dimensiones
wall.transform              // coordenadas
// Construcción plano vectorial → CoreGraphics
```

---

## 21. Errores frecuentes en desarrollo LiDAR

| Error | Solución |
|-------|----------|
| No validar soporte mesh | `ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)` |
| Ejecutar en simulador | LiDAR no funciona en simulador, solo dispositivo real |
| No activar permisos cámara | Añadir `NSCameraUsageDescription` en Info.plist |
| No limpiar anchors antiguos | `session.remove(anchor:)` — produce crash de memoria |
| No optimizar resolución mesh | Produce caída de FPS |

---

## 22. Optimización de memoria profesional

```swift
session.currentFrame?.anchors   // revisar anchors activos
session.remove(anchor:)         // eliminar antiguos
```

Simplificación de mesh con ModelIO:
```swift
MDLMeshBuffer  // reducir densidad del mesh
```

---

## 23. Pipeline profesional — arquitectura multimodo

```
ScanManager       → controla sesiones ARKit/RoomPlan
MeshManager       → gestiona y simplifica mesh
ExportManager     → gestiona exportación (OBJ/USDZ/PLY/STL)
DepthManager      → gestiona depthMap pixel a pixel
RoomPlanManager   → gestiona habitaciones con RoomPlan
MeasurementManager→ gestiona mediciones y distancias
```

---

## 24. Cómo lo implementan las apps profesionales

| App | Técnica principal |
|-----|------------------|
| **Polycam** | mesh reconstruction + export OBJ |
| **MagicPlan** | RoomPlan + plano 2D automático |
| **IKEA Place** | plane detection + occlusion |
| **Scaniverse** | point cloud processing |

---

## 25. Texturas físicas realistas (PBR)

RealityKit soporta materiales PBR:

```swift
PhysicallyBasedMaterial()
// roughness, metallic, normal maps
```

---

## 26. Integración con Metal GPU

Framework: `MetalKit`

Uso: render de alto rendimiento, procesamiento de mesh en GPU

---

## 27. Mejoras avanzadas implementables

- **LOD dinámico** — reducción de vértices con `MDLMesh`
- **Compresión de nube de puntos**
- **Detección de materiales** — CoreML
- **Clasificación automática de objetos** — Vision framework

---

## 28. Lo que no te han preguntado pero deberías considerar

### Persistencia y sesiones
- **Guardar mapa del entorno:** `ARWorldMap` — permite retomar escaneos
- **Multiusuario AR:** `ARCollaborationData` — escaneo colaborativo
- **Streaming mesh en tiempo real** — sincronización en nube
- **Versionado de escaneos** — historial de cambios del entorno
- **Exportación incremental de mesh**
- **Re-scan inteligente** — detección de cambios en entorno

### Precisión y calibración
- **Detección de iluminación:** `lightEstimate` — calibración automática de color
- **Calibración automática de escala**
- **Detección de bordes estructurales**
- **Registro SLAM persistente** — tracking indoor sin GPS

### Rendimiento y estabilidad
- **Optimización de batería** — control de temperatura del sensor
- **Gestión de sesiones largas**
- **Gestión de memoria GPU**
- **Fallback sin LiDAR** — dispositivos sin sensor (iPhone 11 y anteriores)

### Reconstrucción avanzada
- **Reconstrucción parcial incremental** — no requiere escaneo completo
- **Tracking sin GPS indoor** (SLAM puro)

---

## 29. Pipelines recomendados por objetivo

### Planos arquitectónicos profesionales (CAD-ready)
```
RoomPlan → CapturedRoom → ModelIO → CoreGraphics → DXF exporter externo
```
Produce plano arquitectónico usable en CAD.

### Escaneo de objetos para impresión 3D
```
mesh reconstruction → ModelIO → STL export
```

### Digital Twin profesional completo
```
scene reconstruction → classification → texturing → export USDZ → cloud sync
```

---

---

## 30. Arquitectura profesional — App LiDAR multimodo

Estructura recomendada del proyecto Xcode:

```
LiDARApp/
├── App/
├── Managers/
│   ├── ScanManager.swift          → controla sesión LiDAR completa
│   ├── MeshManager.swift          → gestiona y simplifica mesh
│   ├── DepthManager.swift         → gestiona depthMap
│   ├── RoomPlanManager.swift      → habitaciones con RoomPlan
│   ├── MeasurementManager.swift   → mediciones y distancias
│   ├── ExportManager.swift        → exportación multi-formato
│   ├── WorldMapManager.swift      → persistencia espacial ARWorldMap
│   ├── CollaborationManager.swift → multiusuario ARCollaborationData
│   ├── AIManager.swift            → CoreML + Vision
│   └── NavigationManager.swift   → navegación indoor
├── Render/
│   ├── ARViewContainer.swift      → contenedor SwiftUI del ARView
│   ├── MeshRenderer.swift         → renderizado del mesh
│   └── PlanRenderer.swift         → renderizado plano 2D
├── Models/
│   ├── CapturedMesh.swift         → modelo de datos del mesh
│   ├── CapturedRoomModel.swift    → modelo de habitación
│   └── MeasurementModel.swift     → modelo de medición
└── Utilities/
    ├── FileConverter.swift        → conversiones de formato
    ├── MeshOptimizer.swift        → LOD, simplificación, compresión
    └── CoordinateConverter.swift  → conversión de coordenadas AR↔mundo
```

---

### ScanManager.swift — motor base del escaneo universal

```swift
import ARKit
import RealityKit

class ScanManager {

    static let shared = ScanManager()

    var session: ARSession?

    func startFullScan(arView: ARView) {

        session = arView.session

        let config = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }

        config.environmentTexturing = .automatic

        config.frameSemantics = [
            .sceneDepth,
            .smoothedSceneDepth
        ]

        config.planeDetection = [
            .horizontal,
            .vertical
        ]

        arView.session.run(config)
    }
```

Activa simultáneamente: mesh 3D, clasificación de superficies, depth map y detección de planos. Es la base profesional.

---

### MeshManager.swift — extracción de geometría real

```swift
import ARKit
import ModelIO

class MeshManager {

    func extractMesh(from anchor: ARMeshAnchor) -> MDLMesh {

        let geometry = anchor.geometry

        let vertexBuffer = geometry.vertices.buffer

        let vertexCount = geometry.vertices.count

        let vertexDescriptor = MDLVertexDescriptor()

        let allocator = MTKMeshBufferAllocator(device: MTLCreateSystemDefaultDevice()!)

        let mesh = MDLMesh(
            vertexBuffer: allocator.newBuffer(with: vertexBuffer.contents(),
                                              length: vertexBuffer.length,
                                              type: .vertex),
            vertexCount: vertexCount,
            descriptor: vertexDescriptor,
            submeshes: nil
        )

        return mesh
    }
```

Permite exportación directa a OBJ o USDZ.

---

### RoomPlanManager.swift — generador de planos 2D

```swift
import RoomPlan

class RoomPlanManager: NSObject {

    var captureSession = RoomCaptureSession()

    func startScanning() {

        let configuration = RoomCaptureSession.Configuration()

        captureSession.run(configuration: configuration)
    }

    func exportRoom(to url: URL) {

        captureSession.stop()

        if let room = captureSession.capturedRoom {
            try? room.export(to: url)
        }
    }
```

Genera automáticamente estructura arquitectónica.

---

### PlanRenderer.swift — plano 2D vectorial desde paredes

```swift
import CoreGraphics
import RoomPlan

class PlanRenderer {

    func generatePlan(from room: CapturedRoom) -> CGMutablePath {

        let path = CGMutablePath()

        for wall in room.walls {

            let transform = wall.transform

            let dimensions = wall.dimensions

            let startPoint = CGPoint(
                x: CGFloat(transform.columns.3.x),
                y: CGFloat(transform.columns.3.z)
            )

            let endPoint = CGPoint(
                x: startPoint.x + CGFloat(dimensions.x),
                y: startPoint.y
            )

            path.move(to: startPoint)

            path.addLine(to: endPoint)
        }

        return path
    }
```

Crea el plano arquitectónico base a partir de las paredes reales.

---

### ExportManager.swift — exportación multiformato profesional

```swift
import ModelIO

class ExportManager {

    func exportOBJ(mesh: MDLMesh, url: URL) {

        let asset = MDLAsset()

        asset.add(mesh)

        try? asset.export(to: url)
    }
```

El mismo método `exportOBJ` puede adaptarse cambiando la extensión de la URL a: `.usdz`, `.obj`, `.ply`, `.stl`

---

### MeasurementManager.swift — medición profesional

```swift
import ARKit

class MeasurementManager {

    func measureDistance(from pointA: SIMD3<Float>,
                         to pointB: SIMD3<Float>) -> Float {

        return simd_distance(pointA, pointB)
    }
```

Precisión típica en interior: **±5 mm**

---

### WorldMapManager.swift — persistencia espacial del entorno

```swift
import ARKit

class WorldMapManager {

    func saveWorldMap(session: ARSession,
                      completion: @escaping (ARWorldMap?) -> Void) {

        session.getCurrentWorldMap { worldMap, error in

            completion(worldMap)
        }
    }
```

Permite guardar y restaurar el mapa espacial — base para multiusuario y re-scan.

---

### NavigationManager.swift — navegación indoor sin GPS

```swift
import GameplayKit

class NavigationManager {

    func createPathGraph(points: [vector_float3]) -> GKGraph {

        let nodes = points.map { GKGraphNode3D(point: $0) }

        return GKGraph(nodes: nodes)
    }
```

Genera grafos de rutas interiores sin GPS.

---

### MeshRenderer.swift — materiales físicos realistas PBR

```swift
import RealityKit

class MeshRenderer {

    func createMaterial() -> PhysicallyBasedMaterial {

        var material = PhysicallyBasedMaterial()

        material.roughness = .float(0.5)

        material.metallic = .float(0.2)

        return material
    }
```

Permite render físico realista con roughness y metallic configurables.

---

### Texturizado automático del entorno

```swift
config.environmentTexturing = .automatic
```

Captura iluminación real del entorno. Sin código adicional.

---

### Exportación CAD / DXF

Pipeline recomendado:
```
CapturedRoom → extraer paredes → convertir coordenadas → generar líneas → exportar DXF (librería externa)
```

Conversión de coordenadas de pared:
```swift
let transform = wall.transform
let width     = wall.dimensions.x
let height    = wall.dimensions.y
```

---

## 31. Lo más importante que casi nadie implementa

### Diferenciadores profesionales clave

| Función | Impacto |
|---------|---------|
| Guardado incremental del mesh | No pierde trabajo si la app se cierra |
| Detección de cambios en entorno | Re-scan inteligente solo donde cambia |
| Reconstrucción parcial | No requiere escanear de nuevo todo |
| LOD dinámico | Reduce carga GPU sin perder calidad visible |
| Optimización de anchors antiguos | Evita crashes en sesiones largas |
| Streaming de nube de puntos | Sincronización en tiempo real con servidor |
| Exportación progresiva | El usuario puede exportar mientras escanea |
| Multiusuario sincronizado | `ARCollaborationData` — varios dispositivos, un mapa |
| Persistencia de sesiones largas | `ARWorldMap` serializado a disco |
| Fallback automático sin LiDAR | Degradación elegante en iPhone 11 y anteriores |
| Detección de iluminación | `lightEstimate` — calibración automática de color |
| Estimación de materiales | CoreML sobre depth map |
| Detección de colisiones físicas | Para simulaciones o robótica |
| Registro histórico de escaneos | Versionado temporal del espacio |
| Versionado de modelos | Comparar escaneo actual vs anterior |

---

## 32. Funciones adicionales avanzadas (casi nadie integra en v1)

### Verticales de negocio

| Modo / Función | Descripción |
|----------------|-------------|
| **Exportación IFC / BIM** | Formato estándar industria AEC — requiere conversor externo |
| **Detección de mobiliario automática** | RoomPlan clasifica `seat`, `table`, `storage`, etc. |
| **Clasificación de materiales con CoreML** | Modelo entrenado sobre depth map + RGB |
| **Mapa de navegación accesibilidad** | Rutas para silla de ruedas, alturas, obstáculos |
| **Detección de obstáculos para personas ciegas** | Audio espacial + mesh classification |
| **Modo escaneo rápido vs escaneo preciso** | Resolución de mesh configurable |
| **Modo offline vs cloud sync** | Escaneo local + sincronización diferida |
| **Modo escaneo continuo tipo SLAM** | Sesión indefinida con optimización continua |
| **Modo inspección técnica de edificios** | Captura de defectos, grietas, humedades con IA |
| **Modo inventario de almacenes** | Conteo y volumen de cajas y palés |
| **Modo cálculo de volumen automático** | Bounding box 3D → m³ de cualquier objeto |

---

<!-- PENDIENTE: continúa aquí -->



