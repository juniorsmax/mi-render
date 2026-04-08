# mi-render — Resumen del Proyecto

**App ID:** `com.zerbitecni.mirender`  
**Stack:** React 19 + Vite + Capacitor 8 + Swift / RoomPlan / ARKit  
**Empresa:** Zerbitecni  
**Fecha de resumen:** 2026-04-08

---

## Qué es mi-render

Aplicación híbrida web/iOS para **medir habitaciones** con cámara o LiDAR y **generar presupuestos** exportables en Word, PDF y Excel. Orientada a reformistas, decoradores y técnicos de construcción.

---

## Arquitectura general

```
mi-render/
├── src/                  → App React (SPA, Vite)
│   ├── App.jsx           → Shell principal, estado global, router de flujos
│   ├── components/       → Componentes reutilizables
│   ├── views/            → Vistas por pestaña
│   ├── hooks/            → Custom hooks (cámara, WebXR)
│   ├── lib/              → Lógica de negocio (LiDAR, exportadores, seguridad)
│   └── i18n/             → Traducciones ES / EN / IT
├── ios/App/App/          → Código Swift nativo
│   ├── LiDARPlugin.swift → Plugin Capacitor con RoomPlan + ARKit
│   ├── AppDelegate.swift → Delegado iOS
│   └── Info.plist        → Permisos (cámara, ubicación, fotos)
├── capacitor.config.json → Config Capacitor (appId, plugins)
├── vite.config.js        → Build config + HTTPS local
└── package.json          → Dependencias y scripts
```

---

## Archivos creados

### src/

| Archivo | Descripción |
|---------|-------------|
| `main.jsx` | Punto de entrada React, monta `<App />` en `#root` |
| `App.jsx` | Estado global: tab activa, flujo modal (scan/manual/budget), proyectos guardados |
| `index.css` | Design system: tokens de color amber/negro, glass-morphism, tipografía SF Pro |
| `components/BottomNav.jsx` | Barra inferior con 5 tabs + FAB central de creación |
| `components/CreateSheet.jsx` | Modal deslizable con 6 opciones de creación |
| `components/ExportButtons.jsx` | Botones Word / PDF / Excel con estados de carga |
| `components/ScanExport.jsx` | Pantalla de resultados: plano 2D + estadísticas + acciones |
| `components/FloorPlan.jsx` | Canvas 2D que renderiza paredes, puertas, ventanas y brújula N |
| `components/Icon.jsx` | Sistema SVG centralizado (~30 iconos) |
| `components/ServiceRow.jsx` | Fila editable de partida en tabla de presupuesto |
| `components/ARCanvas.jsx` | Canvas WebGL para WebXR (hit-test, reticle, puntos AR) |
| `views/ScanView.jsx` | Flujo completo de escaneo: 6 pasos (permission → scanning → corners → scale → manual → result) |
| `views/BudgetView.jsx` | Editor de presupuesto: partidas, IVA, totales, exportación |
| `views/ProjectsView.jsx` | Lista de proyectos guardados con filtros (recent / all) |
| `views/ExploreView.jsx` | Guía de precios y tutoriales |
| `views/ProfileView.jsx` | Perfil, selector de idioma, configuración, billing |
| `hooks/useCamera.js` | `getUserMedia` con fallbacks y manejo de errores iOS |
| `hooks/useXRSession.js` | Gestión de sesión WebXR immersive-ar |
| `hooks/useHitTest.js` | Hit-test WebXR: rastrea puntos en espacio 3D |
| `lib/lidar.js` | Bridge JS→Swift: detecta capacidades, despacha RoomPlan o ARKit |
| `lib/shoelace.js` | Fórmula de Gauss para calcular área de polígono 2D |
| `lib/security.js` | Sanitización XSS, validación numérica, `safeStorage` con prefijo `mr_` |
| `lib/exportWord.js` | Genera `.docx` con tabla de partidas y datos de cliente |
| `lib/exportPdf.js` | Genera `.pdf` con header, tabla y footer de marca |
| `lib/exportExcel.js` | Genera `.xlsx` con estructura de presupuesto |
| `i18n/index.jsx` | Proveedor de contexto + hook `useLang()` |
| `i18n/es.js` | Traducciones en español |
| `i18n/en.js` | Traducciones en inglés |
| `i18n/it.js` | Traducciones en italiano |

