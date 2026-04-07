import './ServiceRow.css'

const UNITS = ['m²', 'm lineal', 'ud', 'hora', 'set']

export function ServiceRow({ service, onChange, onRemove }) {
  const subtotal = (service.quantity * service.unitPrice).toFixed(2)

  function update(field, value) {
    onChange({ ...service, [field]: value })
  }

  return (
    <tr className="service-row">
      <td>
        <input
          type="text"
          value={service.description}
          onChange={(e) => update('description', e.target.value)}
          placeholder="Descripción del servicio"
        />
      </td>
      <td>
        <select
          value={service.unit}
          onChange={(e) => update('unit', e.target.value)}
        >
          {UNITS.map((u) => <option key={u} value={u}>{u}</option>)}
        </select>
      </td>
      <td>
        <input
          type="number"
          value={service.unitPrice}
          onChange={(e) => update('unitPrice', parseFloat(e.target.value) || 0)}
          min="0"
          step="0.01"
          placeholder="0.00"
        />
      </td>
      <td>
        <input
          type="number"
          value={service.quantity}
          onChange={(e) => update('quantity', parseFloat(e.target.value) || 0)}
          min="0"
          step="0.01"
          placeholder="1"
        />
      </td>
      <td className="service-subtotal text-mono">
        {parseFloat(subtotal).toLocaleString('es-ES', { minimumFractionDigits: 2 })} €
      </td>
      <td>
        <button
          className="service-remove"
          onClick={onRemove}
          title="Eliminar fila"
          type="button"
        >
          ×
        </button>
      </td>
    </tr>
  )
}
