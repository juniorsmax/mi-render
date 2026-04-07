import { useLang } from '../i18n/index.jsx'

const PRICE_GUIDE = [
  { service: 'Pintura plástica (2 manos)', range: '8 – 14 €/m²' },
  { service: 'Preparación y lijado', range: '4 – 7 €/m²' },
  { service: 'Alicatado', range: '22 – 40 €/m²' },
  { service: 'Parquet / tarima', range: '18 – 35 €/m²' },
  { service: 'Escayola / pladur', range: '12 – 22 €/m²' },
]

export function ExploreView() {
  const { t } = useLang()

  return (
    <div className="page">
      <div className="page-header">
        <h1>{t.explore.title}</h1>
      </div>
      <div className="page-content">
        <p className="muted" style={{ fontSize: 13 }}>{t.explore.subtitle}</p>

        <div className="section-label">{t.explore.priceGuide}</div>
        <div className="glass" style={{ overflow: 'hidden' }}>
          {PRICE_GUIDE.map((item, i) => (
            <div key={i} style={{
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
              padding: '13px 16px',
              borderBottom: i < PRICE_GUIDE.length - 1 ? '1px solid var(--border)' : 'none',
            }}>
              <span style={{ fontSize: 14, color: 'var(--text)' }}>{item.service}</span>
              <span className="badge badge-amber">{item.range}</span>
            </div>
          ))}
        </div>

        <div className="section-label">{t.explore.tutorials}</div>
        {[
          { icon: '📹', title: 'Cómo medir con la cámara', tag: '2 min' },
          { icon: '📊', title: 'Crear tu primer presupuesto', tag: '3 min' },
          { icon: '🧊', title: 'Editor 3D — primeros pasos', tag: '5 min' },
        ].map((item, i) => (
          <div key={i} className="list-row">
            <div className="list-row-icon">{item.icon}</div>
            <div className="list-row-body">
              <div className="list-row-title">{item.title}</div>
            </div>
            <span className="badge badge-teal">{item.tag}</span>
          </div>
        ))}
      </div>
    </div>
  )
}