### ios/App/App/

| Archivo | Descripción |
|---------|-------------|
| `LiDARPlugin.swift` | Plugin Capacitor con tres clases: `LiDARPlugin`, `RoomPlanViewController`, `ObjectScanViewController` |
| `AppDelegate.swift` | Delegado de aplicación iOS estándar |
| `Info.plist` | Permisos: cámara, micrófono, fotos, ubicación. `UIFileSharingEnabled = true` |

---

## Funciones de la app

### 1. Escaneo LiDAR nativo (iOS 16+, iPhone 12 Pro+)
- Lanza `RoomPlanViewController` en Swift
- Usa el framework `RoomPlan` de Apple
- El usuario mueve el iPhone por la habitación
- Devuelve: paredes, puertas, ventanas, aberturas, área m², perímetro, volumen, coordenadas GPS
- Exporta automáticamente un archivo `.usdz` del modelo 3D
- Compatible con iPad Pro 2020+ con LiDAR

### 2. Escaneo de objetos 3D (ARKit .mesh)
- Lanza `ObjectScanViewController` en Swift
- Usa `ARWorldTrackingConfiguration` con `sceneReconstruction = .mesh`
- Renderiza malla 3D en tiempo real
- Auto-captura a los 15 segundos o manual
- Devuelve: caras, vértices, dimensiones, bounding box, nivel de confianza

### 3. Escaneo por cámara + marcado manual
- Accede a cámara con `getUserMedia` (hook `useCamera`)
- Video fullscreen, el usuario toca las esquinas del suelo
- Calibración de escala: marca 2 puntos de pared conocida e introduce la distancia real
- Calcula área con la fórmula de Shoelace

### 4. Entrada manual directa
- Formulario: nombre de la estancia, ancho (m), largo (m)
- Calcula `areaSqM = ancho × largo`

### 5. Presupuesto Zerbitecni
- Recibe los datos del escaneo (área, nombre de estancia)
- Datos del cliente: empresa, nombre, fecha
- Tabla de partidas editable: descripción, unidad, precio unitario, cantidad, subtotal
- Cálculo automático de IVA (% configurable)
- Total neto + total con IVA

### 6. Exportación de presupuesto
- **Word (.docx):** tabla con partidas, header con cliente, IVA calculado
- **PDF (.pdf):** header oscuro con logo, tabla estilizada, footer de marca
- **Excel (.xlsx):** hoja con metadatos (cliente, fecha, m²) + filas de partidas

### 7. Plano 2D
- Canvas `<canvas>` puro que renderiza la geometría de la habitación
- Dibuja paredes, puertas, ventanas y brújula de orientación (N)

### 8. Multiidioma
- Español, Inglés, Italiano
- Selector en pantalla Profile
- Contexto global, todas las cadenas de texto traducidas

### 9. Gestión de proyectos
- Lista de proyectos guardados en memoria de sesión
- Filtros: recientes / todos
- Tarjeta con nombre, área m², fecha y tipo (scan / manual)

### 10. Seguridad
- Sanitización XSS en todos los inputs de texto
- Validación numérica con rangos (min/max)
- `localStorage` con prefijo `mr_` y manejo de errores silenciosos

---

## Flujos principales

```
[Crear proyecto]
  ↓
CreateSheet
  ├── Scan LiDAR    → LiDARPlugin (Swift) → ScanExport → BudgetView
  ├── Scan cámara   → useCamera → corners → scale → ScanExport → BudgetView
  ├── Manual        → form ancho×largo → BudgetView
  ├── Foto          → (próximamente)
  ├── Plano         → (próximamente)
  └── Subir archivo → (próximamente)

[BudgetView]
  → Editar partidas → calcular totales → exportar Word/PDF/Excel → guardar proyecto
```

---

## Historial de desarrollo (commits clave)

