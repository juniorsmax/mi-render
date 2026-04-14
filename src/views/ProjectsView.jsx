import { useState } from 'react'
import { useLang } from '../i18n/index.jsx'
import './ProjectsView.css'

const RECENT_COUNT = 5

export function ProjectsView({ projects, onOpen }) {
  const { t } = useLang()
  const [filter, setFilter]   = useState('recent')
  const [search, setSearch]   = useState('')
  const [showSearch, setShowSearch] = useState(false)

  const sorted = [...projects].sort((a, b) => (b.id ?? 0) - (a.id ?? 0))

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

      {/* Filter pills — se ocultan durante búsqueda activa */}
      {!search && (
        <div className="projects-filters">
          {['recent', 'all'].map((f) => (
            <button
              key={f}
              className={`pill ${filter === f ? 'pill-active' : ''}`}
              onClick={() => setFilter(f)}
            >
              {f === 'recent'
                ? `${t.home.recent} (${Math.min(projects.length, RECENT_COUNT)})`
                : `${t.home.all} (${projects.length})`}
            </button>
          ))}
        </div>
      )}

      <div className="page-content">
        {projects.length === 0 ? (
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
            <ProjectCard key={p.id} project={p} onClick={() => onOpen(p)} />
          ))
        )}
      </div>
    </div>
  )
}

function ProjectCard({ project, onClick }) {
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
      </div>
      <span className="muted" style={{ fontSize: 20 }}>›</span>
    </div>
  )
}
