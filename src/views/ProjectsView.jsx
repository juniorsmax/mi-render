import { useState, useEffect, useRef } from 'react'
import { Capacitor } from '@capacitor/core'
import { useLang } from '../i18n/index.jsx'
import { listProjects, openViewer, deleteProject as deleteNativeProject } from '../lib/lidar.js'
import './ProjectsView.css'

const RECENT_COUNT = 5

/**
 * ProjectsView — listado de proyectos con:
 *  - Búsqueda y filtros (recientes / todos)
 *  - Eliminar con modal de confirmación
 *  - Exportar proyecto como .json
 *  - Importar proyecto desde .json
 *  - Ver modelo 3D nativo (USDZ)
 */
export function ProjectsView({ projects, onOpen, onDelete, onExport, onImport }) {
  const { t } = useLang()
  const importRef = useRef(null)

  const [filter,          setFilter]        = useState('recent')
  const [search,          setSearch]        = useState('')
  const [showSearch,      setShowSearch]    = useState(false)
  const [nativeProjects,  setNativeProjects] = useState([])
  const [loadingNative,   setLoadingNative]  = useState(false)
  const [confirmDelete,   setConfirmDelete]  = useState(null)   // { id, name, isNative }
  const [importError,     setImportError]    = useState(null)
  const [importSuccess,   setImportSuccess]  = useState(false)

  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return
    loadNativeProjects()
  }, [])

  async function loadNativeProjects() {
    setLoadingNative(true)
    try {
      const res = await listProjects()
      setNativeProjects(res?.projects ?? [])
    } catch { /* silencio */ }
    finally { setLoadingNative(false) }
  }

  // Fusionar localStorage + nativos sin duplicar
  const localIds = new Set(projects.map(p => String(p.id)))
  const merged = [
    ...projects,
    ...nativeProjects
      .filter(np => !localIds.has(np.id))
      .map(np => ({
        id:        np.id,
        type:      'scan',
        name:      np.name,
        areaSqM:   np.floorArea != null ? +np.floorArea.toFixed(1) : null,
        perimeter: np.perimeter ?? null,
        volume:    np.volume    ?? null,
        createdAt: np.createdAt ?? null,
        date:      np.createdAt ? new Date(np.createdAt).toLocaleDateString('es-ES') : '',
        thumbnail: np.thumbnailBase64 ?? null,
        usdzPath:  np.usdzPath ?? null,
        _native:   true,
      }))
  ]

  const sorted = [...merged].sort((a, b) => {
    const ta = a.createdAt ? new Date(a.createdAt).getTime() : (a.id ? parseInt(a.id, 10) : 0)
    const tb = b.createdAt ? new Date(b.createdAt).getTime() : (b.id ? parseInt(b.id, 10) : 0)
    return tb - ta
  })

  const filtered = search.trim()
    ? sorted.filter(p =>
        (p.name       || '').toLowerCase().includes(search.toLowerCase()) ||
        (p.clientName || '').toLowerCase().includes(search.toLowerCase()) ||
        (p.date       || '').toLowerCase().includes(search.toLowerCase())
      )
    : filter === 'recent' ? sorted.slice(0, RECENT_COUNT) : sorted

  // ── Eliminar ──────────────────────────────────────────────────────
  function askDelete(project, e) {
    e.stopPropagation()
    setConfirmDelete({ id: project.id, name: project.name, isNative: !!project._native })
  }

  async function confirmDeleteProject() {
    if (!confirmDelete) return
    const { id, isNative } = confirmDelete
    if (isNative) {
      try { await deleteNativeProject(id) } catch { /* silencio */ }
      setNativeProjects(prev => prev.filter(p => p.id !== id))
    }
    onDelete?.(id)
    setConfirmDelete(null)
  }

  // ── Exportar ──────────────────────────────────────────────────────
  function handleExport(id, e) {
    e.stopPropagation()
    onExport?.(id)
  }

  // ── Importar ──────────────────────────────────────────────────────
  function triggerImport() {
    setImportError(null)
    importRef.current?.click()
  }

  async function handleImportFile(e) {
    const file = e.target.files?.[0]
    if (!file) return
    e.target.value = ''   // reset para poder reimportar el mismo archivo
    try {
      await onImport?.(file)
      setImportSuccess(true)
      setTimeout(() => setImportSuccess(false), 2500)
    } catch (err) {
      setImportError(err.message || 'Error al importar')
      setTimeout(() => setImportError(null), 4000)
    }
  }

  // ── Abrir visor 3D ────────────────────────────────────────────────
  async function handleOpenViewer(projectId, e) {
    e.stopPropagation()
    try { await openViewer({ projectId }) } catch { /* silencio */ }
  }

  return (
    <div className="page">
      {/* ── Header ── */}
      <div className="page-header">
        <h1>{t.home.title}</h1>
        <div style={{ display: 'flex', gap: 8 }}>
          {/* Importar */}
          <button
            className="btn btn-icon"
            title="Importar proyecto .json"
            onClick={triggerImport}
          >⬇</button>
          <input
            ref={importRef}
            type="file"
            accept=".json,application/json"
            style={{ display: 'none' }}
            onChange={handleImportFile}
          />
          {/* Buscar */}
          <button
            className={`btn btn-icon ${showSearch ? 'btn-icon-active' : ''}`}
            title="Buscar"
            onClick={() => { setShowSearch(v => !v); setSearch('') }}
          >🔍</button>
        </div>
      </div>

      {/* Notificaciones de import */}
      {importSuccess && (
        <div className="projects-toast projects-toast-ok">✅ Proyecto importado</div>
      )}
      {importError && (
        <div className="projects-toast projects-toast-err">⚠️ {importError}</div>
      )}

      {/* Búsqueda */}
      {showSearch && (
        <div className="projects-search-wrap">
          <input
            className="projects-search-input"
            type="text"
            placeholder="Buscar por nombre, cliente o fecha…"
            value={search}
            onChange={e => setSearch(e.target.value)}
            autoFocus
          />
          {search && (
            <button className="projects-search-clear" onClick={() => setSearch('')}>✕</button>
          )}
        </div>
      )}

      {/* Filtros */}
      {!search && (
        <div className="projects-filters">
          {['recent', 'all'].map((f) => (
            <button
              key={f}
              className={`pill ${filter === f ? 'pill-active' : ''}`}
              onClick={() => setFilter(f)}
            >
              {f === 'recent'
                ? `${t.home.recent} (${Math.min(merged.length, RECENT_COUNT)})`
                : `${t.home.all} (${merged.length})`}
            </button>
          ))}
          {Capacitor.isNativePlatform() && (
            <button className="pill" onClick={loadNativeProjects} title="Actualizar">
              {loadingNative ? '⏳' : '↻'}
            </button>
          )}
        </div>
      )}

      {/* Lista */}
      <div className="page-content">
        {merged.length === 0 ? (
          <div className="projects-empty">
            <div className="projects-empty-icon">📁</div>
            <p className="projects-empty-title">{t.home.empty}</p>
            <p className="muted" style={{ fontSize: 13 }}>{t.home.emptyHint}</p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="projects-empty">
            <div className="projects-empty-icon" style={{ fontSize: '2rem' }}>🔍</div>
            <p className="projects-empty-title">Sin resultados</p>
            <p className="muted" style={{ fontSize: 13 }}>Prueba con otro nombre o fecha</p>
          </div>
        ) : (
          filtered.map((p) => (
            <ProjectCard
              key={p.id}
              project={p}
              onClick={() => onOpen(p)}
              onView={p.usdzPath || p._native ? (e) => handleOpenViewer(p.id, e) : null}
              onExport={!p._native ? (e) => handleExport(p.id, e) : null}
              onDelete={(e) => askDelete(p, e)}
            />
          ))
        )}
      </div>

      {/* Modal confirmación borrar */}
      {confirmDelete && (
        <div className="projects-modal-overlay" onClick={() => setConfirmDelete(null)}>
          <div className="projects-modal" onClick={e => e.stopPropagation()}>
            <div className="projects-modal-icon">🗑️</div>
            <p className="projects-modal-title">Eliminar proyecto</p>
            <p className="projects-modal-desc">
              ¿Seguro que quieres eliminar <strong>{confirmDelete.name}</strong>?
              <br /><span className="muted" style={{ fontSize: 12 }}>Esta acción no se puede deshacer.</span>
            </p>
            <div className="projects-modal-actions">
              <button className="btn btn-ghost" onClick={() => setConfirmDelete(null)}>
                Cancelar
              </button>
              <button className="btn btn-danger" onClick={confirmDeleteProject}>
                Eliminar
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// ── Tarjeta de proyecto ───────────────────────────────────────────────────────

function ProjectCard({ project, onClick, onView, onExport, onDelete }) {
  const dateStr = project.date
    || (project.createdAt ? new Date(project.createdAt).toLocaleDateString('es-ES') : '')

  return (
    <div className="project-card" onClick={onClick}>
      <div className="project-card-thumb">
        {project.thumbnail
          ? <img src={project.thumbnail} alt="" />
          : <span className="project-card-icon">🏠</span>
        }
      </div>

      <div className="project-card-body">
        <div className="project-card-name">{project.name || 'Sin nombre'}</div>

        {/* Métricas */}
        <div className="project-card-meta muted">
          {project.areaSqM > 0 && `${(+project.areaSqM).toFixed(1)} m²`}
          {project.areaSqM > 0 && project.volume > 0 && ' · '}
          {project.volume  > 0 && `${(+project.volume).toFixed(1)} m³`}
          {(project.areaSqM > 0 || project.volume > 0) && dateStr && ' · '}
          {dateStr}
        </div>

        {project.clientName && (
          <div className="project-card-client muted" style={{ fontSize: 12 }}>
            👤 {project.clientName}
          </div>
        )}

        {project.type && (
          <span className={`badge badge-${project.type === 'scan' ? 'amber' : 'teal'}`}
            style={{ marginTop: 4 }}>
            {project.type === 'scan'   ? '📐 Medición'
              : project.type === 'manual' ? '✏️ Manual'
              : '🧊 3D'}
          </span>
        )}

        {/* Acciones */}
        <div className="project-card-actions" onClick={e => e.stopPropagation()}>
          {onView && (
            <button className="btn btn-xs btn-outline" onClick={onView} title="Ver modelo 3D">
              🧊 3D
            </button>
          )}
          {onExport && (
            <button className="btn btn-xs btn-outline" onClick={onExport} title="Exportar .json">
              ⬆ JSON
            </button>
          )}
          <button className="btn btn-xs btn-danger-ghost" onClick={onDelete} title="Eliminar">
            🗑
          </button>
        </div>
      </div>

      <span className="muted" style={{ fontSize: 20 }}>›</span>
    </div>
  )
}
