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

// Materiales y mobiliario predefinidos
const MATERIAL_CATALOG = [
  { description: 'Pintura interior (bote 15L)', unit: 'ud', unitPrice: 42, category: 'material' },
  { description: 'Rodillo + bandeja', unit: 'set', unitPrice: 12, category: 'herramienta' },
  { description: 'Cinta de carrocero', unit: 'ud', unitPrice: 4, category: 'material' },
  { description: 'Plástico protector suelo', unit: 'm²', unitPrice: 0.8, category: 'material' },
  { description: 'Imprimación selladora', unit: 'm²', unitPrice: 3.5, category: 'material' },
  { description: 'Masilla para grietas', unit: 'ud', unitPrice: 8, category: 'material' },
  { description: 'Lija de pared', unit: 'ud', unitPrice: 2, category: 'herramienta' },
]

const FURNITURE_CATALOG = [
  { description: 'Sofá 3 plazas', unit: 'ud', unitPrice: 650, category: 'mobiliario' },
  { description: 'Mesa de comedor', unit: 'ud', unitPrice: 320, category: 'mobiliario' },
  { description: 'Silla', unit: 'ud', unitPrice: 85, category: 'mobiliario' },
  { description: 'Armario (por módulo)', unit: 'ud', unitPrice: 280, category: 'mobiliario' },
  { description: 'Cama 150×200', unit: 'ud', unitPrice: 420, category: 'mobiliario' },
  { description: 'Mesita de noche', unit: 'ud', unitPrice: 95, category: 'mobiliario' },
  { description: 'Escritorio', unit: 'ud', unitPrice: 180, category: 'mobiliario' },
  { description: 'Luminaria de techo', unit: 'ud', unitPrice: 120, category: 'mobiliario' },
  { description: 'Persiana/cortina', unit: 'ud', unitPrice: 75, category: 'mobiliario' },
]

function defaultMaterials(areaSqM) {
  const litros = Math.ceil(areaSqM / 12) // 1 bote 15L cubre ~12m² con 2 manos
  return [
    newService({ description: 'Pintura interior (bote 15L)', unit: 'ud', unitPrice: 42, quantity: litros }),
    newService({ description: 'Plástico protector suelo', unit: 'm²', unitPrice: 0.8, quantity: areaSqM }),
  ]
}

