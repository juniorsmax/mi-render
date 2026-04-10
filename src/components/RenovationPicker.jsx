import { useState } from 'react'
import { RENOVATION_CATALOG } from '../lib/renovationCatalog'
import './RenovationPicker.css'

/**
 * RenovationPicker — Selector de partidas de reforma por categoría
 * Permite elegir categoría y luego seleccionar partidas individuales
 * onAdd(item) se llama para cada partida que el usuario añade
 */
export function RenovationPicker({ onAdd, onClose, areaSqM = 0 }) {
  const [selectedCat, setSelectedCat] = useState(null)
  const [search, setSearch] = useState('')
  const [added, setAdded] = useState(new Set())

  const categories = Object.entries(RENOVATION_CATALOG)

  const filteredItems = selectedCat
    ? RENOVATION_CATALOG[selectedCat].items.filter(item =>
        item.description.toLowerCase().includes(search.toLowerCase())
      )
    : []

  function handleAdd(item) {
    const quantity = item.unit === 'm²' ? (areaSqM || 1) : 1
    onAdd({ ...item, quantity })
    setAdded(prev => new Set([...prev, item.description]))
  }

  return (
    <div className="renov-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="renov-sheet">
        <div className="renov-handle" />

        <div className="renov-header">
          {selectedCat ? (
            <>
              <button className="renov-back" onClick={() => { setSelectedCat(null); setSearch('') }}>
                ← Categorías
              </button>
              <div className="renov-cat-title">
                <span>{RENOVATION_CATALOG[selectedCat].icon}</span>
                <span>{RENOVATION_CATALOG[selectedCat].label}</span>
              </div>
            </>
          ) : (
            <div className="renov-title">Añadir partidas de reforma</div>
          )}
          <button className="renov-close" onClick={onClose}>✕</button>
        </div>

        {!selectedCat ? (
          // ── Vista de categorías ──
          <div className="renov-categories">
            {categories.map(([key, cat]) => (
              <button
                key={key}
                className="renov-cat-btn"
                style={{ '--cat-color': cat.color }}
                onClick={() => setSelectedCat(key)}
              >
                <span className="renov-cat-icon">{cat.icon}</span>
                <span className="renov-cat-label">{cat.label}</span>
                <span className="renov-cat-count">{cat.items.length} partidas</span>
                <span className="renov-cat-arrow">›</span>
              </button>
            ))}
          </div>
        ) : (
          // ── Vista de partidas ──
          <>
            <div className="renov-search-wrap">
              <input
                type="text"
                placeholder="Buscar partida…"
                value={search}
                onChange={e => setSearch(e.target.value)}
                className="renov-search"
              />
            </div>
            <div className="renov-items">
              {filteredItems.map((item, i) => {
                const isAdded = added.has(item.description)
                return (
                  <div key={i} className={`renov-item ${isAdded ? 'renov-item-added' : ''}`}>
                    <div className="renov-item-info">
                      <div className="renov-item-desc">{item.description}</div>
                      <div className="renov-item-meta">
                        <span className="renov-item-unit">{item.unit}</span>
                        <span className="renov-item-price">
                          {item.unitPrice.toLocaleString('es-ES', { style: 'currency', currency: 'EUR' })}/{item.unit}
                        </span>
                      </div>
                    </div>
                    <button
                      className={`renov-add-btn ${isAdded ? 'added' : ''}`}
                      onClick={() => handleAdd(item)}
                    >
                      {isAdded ? '✓' : '+'}
                    </button>
                  </div>
                )
              })}
              {filteredItems.length === 0 && (
                <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '24px 0', fontSize: 13 }}>
                  No se encontraron partidas
                </p>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  )
}
