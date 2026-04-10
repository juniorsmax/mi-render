import { useState, useEffect } from 'react'
import { LangProvider } from './i18n/index.jsx'
import { BottomNav }    from './components/BottomNav.jsx'
import { CreateSheet }  from './components/CreateSheet.jsx'
import { ProjectsView } from './views/ProjectsView.jsx'
import { ExploreView }  from './views/ExploreView.jsx'
import { ProfileView }  from './views/ProfileView.jsx'
import { ScanView }     from './views/ScanView.jsx'
import { BudgetView }   from './views/BudgetView.jsx'

/**
 * App — tab-based navigation with create sheet
 *
 * Tabs:  projects | explore | [create FAB] | team | profile
 * Modal: scan → budget  (overlays above nav)
 */
export default function App() {
  const [tab, setTab]           = useState('projects')
  const [showCreate, setCreate] = useState(false)
  const [flow, setFlow]         = useState(null)  // null | 'scan' | 'manual' | 'budget'
  const [scannedRoom, setRoom]  = useState(null)
  const [projects, setProjects] = useState(() => {
    try { return JSON.parse(localStorage.getItem('mi-render-projects') || '[]') }
    catch { return [] }
  })

  useEffect(() => {
    try { localStorage.setItem('mi-render-projects', JSON.stringify(projects)) }
    catch {}
  }, [projects])

  function handleSelect(optionId) {
    setCreate(false)
    if (optionId === 'scan')   { setFlow('scan') }
    if (optionId === 'manual') { setFlow('manual') }
    if (optionId === 'model3d'){ setFlow('model3d') }
    // photo, plan, upload — coming soon toast
    if (['photo', 'plan', 'upload'].includes(optionId)) {
      alert('Próximamente disponible')
    }
  }

  function handleScanComplete(room) {
    setRoom(room)
    setFlow('budget')
  }

  function handleBudgetDone(budgetData) {
    const newProject = {
      id: Date.now(),
      name: budgetData?.roomName || scannedRoom?.roomName || 'Proyecto ' + (projects.length + 1),
      clientName: budgetData?.clientName || '',
      areaSqM: budgetData?.areaSqM ?? scannedRoom?.floorArea ?? scannedRoom?.areaSqM ?? 0,
      total: budgetData?.total ?? 0,
      date: budgetData?.date || new Date().toLocaleDateString('es-ES'),
      type: scannedRoom?.scanMode === 'manual' ? 'manual' : 'scan',
      room: scannedRoom,
    }
    setProjects((p) => [newProject, ...p])
    setFlow(null)
    setRoom(null)
    setTab('projects')
  }

  // ── Full-screen flows (scanner / budget) ─────────────────────────
  if (flow === 'scan' || flow === 'manual') {
    return (
      <LangProvider>
        <ScanView
          initialStep={flow === 'manual' ? 'manual' : 'permission'}
          onComplete={handleScanComplete}
          onCancel={() => setFlow(null)}
        />
      </LangProvider>
    )
  }

  if (flow === 'budget') {
    return (
      <LangProvider>
        <BudgetView
          room={scannedRoom}
          onRescan={() => setFlow('scan')}
          onDone={handleBudgetDone}
        />
      </LangProvider>
    )
  }

  // ── Main tabbed shell ─────────────────────────────────────────────
  return (
    <LangProvider>
      {/* Active tab content */}
      {tab === 'projects' && <ProjectsView projects={projects} onOpen={() => {}} />}
      {tab === 'explore'  && <ExploreView />}
      {tab === 'team'     && <TeamPlaceholder />}
      {tab === 'profile'  && <ProfileView />}

      {/* Bottom navigation */}
      <BottomNav
        active={tab}
        onTab={setTab}
        onCreate={() => setCreate(true)}
      />

      {/* Create sheet */}
      {showCreate && (
        <CreateSheet
          onClose={() => setCreate(false)}
          onSelect={handleSelect}
        />
      )}
    </LangProvider>
  )
}

function TeamPlaceholder() {
  return (
    <div className="page">
      <div className="page-header"><h1>Equipo</h1></div>
      <div className="page-content" style={{ alignItems: 'center', justifyContent: 'center', textAlign: 'center' }}>
        <span style={{ fontSize: '3rem', opacity: 0.3 }}>👥</span>
        <p className="muted">Próximamente</p>
      </div>
    </div>
  )
}