export function BudgetView({ room, initialData, onRescan, onDone }) {
  const defaultArea = room?.floorArea ?? room?.areaSqM ?? initialData?.areaSqM ?? 0
  const [company, setCompany]     = useState(initialData?.company     || 'Zerbitecni')
  const [clientName, setClientName] = useState(initialData?.clientName || '')
  const [roomName, setRoomName]   = useState(initialData?.roomName    || room?.roomName || '')
  const [dimensions, setDimensions] = useState(initialData?.dimensions || room?.dimensions || '')
  const [areaSqM, setAreaSqM]     = useState(initialData?.areaSqM     ?? defaultArea)
  const [services, setServices]   = useState(() => initialData?.services   || defaultServices(defaultArea))
  const [materials, setMaterials] = useState(() => initialData?.materials  || defaultMaterials(defaultArea))
  const [furniture, setFurniture] = useState(() => initialData?.furniture  || [])
  const [showMatCatalog, setShowMatCatalog]   = useState(false)
  const [showFurnCatalog, setShowFurnCatalog] = useState(false)
  const [taxRate, setTaxRate] = useState(initialData?.taxRate ?? 21)
  const [date, setDate]       = useState(initialData?.date    || new Date().toLocaleDateString('es-ES'))

  const subtotalBeforeTax = useMemo(
    () => [...services, ...materials, ...furniture].reduce((s, r) => s + r.quantity * r.unitPrice, 0),
    [services, materials, furniture]
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
      services, materials, furniture,
      allRows: [...services, ...materials, ...furniture],
      taxRate,
      subtotalBeforeTax, taxAmount, total, date,
    }
  }

  function addMaterialFromCatalog(item) {
    setMaterials(prev => [...prev, newService({ ...item, quantity: item.unit === 'm²' ? defaultArea : 1 })])
    setShowMatCatalog(false)
  }

  function addFurnitureFromCatalog(item) {
    setFurniture(prev => [...prev, newService({ ...item, quantity: 1 })])
    setShowFurnCatalog(false)
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

        {/* ── Materiales ────────────────────────────── */}
        <div className="glass budget-services-section">
          <div className="budget-services-header">
            <h3>Materiales</h3>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn btn-ghost btn-sm" onClick={() => setShowMatCatalog(v => !v)} type="button">
                + Catálogo
              </button>
              <button className="btn btn-ghost btn-sm" onClick={() => setMaterials(prev => [...prev, newService({ unit: 'ud' })])} type="button">
                + Manual
              </button>
            </div>
          </div>
          {showMatCatalog && (
            <div style={{ padding: '8px 0', display: 'flex', flexWrap: 'wrap', gap: 6, paddingLeft: 8, paddingRight: 8 }}>
              {MATERIAL_CATALOG.map((item, i) => (
                <button key={i} className="btn btn-ghost btn-sm" style={{ fontSize: 11 }} onClick={() => addMaterialFromCatalog(item)}>
                  + {item.description}
                </button>
              ))}
            </div>
          )}
          <div className="divider" />
          <div className="budget-table-wrapper">
            <table className="budget-table">
              <thead><tr><th>Descripción</th><th>Unidad</th><th>Precio u.</th><th>Cant.</th><th style={{ textAlign: 'right' }}>Subtotal</th><th></th></tr></thead>
              <tbody>
                {materials.map((s) => (
                  <ServiceRow key={s.id} service={s}
                    onChange={(u) => setMaterials(prev => prev.map(r => r.id === s.id ? u : r))}
                    onRemove={() => setMaterials(prev => prev.filter(r => r.id !== s.id))} />
                ))}
                {materials.length === 0 && <tr><td colSpan={6} style={{ textAlign: 'center', color: 'rgba(150,130,100,0.5)', fontSize: 12, padding: 12 }}>Sin materiales — añade desde catálogo</td></tr>}
              </tbody>
            </table>
          </div>
        </div>

        {/* ── Mobiliario ────────────────────────────── */}
        <div className="glass budget-services-section">
          <div className="budget-services-header">
            <h3>Mobiliario y equipamiento</h3>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn btn-ghost btn-sm" onClick={() => setShowFurnCatalog(v => !v)} type="button">
                + Catálogo
              </button>
              <button className="btn btn-ghost btn-sm" onClick={() => setFurniture(prev => [...prev, newService({ unit: 'ud' })])} type="button">
                + Manual
              </button>
            </div>
          </div>
          {showFurnCatalog && (
            <div style={{ padding: '8px 0', display: 'flex', flexWrap: 'wrap', gap: 6, paddingLeft: 8, paddingRight: 8 }}>
              {FURNITURE_CATALOG.map((item, i) => (
                <button key={i} className="btn btn-ghost btn-sm" style={{ fontSize: 11 }} onClick={() => addFurnitureFromCatalog(item)}>
                  + {item.description}
                </button>
              ))}
            </div>
          )}
          <div className="divider" />
          <div className="budget-table-wrapper">
            <table className="budget-table">
              <thead><tr><th>Descripción</th><th>Unidad</th><th>Precio u.</th><th>Cant.</th><th style={{ textAlign: 'right' }}>Subtotal</th><th></th></tr></thead>
              <tbody>
                {furniture.map((s) => (
                  <ServiceRow key={s.id} service={s}
                    onChange={(u) => setFurniture(prev => prev.map(r => r.id === s.id ? u : r))}
                    onRemove={() => setFurniture(prev => prev.filter(r => r.id !== s.id))} />
                ))}
                {furniture.length === 0 && <tr><td colSpan={6} style={{ textAlign: 'center', color: 'rgba(150,130,100,0.5)', fontSize: 12, padding: 12 }}>Sin mobiliario — añade desde catálogo</td></tr>}
              </tbody>
            </table>
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

        <div style={{ padding: '0 0 8px' }}>
          <button
            className="btn btn-primary"
            style={{ width: '100%' }}
            onClick={() => onDone?.(buildBudgetData())}
          >
            Guardar proyecto
          </button>
        </div>

        <p className="budget-footer text-muted">
          Generado con mi-render · Zerbitecni
        </p>
      </div>
    </div>
  )
}
