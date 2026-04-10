import * as XLSX from 'xlsx'

function money(n) {
  return n.toLocaleString('es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

async function shareOrSave(blob, filename) {
  const file = new File([blob], filename, { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    await navigator.share({ files: [file], title: filename })
  } else {
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = filename
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 5000)
  }
}

export async function exportExcel(budgetData) {
  const { roomName, dimensions, areaSqM, allRows, services, taxRate,
    subtotalBeforeTax, taxAmount, total, company, clientName, date } = budgetData

  const rows = allRows ?? services ?? []

  const sheetRows = [
    [company || 'Zerbitecni', '', '', '', ''],
    ['PRESUPUESTO DE OBRAS', '', '', '', ''],
    [''],
    ['Cliente:', clientName || '—', '', 'Fecha:', date || new Date().toLocaleDateString('es-ES')],
    ['Estancia:', roomName || '—', '', 'Superficie:', `${parseFloat(areaSqM || 0).toFixed(2)} m²`],
    dimensions ? ['Dimensiones:', dimensions] : null,
    [''],
    ['Servicio / Descripción', 'Unidad', 'Precio unit. (€)', 'Cantidad', 'Subtotal (€)'],
    ...rows.map((s) => [
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

  const ws = XLSX.utils.aoa_to_sheet(sheetRows)

  ws['!cols'] = [
    { wch: 38 },
    { wch: 12 },
    { wch: 16 },
    { wch: 12 },
    { wch: 16 },
  ]

  const wb = XLSX.utils.book_new()
  XLSX.utils.book_append_sheet(wb, ws, 'Presupuesto')

  const filename = `presupuesto-${(roomName || 'habitacion').replace(/\s+/g, '-')}.xlsx`
  const buf = XLSX.write(wb, { type: 'array', bookType: 'xlsx' })
  const blob = new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
  await shareOrSave(blob, filename)
}
