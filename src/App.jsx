import { useState } from 'react'
import { LangProvider } from './i18n/index.jsx'
import { BottomNav }    from './components/BottomNav.jsx'
import { CreateSheet }  from './components/CreateSheet.jsx'
import { HomeView }     from './views/HomeView.jsx'
import { ProjectsView } from './views/ProjectsView.jsx'
import { ExploreView }  from './views/ExploreView.jsx'
import { ProfileView }  from './views/ProfileView.jsx'
import { TeamView }     from './views/TeamView.jsx'
import { ScanView }     from './views/ScanView.jsx'
import { BudgetView }   from './views/BudgetView.jsx'
import { useProjects }  from './hooks/useProjects.js'

/**
 * App — tab-based navigation with create sheet
 *
 * Tabs:  projects | explore | [create FAB] | team | profile
 * Modal: scan → budget  (overlays above nav)
 */
export default function App() {
  const [tab, setTab]           = useState('projects')
  const [showCreate, setCreate] = useState(false)
  const [flow, setFlow]         = useState(null)
  const [scannedRoom, setRoom]  = useState(null)
  const [openProject, setOpenProject] = useState(null)

  const {
    projects,
    addProject,
    updateProject,
    deleteProject,
    exportProjectJSON,
    importProjectJSON,
  } = useProjects()

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
    const room = scannedRoom
    if (openProject) {
      updateProject(openProject.id, {
        name:       budgetData?.roomName   || room?.roomName   || openProject.name,
        clientName: budgetData?.clientName || openProject.clientName || '',
        areaSqM:    budgetData?.areaSqM    ?? room?.floorArea  ?? openProject.areaSqM ?? 0,
        perimeter:  room?.perimeter        ?? openProject.perimeter ?? 0,
        volume:     room?.totalVolume      ?? openProject.volume    ?? 0,
        wallCount:  room?.wallCount        ?? openProject.wallCount ?? 0,
        avgHeight:  room?.avgHeight        ?? openProject.avgHeight ?? 2.5,
        thumbnail:  room?.thumbnail        || openProject.thumbnail || null,
        usdzPath:   room?.usdzPath         || openProject.usdzPath  || null,
        room:       room                   || openProject.room,
        budgetData,
        total:      budgetData?.total      ?? openProject.total ?? 0,
      })
      setOpenProject(null)
    } else {
      addProject({
        name:       budgetData?.roomName   || room?.roomName   || 'Proyecto',
        type:       room?.scanMode === 'manual' ? 'manual' : 'scan',
        clientName: budgetData?.clientName || '',
        areaSqM:    budgetData?.areaSqM    ?? room?.floorArea  ?? 0,
        perimeter:  room?.perimeter        ?? 0,
        volume:     room?.totalVolume      ?? 0,
        wallCount:  room?.wallCount        ?? room?.walls?.length ?? 0,
        avgHeight:  room?.avgHeight        ?? 2.5,
        thumbnail:  room?.thumbnail        || null,
        usdzPath:   room?.usdzPath         || null,
        room,
        budgetData,
        total:      budgetData?.total      ?? 0,
      })
    }
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
        : tab === 'projects' && (
          <ProjectsView
            projects={projects}
            onOpen={handleOpenProject}
            onDelete={deleteProject}
            onExport={exportProjectJSON}
            onImport={importProjectJSON}
          />
        )
      }
      {tab === 'explore'  && <ExploreView />}
      {tab === 'team'     && <TeamView />}
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

