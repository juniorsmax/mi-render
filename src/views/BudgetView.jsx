import { useState, useMemo } from 'react'
import { ServiceRow } from '../components/ServiceRow'
import { ExportButtons } from '../components/ExportButtons'
// Lazy imports to keep initial bundle small
async function exportWord(data) { const m = await import('../lib/exportWord'); return m.exportWord(data) }
async function exportPdf(data)  { const m = await import('../lib/exportPdf');  return m.exportPdf(data)  }
async function exportExcel(data){ const m = await import('../lib/exportExcel'); return m.exportExcel(data) }
import './BudgetView.css'

let _nextId = 1
function newService(overrides = {}) {
  return {
    id: _nextId++,
    description: '',
    unit: 'm²',
    unitPrice: 0,
    quantity: 1,
    ...overrides,
  }
}

function defaultServices(areaSqM) {
  return [
    newService({ description: 'Preparación de superficies', unit: 'm²', unitPrice: 4.5, quantity: areaSqM }),
    newService({ description: 'Pintura plástica (2 manos)', unit: 'm²', unitPrice: 8, quantity: areaSqM }),
    newService({ description: 'Material y transporte', unit: 'set', unitPrice: 80, quantity: 1 }),
  ]
}

export function BudgetView({ room, onRescan, onDone }) {
  const [company, setCompany] = useState('Zerbitecni')
  const [clientName, setClientName] = useState('')
  const [roomName, setRoomName] = useState(room?.roomName || '')
  const [dimensions, setDimensions] = useState(room?.dimensions || '')
  const [areaSqM, setAreaSqM] = useState(room?.areaSqM ?? 0)
  const [services, setServices] = useState(() => defaultServices(room?.areaSqM ?? 0))
  const [taxRate, setTaxRate] = useState(21)
  const [date, setDate] = useState(new Date().toLocaleDateString('es-ES'))

  const subtotalBeforeTax = useMemo(
    () => services.reduce((s, r) => s + r.quantity * r.unitPrice, 0),
    [services]
  )
  const taxAmount = subtotalBeforeTax * (taxRate / 100)
  const total = subtotalBeforeTax + taxAmount

  function updateService(id, updated) {
    setServices((prev) => prev.map((s) => (s.id === id ? updated : s)))
  }

  function removeService(id) {
    setServices((prev) => prev.filter((s) => s.id !== id))
  }

  function addService() {
    setServices((prev) => [...prev, newService()])
  }

  function buildBudgetData() {
    return {
      company, clientName, roomName, dimensions,
      areaSqM: parseFloat(areaSqM) || 0,
      services, taxRate,
      subtotalBeforeTax, taxAmount, total, date,
    }
  }

  function money(n) {
    return n.toLocaleString('es-ES', { style: 'currency', currency: 'EUR' })
  }

  return (
    <div className="budget-root scroll-view">
      <div className="budget-content safe-top safe-bottom">

        {/* Header */}
        <div className="budget-header">
          <div className="budget-header-left">
            <h2>{company || 'Zerbitecni'}</h2>
            <span className="badge badge-accent">Presupuesto</span>
          </div>
          <button className="btn btn-ghost btn-sm" onClick={onRescan}>
            ↩ Re-escanear
          </button>
        </div>

        {/* Area hero */}
        <div className="budget-area-card glass">
          <div className="budget-area-main">
            <span className="budget-area-value text-mono">{parseFloat(areaSqM).toFixed(2)}</span>
            <span className="budget-area-unit">m²</span>
          </div>
          {dimensions && <p className="text-muted" style={{ fontSize: 13 }}>{dimensions}</p>}
          <div className="budget-area-edit">
            <label>Ajustar superficie (m²)</label>
            <input
              type="number"
              value={areaSqM}
              min="0"
              step="0.01"
              onChange={(e) => setAreaSqM(e.target.value)}
              style={{ maxWidth: 120 }}
            />
          </div>
        </div>

        {/* Info section */}
        <div className="glass budget-info-section">
          <h3>Datos del presupuesto</h3>
          <div className="divider" />
          <div className="budget-form-grid">
            <div className="form-field">
              <label>Empresa</label>
              <input type="text" value={company} onChange={(e) => setCompany(e.target.value)} />
            </div>
            <div className="form-field">
              <label>Fecha</label>
              <input type="text" value={date} onChange={(e) => setDate(e.target.value)} />
            </div>
            <div className="form-field">
              <label>Cliente</label>
              <input type="text" placeholder="Nombre del cliente" value={clientName} onChange={(e) => setClientName(e.target.value)} />
            </div>
            <div className="form-field">
              <label>Estancia</label>
              <input type="text" placeholder="Ej. Salón" value={roomName} onChange={(e) => setRoomName(e.target.value)} />
            </div>
            <div className="form-field">
              <label>Dimensiones</label>
              <input type="text" placeholder="Ej. 4.2m × 3.8m" value={dimensions} onChange={(e) => setDimensions(e.target.value)} />
            </div>
            <div className="form-field">
              <label>IVA (%)</label>
              <input
                type="number"
                value={taxRate}
                min="0"
                max="100"
                step="1"
                onChange={(e) => setTaxRate(parseFloat(e.target.value) || 0)}
                style={{ maxWidth: 80 }}
              />
            </div>
          </div>
        </div>

        {/* Services table */}
        <div className="glass budget-services-section">
          <div className="budget-services-header">
            <h3>Partidas</h3>
            <button className="btn btn-ghost btn-sm" onClick={addService} type="button">
              + Añadir
            </button>
          </div>
          <div className="divider" />
          <div className="budget-table-wrapper">
            <table className="budget-table">
              <thead>
                <tr>
                  <th>Descripción</th>
                  <th>Unidad</th>
                  <th>Precio u.</th>
                  <th>Cant.</th>
                  <th style={{ textAlign: 'right' }}>Subtotal</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {services.map((s) => (
                  <ServiceRow
                    key={s.id}
                    service={s}
                    onChange={(updated) => updateService(s.id, updated)}
                    onRemove={() => removeService(s.id)}
                  />
                ))}
              </tbody>
            </table>
          </div>

          {/* Totals */}
          <div className="budget-totals">
            <div className="budget-total-row">
              <span className="text-muted">Subtotal</span>
              <span className="text-mono">{money(subtotalBeforeTax)}</span>
            </div>
            <div className="budget-total-row">
              <span className="text-muted">IVA ({taxRate}%)</span>
              <span className="text-mono">{money(taxAmount)}</span>
            </div>
            <div className="divider" />
            <div className="budget-total-row budget-total-final">
              <span>Total</span>
              <span className="text-mono text-accent">{money(total)}</span>
            </div>
          </div>
        </div>

        {/* Export */}
        <div className="glass budget-export-section">
          <ExportButtons
            onExportWord={() => exportWord(buildBudgetData())}
            onExportPdf={() => exportPdf(buildBudgetData())}
            onExportExcel={() => exportExcel(buildBudgetData())}
          />
        </div>

        <p className="budget-footer text-muted">
          Generado con mi-render · Zerbitecni
        </p>
      </div>
    </div>
  )
}
