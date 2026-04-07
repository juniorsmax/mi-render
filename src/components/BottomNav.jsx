import { useLang } from '../i18n/index.jsx'

const TABS = [
  { id: 'projects', icon: '🗂️' },
  { id: 'explore',  icon: '🌐' },
  { id: 'create',   icon: '+', fab: true },
  { id: 'team',     icon: '👥' },
  { id: 'profile',  icon: '👤' },
]

export function BottomNav({ active, onTab, onCreate }) {
  const { t } = useLang()

  const labels = {
    projects: t.nav.projects,
    explore:  t.nav.explore,
    create:   t.nav.create,
    team:     'Equipo',
    profile:  t.nav.profile,
  }

  return (
    <nav className="bottom-nav">
      {TABS.map((tab) => {
        if (tab.fab) {
          return (
            <div key="create" className="nav-tab" onClick={onCreate}>
              <div className="nav-tab-fab">{tab.icon}</div>
            </div>
          )
        }
        return (
          <div
            key={tab.id}
            className={`nav-tab ${active === tab.id ? 'active' : ''}`}
            onClick={() => onTab(tab.id)}
          >
            <span className="nav-tab-icon">{tab.icon}</span>
            <span className="nav-tab-label">{labels[tab.id]}</span>
          </div>
        )
      })}
    </nav>
  )
}
