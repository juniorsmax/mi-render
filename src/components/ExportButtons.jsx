import { useState } from 'react'
import './ExportButtons.css'

export function ExportButtons({ onExportWord, onExportPdf, onExportExcel }) {
  const [loading, setLoading] = useState(null)

  async function handle(type, fn) {
    setLoading(type)
    try {
      await fn()
    } catch (err) {
      console.error('[Export]', type, err)
      alert(`Error al exportar ${type}: ${err.message}`)
    } finally {
      setLoading(null)
    }
  }

  return (
    <div className="export-buttons">
      <p className="export-title text-muted">Exportar presupuesto</p>
      <div className="export-row">
        <ExportBtn
          icon="📝"
          label="Word"
          sub=".docx"
          color="var(--color-accent)"
          loading={loading === 'word'}
          onClick={() => handle('word', onExportWord)}
        />
        <ExportBtn
          icon="📄"
          label="PDF"
          sub=".pdf"
          color="var(--color-danger)"
          loading={loading === 'pdf'}
          onClick={() => handle('pdf', onExportPdf)}
        />
        <ExportBtn
          icon="📊"
          label="Excel"
          sub=".xlsx"
          color="var(--color-success)"
          loading={loading === 'excel'}
          onClick={() => handle('excel', onExportExcel)}
        />
      </div>
    </div>
  )
}

function ExportBtn({ icon, label, sub, color, loading, onClick }) {
  return (
    <button
      className="export-btn glass"
      onClick={onClick}
      disabled={loading}
      type="button"
    >
      {loading
        ? <div className="export-spinner" />
        : <span className="export-icon">{icon}</span>
      }
      <span className="export-label" style={{ color }}>{label}</span>
      <span className="export-sub text-muted">{sub}</span>
    </button>
  )
}
