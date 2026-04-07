import { useLang } from '../i18n/index.jsx'
import { Icon } from './Icon.jsx'

const OPTIONS = [
  { id: 'scan',    icon: 'scan',    accent: '#f0a500' },
  { id: 'photo',   icon: 'photo',   accent: '#2dd4bf', soon: true },
  { id: 'plan',    icon: 'plan',    accent: '#a78bfa', soon: true },
  { id: 'model3d', icon: 'model3d', accent: '#ff6b35', soon: true },
  { id: 'upload',  icon: 'upload',  accent: '#4ade80', soon: true },
  { id: 'manual',  icon: 'manual',  accent: '#fbbf24' },
]

export function CreateSheet({ onClose, onSelect }) {
  const { t } = useLang()

  function handleOverlay(e) {
    if (e.target === e.currentTarget) onClose()
  }

  return (
    <div className="sheet-overlay" onClick={handleOverlay}>
      <div className="sheet" style={{ position: 'relative' }}>
        <div className="sheet-handle" />
        <div className="sheet-title">{t.create.title}</div>
        <button className="sheet-close" onClick={onClose} aria-label="Cerrar">
          <Icon name="close" size={16} />
        </button>

        <div className="sheet-body">
          {OPTIONS.map((opt) => {
            const info = t.create.options[opt.id]
            return (
              <div
                key={opt.id}
                className={`list-row ${opt.soon ? 'list-row-soon' : ''}`}
                onClick={() => !opt.soon && onSelect(opt.id)}
                role="button"
              >
                <div
                  className="list-row-icon"
                  style={{ background: opt.accent + '22', border: `1px solid ${opt.accent}44`, color: opt.accent }}
                >
                  <Icon name={opt.icon} size={20} />
                </div>
                <div className="list-row-body">
                  <div className="list-row-title">
                    {info.label}
                    {opt.soon && <span className="badge-soon">Pronto</span>}
                  </div>
                  <div className="list-row-desc">{info.desc}</div>
                </div>
                {!opt.soon && <Icon name="chevronRight" size={18} style={{ color: 'var(--text-muted)' }} />}
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
