import { useLang } from '../i18n/index.jsx'
import { Icon } from './Icon.jsx'

const TABS = [
  { id: 'projects', icon: 'projects' },
  { id: 'explore',  icon: 'explore' },
  { id: 'create',   icon: 'plus', fab: true },
  { id: 'team',     icon: 'team' },
  { id: 'profile',  icon: 'profile' },
]

export function BottomNav({ active, onTab, onCreate }) {
  const { t } = useLang()

  const labels = {
    projects: t.nav.projects,
    explore:  t.nav.explore,
    team:     'Equipo',
    profile:  t.nav.profile,
  }

  return (
    <nav className="bottom-nav">
      {TABS.map((tab) => {
        if (tab.fab) {
          return (
            <div key="create" className="nav-tab" onClick={onCreate} role="button" aria-label="Crear nuevo proyecto">
              <div className="nav-tab-fab">
                <Icon name="plus" size={26} style={{ color: '#0c0a08' }} />
              </div>
            </div>
          )
        }
        return (
          <div
            key={tab.id}
            className={`nav-tab ${active === tab.id ? 'active' : ''}`}
            onClick={() => onTab(tab.id)}
            role="button"
            aria-label={labels[tab.id]}
          >
            <span className="nav-tab-icon">
              <Icon name={tab.icon} size={22} />
            </span>
            <span className="nav-tab-label">{labels[tab.id]}</span>
          </div>
        )
      })}
    </nav>
  )
}
