import { useState } from 'react'
import { useLang } from '../i18n/index.jsx'
import './ProjectsView.css'

export function ProjectsView({ projects, onOpen }) {
  const { t } = useLang()
  const [filter, setFilter] = useState('recent')

  return (
    <div className="page">
      <div className="page-header">
        <h1>{t.home.title}</h1>
        <button className="btn btn-icon" title="Buscar">🔍</button>
      </div>

      {/* Filter pills */}
      <div className="projects-filters">
        {['recent', 'all'].map((f) => (
          <button
            key={f}
            className={`pill ${filter === f ? 'pill-active' : ''}`}
            onClick={() => setFilter(f)}
          >
            {f === 'recent' ? t.home.recent : t.home.all}
          </button>
        ))}
      </div>

      <div className="page-content">
        {projects.length === 0 ? (
          <div className="projects-empty">
            <div className="projects-empty-icon">📁</div>
            <p className="projects-empty-title">{t.home.empty}</p>
            <p className="muted" style={{ fontSize: 13 }}>{t.home.emptyHint}</p>
          </div>
        ) : (
          projects.map((p) => (
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