| Commit | Descripción |
|--------|-------------|
| `8f9fdef` | App inicial — WebXR scanner + generador de presupuestos Zerbitecni |
| `bc94c75` | TAREAS.md — tracker de tareas del proyecto |
| `e52969d` | Plataforma Capacitor iOS añadida |
| `06f1471` | GitHub Actions — workflow de build iOS (Xcode 16) |
| `68780dd` | CI — build .ipa sin firma para dispositivo real |
| `b1d5009` | Iconos SVG, bridge LiDAR, capa de seguridad, mejoras UI |
| `473aefa` | Plugin Swift LiDAR con RoomPlan |
| `f179def` | Permiso cámara WKWebView — CAPBridgeViewController |
| `e88a1f6` | Info.plist completo: cámara, micrófono, fotos, ubicación |
| `399de7d` | UI escáner estilo Polycam completa (Luna+Vera+Ares) |
| `d9f5319` | Plugin LiDAR correctamente registrado en Xcode |
| `73b9a6a` | Plugin LiDAR completo — ARKit + RoomPlan ready |
| `c73b9a6` | Correcciones API RoomPlan — RoomCaptureView + delegate |
| `af5327f` | Fix RoomPlan — floors iOS17+, tipo Confidence corregido |
| `7341759` | Conexión LiDAR nativo + escaneo de objetos 3D ARKit mesh |
| `cab92c7` | Plano 2D + exportación PDF/USDZ + pantalla sin oscurecer |
| `7b5ad29` | Fix API RoomPlan — eliminar propiedades inexistentes |

---

## Estado actual

### Funcionando
- [x] App React con navegación por tabs
- [x] Plugin Swift LiDAR con RoomPlan (iOS 16+)
- [x] Plugin Swift ARKit .mesh para objetos 3D
- [x] Escaneo por cámara con marcado de esquinas
- [x] Entrada manual de dimensiones
- [x] Editor de presupuesto con partidas
- [x] Exportación Word / PDF / Excel
- [x] Plano 2D en canvas
- [x] Multiidioma ES / EN / IT
- [x] Design system glass-morphism amber
- [x] Capa de seguridad (XSS, sanitización, safeStorage)
- [x] GitHub Actions — build iOS unsigned

### Pendiente / En progreso
- [ ] **Persistencia real** — proyectos se pierden al cerrar la app (solo en memoria de sesión); falta integrar localStorage o base de datos en la nube
- [ ] **Autenticación** — no hay login ni usuarios; los proyectos no están vinculados a ninguna cuenta
- [ ] **Opción "Foto"** — escaneo por fotografía (actualmente muestra "próximamente")
- [ ] **Opción "Plano"** — importar plano en imagen (actualmente "próximamente")
- [ ] **Opción "Subir archivo"** — importar PDF/DXF (actualmente "próximamente")
- [ ] **Tab "Team"** — colaboración entre usuarios (no implementado)
- [ ] **Distribución iOS** — firma de código y TestFlight/Sideloadly pendiente
- [ ] **MCP GitHub** — recién instalado, pendiente configurar token
- [ ] **Thumbnails de proyecto** — las tarjetas en ProjectsView no tienen imagen real
- [ ] **Cámara Web/Android** — `useXRSession` listo pero WebXR no está activo en el flujo principal
- [ ] **ExploreView** — contenido de guía de precios y tutoriales no poblado

---

## Dependencias clave

| Paquete | Versión | Uso |
|---------|---------|-----|
| react | 19.2.4 | UI |
| @capacitor/core | 8.3.0 | Bridge nativo |
| @capacitor/ios | 8.3.0 | Build iOS |
| three | 0.183.2 | WebGL 3D |
| jspdf + jspdf-autotable | latest | Exportación PDF |
| xlsx | latest | Exportación Excel |
| docx | latest | Exportación Word |
| vite | 8.0.4 | Build tool |

---

## Comandos útiles

```bash
# Desarrollo web
npm run dev

# Build para iOS
npm run build && npx cap sync ios

# Abrir en Xcode
npx cap open ios

# Linting
npm run lint
```

---

## Notas técnicas

- El Mac de desarrollo es un MacBook 2017 con Monterey — Xcode 14.2 como máximo; builds en GitHub Actions con Xcode 16
- El dispositivo de prueba es iPhone 16 Pro Max (LiDAR disponible)
- La instalación de builds se hace con **Sideloadly** hasta tener cuenta de desarrollador pagada
- El plugin LiDAR requiere framework `RoomPlan` enlazado manualmente en Xcode (Build Phases → Link Binary With Libraries)
- WebXR (`useXRSession`, `useHitTest`, `ARCanvas`) está construido pero no conectado al flujo principal aún
