import * as XLSX from 'xlsx'

function money(n) {
  return n.toLocaleString('es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

export function exportExcel(budgetData) {
  const { roomName, dimensions, areaSqM, services, taxRate,
    subtotalBeforeTax, taxAmount, total, company, clientName, date } = budgetData

  const rows = [
    [company || 'Zerbitecni', '', '', '', ''],
    ['PRESUPUESTO DE OBRAS', '', '', '', ''],
    [''],
    ['Cliente:', clientName || '—', '', 'Fecha:', date || new Date().toLocaleDateString('es-ES')],
    ['Estancia:', roomName || '—', '', 'Superficie:', `${areaSqM.toFixed(2)} m²`],
    dimensions ? ['Dimensiones:', dimensions] : null,
    [''],
    ['Servicio / Descripción', 'Unidad', 'Precio unit. (€)', 'Cantidad', 'Subtotal (€)'],
    ...services.map((s) => [
      s.description,
      s.unit,
      money(s.unitPrice),
      s.quantity,
      money(s.quantity * s.unitPrice),
    ]),
    [''],
    ['', '', '', 'Subtotal', money(subtotalBeforeTax)],
    ['', '', '', `IVA (${taxRate}%)`, money(taxAmount)],
    ['', '', '', 'TOTAL', money(total)],
    [''],
    ['Generado con mi-render · Zerbitecni'],
  ].filter(Boolean)

  const ws = XLSX.utils.aoa_to_sheet(rows)

  // Column widths
  ws['!cols'] = [
    { wch: 38 },
    { wch: 12 },
    { wch: 16 },
    { wch: 12 },
    { wch: 16 },
  ]

  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Presupuesto')
  XLSX.writeFile(wb, `presupuesto-${(roomName || 'habitacion').replace(/\s+/g, '-')}.xlsx`)
}
