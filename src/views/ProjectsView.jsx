import { useState, useEffect } from 'react'
import { Capacitor } from '@capacitor/core'
import { useLang } from '../i18n/index.jsx'
import { listProjects, openViewer, deleteProject } from '../lib/lidar.js'
import './ProjectsView.css'

const RECENT_COUNT = 5

export function ProjectsView({ projects, onOpen, onProjectsChanged }) {
  const { t } = useLang()
  const [filter, setFilter]       = useState('recent')
  const [search, setSearch]       = useState('')
  const [showSearch, setShowSearch] = useState(false)
  const [nativeProjects, setNativeProjects] = useState([])
  const [loadingNative, setLoadingNative]   = useState(false)

  // Cargar proyectos guardados en disco (solo en iOS nativo)
  useEffect(() => {
    if (!Capacitor.isNativePlatform()) return
    loadNativeProjects()
  }, [])

  async function loadNativeProjects() {
    setLoadingNative(true)
    try {
      const res = await listProjects()
      setNativeProjects(res?.projects ?? [])
    } catch {
      // Sin conexión nativa o error — ignorar silenciosamente
    } finally {
      setLoadingNative(false)
    }
  }

  // Combina proyectos de localStorage + proyectos nativos (por id, sin duplicar)
  const localIds = new Set(projects.map(p => String(p.id)))
  const merged = [
    ...projects,
    ...nativeProjects
      .filter(np => !localIds.has(np.id))
      .map(np => ({
        id:          np.id,
        type:        'scan',
        name:        np.name,
        areaSqM:     np.floorArea ? np.floorArea.toFixed(1) : null,
        date:        np.createdAt ? new Date(np.createdAt).toLocaleDateString('es-ES') : '',
        thumbnail:   np.thumbnailBase64 ?? null,
        usdzPath:    np.usdzPath ?? null,
        _native:     true,
      }))
  ]

  const sorted = [...merged].sort((a, b) => {
    const ta = a._native ? new Date(nativeProjects.find(n=>n.id===a.id)?.createdAt||0).getTime() : (a.id ?? 0)
    const tb = b._native ? new Date(nativeProjects.find(n=>n.id===b.id)?.createdAt||0).getTime() : (b.id ?? 0)
    return tb - ta
  })

  const filtered = search.trim()
    ? sorted.filter(p =>
        (p.name       || '').toLowerCase().includes(search.toLowerCase()) ||
        (p.clientName || '').toLowerCase().includes(search.toLowerCase()) ||
        (p.date       || '').toLowerCase().includes(search.toLowerCase())
      )
    : filter === 'recent' ? sorted.slice(0, RECENT_COUNT) : sorted

  function toggleSearch() {
    setShowSearch(v => !v)
    setSearch('')
  }

  async function handleOpenViewer(projectId, e) {
    e.stopPropagation()
    try { await openViewer(projectId) } catch (err) {
      console.warn('openViewer error:', err)
    }
  }

  async function handleDelete(projectId, isNative, e) {
    e.stopPropagation()
    if (!confirm('¿Eliminar este proyecto?')) return
    if (isNative) {
      try { await deleteProject(projectId) } catch {}
      setNativeProjects(prev => prev.filter(p => p.id !== projectId))
    }
    onProjectsChanged?.(projectId)
  }

  return (
    <div className="page">
      <div className="page-header">
        <h1>{t.home.title}</h1>
        <button
          className={`btn btn-icon ${showSearch ? 'btn-icon-active' : ''}`}
          title="Buscar"
          onClick={toggleSearch}
        >🔍</button>
      </div>

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
              onView={p.usdzPath || p._native
                ? (e) => handleOpenViewer(p.id, e)
                : null}
              onDelete={(e) => handleDelete(p.id, !!p._native, e)}
            />
          ))
        )}
      </div>
    </div>
  )
}

function ProjectCard({ project, onClick, onView, onDelete }) {
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
        <div className="project-card-meta muted">
          {project.areaSqM ? `${project.areaSqM} m²` : ''}
          {project.areaSqM && project.date ? ' · ' : ''}
          {project.date || ''}
        </div>
        {project.type && (
          <span className={`badge badge-${project.type === 'scan' ? 'amber' : 'teal'}`} style={{ marginTop: 4 }}>
            {project.type === 'scan' ? '📐 Medición' : project.type === 'manual' ? '✏️ Manual' : '🧊 3D'}
          </span>
        )}
        <div className="project-card-actions" onClick={e => e.stopPropagation()}>
          {onView && (
            <button className="btn btn-xs btn-outline" onClick={onView} title="Ver modelo 3D">
              🧊 3D
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
