import {
  Document, Packer, Paragraph, Table, TableRow, TableCell,
  TextRun, AlignmentType, WidthType, BorderStyle, HeadingLevel,
  ShadingType,
} from 'docx'

function cell(text, opts = {}) {
  return new TableCell({
    children: [new Paragraph({
      children: [new TextRun({ text: String(text), bold: opts.bold, color: opts.color })],
      alignment: opts.align || AlignmentType.LEFT,
    })],
    shading: opts.bg ? { type: ShadingType.CLEAR, fill: opts.bg } : undefined,
    width: opts.width ? { size: opts.width, type: WidthType.PERCENTAGE } : undefined,
  })
}

function money(n) {
  return n.toLocaleString('es-ES', { style: 'currency', currency: 'EUR' })
}

async function shareOrSave(blob, filename) {
  const file = new File([blob], filename, { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' })
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

export async function exportWord(budgetData) {
  const { roomName, dimensions, areaSqM, allRows, services, taxRate,
    subtotalBeforeTax, taxAmount, total, company, clientName, date } = budgetData

  const rows = allRows ?? services ?? []

  const headerRows = [
    new TableRow({
      children: [
        cell('Servicio / Descripción', { bold: true, bg: '1a1e2e', color: 'eef0f5', width: 40 }),
        cell('Unidad', { bold: true, bg: '1a1e2e', color: 'eef0f5', width: 12, align: AlignmentType.CENTER }),
        cell('Precio unit.', { bold: true, bg: '1a1e2e', color: 'eef0f5', width: 16, align: AlignmentType.RIGHT }),
        cell('Cantidad', { bold: true, bg: '1a1e2e', color: 'eef0f5', width: 16, align: AlignmentType.RIGHT }),
        cell('Subtotal', { bold: true, bg: '1a1e2e', color: 'eef0f5', width: 16, align: AlignmentType.RIGHT }),
      ],
    }),
  ]

  const serviceRows = rows.map((s) =>
    new TableRow({
      children: [
        cell(s.description, { width: 40 }),
        cell(s.unit, { width: 12, align: AlignmentType.CENTER }),
        cell(money(s.unitPrice), { width: 16, align: AlignmentType.RIGHT }),
        cell(String(s.quantity), { width: 16, align: AlignmentType.RIGHT }),
        cell(money(s.quantity * s.unitPrice), { width: 16, align: AlignmentType.RIGHT }),
      ],
    })
  )

  const totalRows = [
    new TableRow({
      children: [
        cell('', { width: 40 }),
        cell('', { width: 12 }),
        cell('', { width: 16 }),
        cell('Subtotal', { bold: true, width: 16, align: AlignmentType.RIGHT }),
        cell(money(subtotalBeforeTax), { width: 16, align: AlignmentType.RIGHT }),
      ],
    }),
    new TableRow({
      children: [
        cell('', { width: 40 }),
        cell('', { width: 12 }),
        cell('', { width: 16 }),
        cell(`IVA (${taxRate}%)`, { bold: true, width: 16, align: AlignmentType.RIGHT }),
        cell(money(taxAmount), { width: 16, align: AlignmentType.RIGHT }),
      ],
    }),
    new TableRow({
      children: [
        cell('', { width: 40 }),
        cell('', { width: 12 }),
        cell('', { width: 16 }),
        cell('TOTAL', { bold: true, bg: '6c8fff', color: 'ffffff', width: 16, align: AlignmentType.RIGHT }),
        cell(money(total), { bold: true, bg: '6c8fff', color: 'ffffff', width: 16, align: AlignmentType.RIGHT }),
      ],
    }),
  ]

  const doc = new Document({
    sections: [{
      children: [
        new Paragraph({
          children: [new TextRun({ text: company || 'Zerbitecni', bold: true, size: 52, color: '6c8fff' })],
          heading: HeadingLevel.HEADING_1,
        }),
        new Paragraph({
          children: [new TextRun({ text: 'PRESUPUESTO DE OBRAS', bold: true, size: 28, color: '6b7385' })],
        }),
        new Paragraph({ text: '' }),
        new Paragraph({
          children: [
            new TextRun({ text: `Cliente: `, bold: true }),
            new TextRun({ text: clientName || '—' }),
            new TextRun({ text: `     Fecha: `, bold: true }),
            new TextRun({ text: date || new Date().toLocaleDateString('es-ES') }),
          ],
        }),
        new Paragraph({
          children: [
            new TextRun({ text: `Estancia: `, bold: true }),
            new TextRun({ text: roomName || '—' }),
            new TextRun({ text: `     Dimensiones: `, bold: true }),
            new TextRun({ text: dimensions || '—' }),
            new TextRun({ text: `     Superficie: `, bold: true }),
            new TextRun({ text: `${parseFloat(areaSqM || 0).toFixed(2)} m²` }),
          ],
        }),
        new Paragraph({ text: '' }),
        new Table({
          rows: [...headerRows, ...serviceRows, ...totalRows],
          width: { size: 100, type: WidthType.PERCENTAGE },
        }),
        new Paragraph({ text: '' }),
        new Paragraph({
          children: [new TextRun({ text: 'Generado con mi-render · Zerbitecni', size: 18, color: '6b7385', italics: true })],
          alignment: AlignmentType.CENTER,
        }),
      ],
    }],
  })

  const blob = await Packer.toBlob(doc)
  const filename = `presupuesto-${(roomName || 'habitacion').replace(/\s+/g, '-')}.docx`
  await shareOrSave(blob, filename)
}
