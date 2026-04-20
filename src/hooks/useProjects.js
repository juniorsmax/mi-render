/**
 * useProjects — hook de gestión de proyectos con persistencia completa
 *
 * Metadata por proyecto:
 *   id, name, createdAt, updatedAt, type
 *   areaSqM, perimeter, volume, wallCount
 *   clientName, address
 *   thumbnail (base64), usdzPath (ruta local iOS)
 *   room (datos raw del LiDAR), budgetData (presupuesto)
 */

import { useState, useEffect, useCallback } from 'react'

const KEY = 'mi-render-projects'

// ─── Schema de un proyecto vacío ─────────────────────────────────────────────

export function emptyProject(overrides = {}) {
  const now = new Date().toISOString()
  return {
    id:          String(Date.now()),
    name:        'Proyecto sin nombre',
    createdAt:   now,
    updatedAt:   now,
    type:        'scan',          // 'scan' | 'manual' | 'photogrammetry'
    // Dimensiones
    areaSqM:     0,
    perimeter:   0,
    volume:      0,
    wallCount:   0,
    avgHeight:   2.5,
    // Identificación
    clientName:  '',
    address:     '',
    // Archivos
    thumbnail:   null,            // base64 PNG
    usdzPath:    null,            // ruta local iOS
    // Datos completos
    room:        null,            // resultado parseLiDARResult
    budgetData:  null,            // objeto BudgetView
    ...overrides,
  }
}

// ─── Hook ────────────────────────────────────────────────────────────────────

export function useProjects() {
  const [projects, setProjects] = useState(() => {
    try {
      const raw = localStorage.getItem(KEY)
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  })

  // Auto-guardar en cada cambio
  useEffect(() => {
    try {
      localStorage.setItem(KEY, JSON.stringify(projects))
    } catch (e) {
      console.warn('[useProjects] localStorage lleno:', e)
    }
  }, [projects])

  // ── Añadir proyecto ────────────────────────────────────────────────
  const addProject = useCallback((data) => {
    const project = emptyProject({
      id:         String(Date.now()),
      name:       data.name        || 'Proyecto',
      type:       data.type        || 'scan',
      areaSqM:    data.areaSqM     ?? data.floorArea    ?? 0,
      perimeter:  data.perimeter   ?? data.perimeterM   ?? 0,
      volume:     data.volume      ?? data.totalVolume  ?? 0,
      wallCount:  data.wallCount   ?? data.walls?.length ?? 0,
      avgHeight:  data.avgHeight   ?? 2.5,
      clientName: data.clientName  || '',
      address:    data.address     || '',
      thumbnail:  data.thumbnail   || null,
      usdzPath:   data.usdzPath    || null,
      room:       data.room        || null,
      budgetData: data.budgetData  || null,
    })
    setProjects(prev => [project, ...prev])
    return project
  }, [])

  // ── Actualizar proyecto ────────────────────────────────────────────
  const updateProject = useCallback((id, updates) => {
    setProjects(prev => prev.map(p =>
      p.id === String(id)
        ? { ...p, ...updates, id: String(id), updatedAt: new Date().toISOString() }
        : p
    ))
  }, [])

  // ── Eliminar proyecto ──────────────────────────────────────────────
  const deleteProject = useCallback((id) => {
    setProjects(prev => prev.filter(p => p.id !== String(id)))
  }, [])

  // ── Exportar proyecto como .json ──────────────────────────────────
  const exportProjectJSON = useCallback((id) => {
    const project = projects.find(p => p.id === String(id))
    if (!project) return

    const json = JSON.stringify(project, null, 2)
    const blob = new Blob([json], { type: 'application/json' })
    const url  = URL.createObjectURL(blob)
    const safe = (project.name || 'proyecto').replace(/[^a-z0-9áéíóúñ]/gi, '_')
    const a    = document.createElement('a')
    a.href     = url
    a.download = `${safe}_backup.json`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    setTimeout(() => URL.revokeObjectURL(url), 5000)
  }, [projects])

  // ── Importar proyecto desde .json ─────────────────────────────────
  const importProjectJSON = useCallback((file) => {
    return new Promise((resolve, reject) => {
      if (!file) { reject(new Error('No se seleccionó archivo')); return }
      const reader = new FileReader()
      reader.onload = (e) => {
        try {
          const data = JSON.parse(e.target.result)
          if (!data || typeof data !== 'object' || !data.name) {
            reject(new Error('Archivo JSON inválido'))
            return
          }
          // Nuevo ID para evitar colisiones
          const project = {
            ...emptyProject(),
            ...data,
            id:        String(Date.now()),
            createdAt: data.createdAt || new Date().toISOString(),
            updatedAt: new Date().toISOString(),
          }
          setProjects(prev => [project, ...prev])
          resolve(project)
        } catch {
          reject(new Error('Error al parsear el JSON'))
        }
      }
      reader.onerror = () => reject(new Error('Error al leer el archivo'))
      reader.readAsText(file)
    })
  }, [])

  return {
    projects,
    setProjects,
    addProject,
    updateProject,
    deleteProject,
    exportProjectJSON,
    importProjectJSON,
  }
}
