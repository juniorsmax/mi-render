/**
 * security.js — utilidades de seguridad para mi-render
 * Sanitización de inputs, storage seguro, validaciones
 */

// ── Sanitización de texto ────────────────────────────────────────────────────

/**
 * Elimina caracteres peligrosos de strings (previene XSS)
 */
export function sanitizeText(str) {
  if (typeof str !== 'string') return ''
  return str
    .replace(/[<>]/g, '')          // elimina < >
    .replace(/javascript:/gi, '')  // elimina javascript: URIs
    .replace(/on\w+\s*=/gi, '')    // elimina event handlers inline
    .trim()
    .slice(0, 500)                 // límite máximo de longitud
}

/**
 * Sanitiza un número: retorna el número o null si no es válido
 */
export function sanitizeNumber(val, { min = 0, max = 99999 } = {}) {
  const n = parseFloat(val)
  if (isNaN(n) || !isFinite(n)) return null
  if (n < min || n > max) return null
  return n
}

/**
 * Sanitiza un nombre de proyecto/estancia
 */
export function sanitizeName(str) {
  if (typeof str !== 'string') return ''
  return sanitizeText(str).slice(0, 100)
}

// ── localStorage seguro ──────────────────────────────────────────────────────

const STORAGE_PREFIX = 'mr_'

export const safeStorage = {
  get(key) {
    try {
      const raw = localStorage.getItem(STORAGE_PREFIX + key)
      if (!raw) return null
      return JSON.parse(raw)
    } catch {
      return null
    }
  },

  set(key, value) {
    try {
      localStorage.setItem(STORAGE_PREFIX + key, JSON.stringify(value))
      return true
    } catch {
      return false
    }
  },

  remove(key) {
    try {
      localStorage.removeItem(STORAGE_PREFIX + key)
    } catch {}
  },

  clear() {
    try {
      Object.keys(localStorage)
        .filter((k) => k.startsWith(STORAGE_PREFIX))
        .forEach((k) => localStorage.removeItem(k))
    } catch {}
  },
}

// ── Validaciones de negocio ──────────────────────────────────────────────────

export function validateRoom(room) {
  const errors = []
  if (!room) { errors.push('Datos de habitación vacíos'); return errors }
  if (room.areaSqM !== undefined) {
    const area = sanitizeNumber(room.areaSqM, { min: 0.1, max: 10000 })
    if (area === null) errors.push('Superficie no válida')
  }
  if (room.roomName) {
    const name = sanitizeName(room.roomName)
    if (name.length === 0) errors.push('Nombre de estancia no válido')
  }
  return errors
}

export function validateBudgetLine(line) {
  const errors = []
  if (!line.description || sanitizeText(line.description).length === 0) {
    errors.push('Descripción vacía')
  }
  if (sanitizeNumber(line.qty, { min: 0 }) === null) errors.push('Cantidad no válida')
  if (sanitizeNumber(line.price, { min: 0 }) === null) errors.push('Precio no válido')
  return errors
}

// ── Permisos de cámara ───────────────────────────────────────────────────────

export async function checkCameraPermission() {
  try {
    if (!navigator.permissions) return 'unknown'
    const result = await navigator.permissions.query({ name: 'camera' })
    return result.state // 'granted' | 'denied' | 'prompt'
  } catch {
    return 'unknown'
  }
}
