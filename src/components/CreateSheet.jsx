import { useLang } from '../i18n/index.jsx'

const OPTIONS = [
  { id: 'scan',    icon: '📐', accent: '#f0a500' },
  { id: 'photo',   icon: '🪄', accent: '#2dd4bf' },
  { id: 'plan',    icon: '🗺️', accent: '#a78bfa' },
  { id: 'model3d', icon: '🧊', accent: '#ff6b35' },
  { id: 'upload',  icon: '📤', accent: '#4ade80' },
  { id: 'manual',  icon: '✏️', accent: '#fbbf24' },
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
        <button className="sheet-close" onClick={onClose}>✕</button>

        <div className="sheet-body">
          {OPTIONS.map((opt) => {
            const info = t.create.options[opt.id]
            return (
              <div
                key={opt.id}
                className="list-row"
                onClick={() => onSelect(opt.id)}
              >
                <div
                  className="list-row-icon"
                  style={{ background: opt.accent + '22', border: `1px solid ${opt.accent}44` }}
                >
                  {opt.icon}
                </div>
                <div className="list-row-body">
                  <div className="list-row-title">{info.label}</div>
                  <div className="list-row-desc">{info.desc}</div>
                </div>
                <span className="list-row-chevron">›</span>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
