import { useState, useEffect } from 'react'
import { LangProvider } from './i18n/index.jsx'
import { BottomNav }    from './components/BottomNav.jsx'
import { CreateSheet }  from './components/CreateSheet.jsx'
import { HomeView }     from './views/HomeView.jsx'
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
  const [flow, setFlow]         = useState(null)  // null | 'scan' | 'manual' | 'budget' | 'view-project'
  const [scannedRoom, setRoom]  = useState(null)
  const [openProject, setOpenProject] = useState(null)
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

  function handleOpenProject(project) {
    setOpenProject(project)
    setRoom(project.room || null)
    setFlow('view-project')
  }

  function handleBudgetDone(budgetData) {
    if (openProject) {
      // Actualizar proyecto existente
      setProjects((p) => p.map((proj) =>
        proj.id === openProject.id
          ? { ...proj, ...buildProjectFromBudget(budgetData, scannedRoom, proj) }
          : proj
      ))
      setOpenProject(null)
    } else {
      // Proyecto nuevo
      setProjects((p) => [buildProjectFromBudget(budgetData, scannedRoom, { id: Date.now(), type: scannedRoom?.scanMode === 'manual' ? 'manual' : 'scan' }), ...p])
    }
    setFlow(null)
    setRoom(null)
    setTab('projects')
  }

  function buildProjectFromBudget(budgetData, room, base) {
    return {
      ...base,
      name: budgetData?.roomName || room?.roomName || base.name || 'Proyecto',
      clientName: budgetData?.clientName || base.clientName || '',
      areaSqM: budgetData?.areaSqM ?? room?.floorArea ?? room?.areaSqM ?? base.areaSqM ?? 0,
      total: budgetData?.total ?? base.total ?? 0,
      date: budgetData?.date || new Date().toLocaleDateString('es-ES'),
      thumbnail: room?.thumbnail || base.thumbnail || null,
      room: room || base.room,
      budgetData,
    }
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

  if (flow === 'budget' || flow === 'view-project') {
    return (
      <LangProvider>
        <BudgetView
          room={scannedRoom}
          initialData={openProject?.budgetData}
          onRescan={() => { setOpenProject(null); setFlow('scan') }}
          onDone={handleBudgetDone}
        />
      </LangProvider>
    )
  }

  // ── Main tabbed shell ─────────────────────────────────────────────
  return (
    <LangProvider>
      {/* Active tab content */}
      {tab === 'projects' && projects.length === 0
        ? <HomeView onStart={() => setFlow('scan')} />
        : tab === 'projects' && <ProjectsView projects={projects} onOpen={handleOpenProject} />
      }
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
