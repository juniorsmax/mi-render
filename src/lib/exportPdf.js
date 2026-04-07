import jsPDF from 'jspdf'
import autoTable from 'jspdf-autotable'

function money(n) {
  return n.toLocaleString('es-ES', { style: 'currency', currency: 'EUR' })
}

export function exportPdf(budgetData) {
  const { roomName, dimensions, areaSqM, services, taxRate,
    subtotalBeforeTax, taxAmount, total, company, clientName, date } = budgetData

  const doc = new jsPDF({ unit: 'mm', format: 'a4' })
  const pageW = doc.internal.pageSize.getWidth()

  // Header bar
  doc.setFillColor(10, 12, 18)
  doc.rect(0, 0, pageW, 30, 'F')

  // Company name
  doc.setTextColor(108, 143, 255)
  doc.setFontSize(22)
  doc.setFont('helvetica', 'bold')
  doc.text(company || 'Zerbitecni', 14, 18)

  // Subtitle
  doc.setTextColor(107, 115, 133)
  doc.setFontSize(9)
  doc.setFont('helvetica', 'normal')
  doc.text('PRESUPUESTO DE OBRAS', 14, 26)

  // Date top-right
  doc.setTextColor(200, 205, 216)
  doc.text(date || new Date().toLocaleDateString('es-ES'), pageW - 14, 18, { align: 'right' })

  // Info section
  doc.setTextColor(107, 115, 133)
  doc.setFontSize(8)
  doc.text('CLIENTE', 14, 40)
  doc.text('ESTANCIA', 80, 40)
  doc.text('SUPERFICIE', 146, 40)

  doc.setTextColor(238, 240, 245)
  doc.setFontSize(11)
  doc.setFont('helvetica', 'bold')
  doc.text(clientName || '—', 14, 47)
  doc.text(roomName || '—', 80, 47)
  doc.text(`${areaSqM.toFixed(2)} m²`, 146, 47)

  if (dimensions) {
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(9)
    doc.setTextColor(107, 115, 133)
    doc.text(dimensions, 80, 53)
  }

  // Services table
  autoTable(doc, {
    startY: 62,
    head: [['Servicio / Descripción', 'Unidad', 'Precio unit.', 'Cantidad', 'Subtotal']],
    body: services.map((s) => [
      s.description,
      s.unit,
      money(s.unitPrice),
      s.quantity,
      money(s.quantity * s.unitPrice),
    ]),
    foot: [
      ['', '', '', 'Subtotal', money(subtotalBeforeTax)],
      ['', '', '', `IVA (${taxRate}%)`, money(taxAmount)],
      ['', '', '', 'TOTAL', money(total)],
    ],
    styles: {
      fontSize: 9,
      textColor: [200, 205, 216],
      fillColor: [18, 21, 31],
      lineColor: [30, 35, 50],
      lineWidth: 0.2,
    },
    headStyles: {
      fillColor: [26, 30, 46],
      textColor: [238, 240, 245],
      fontStyle: 'bold',
    },
    footStyles: {
      fillColor: [18, 21, 31],
      textColor: [200, 205, 216],
      fontStyle: 'bold',
    },
    columnStyles: {
      0: { cellWidth: 75 },
      1: { cellWidth: 22, halign: 'center' },
      2: { cellWidth: 30, halign: 'right' },
      3: { cellWidth: 22, halign: 'right' },
      4: { cellWidth: 30, halign: 'right' },
    },
    // Highlight TOTAL row
    didParseCell(data) {
      if (data.section === 'foot' && data.row.index === 2) {
        data.cell.styles.fillColor = [108, 143, 255]
        data.cell.styles.textColor = [255, 255, 255]
        data.cell.styles.fontSize = 10
      }
    },
  })

  // Footer
  const finalY = doc.lastAutoTable.finalY + 10
  doc.setFontSize(8)
  doc.setTextColor(107, 115, 133)
  doc.setFont('helvetica', 'italic')
  doc.text('Generado con mi-render · Zerbitecni', pageW / 2, finalY, { align: 'center' })

  doc.save(`presupuesto-${(roomName || 'habitacion').replace(/\s+/g, '-')}.pdf`)
}
