import './HomeView.css'

export function HomeView({ onStart }) {
  return (
    <div className="home-root scroll-view">
      <div className="home-bg-gradient" />

      <div className="home-content safe-top safe-bottom">
        {/* Logo / brand */}
        <div className="home-brand anim-up" style={{ animationDelay: '0ms' }}>
          <div className="home-logo">
            <svg width="44" height="44" viewBox="0 0 44 44" fill="none">
              <rect width="44" height="44" rx="13" fill="#0a0a0a" />
              <path d="M12 32L22 13L32 32H12Z" fill="white" fillOpacity="0.95" />
              <path d="M17 32L22 22L27 32H17Z" fill="white" fillOpacity="0.45" />
            </svg>
          </div>
          <div>
            <div className="home-title t-title">mi-render</div>
            <p className="home-subtitle t-caption">by <strong>Zerbitecni</strong></p>
          </div>
        </div>

        {/* Hero ilustrado */}
        <div className="home-hero glass anim-up" style={{ animationDelay: '60ms' }}>
          <div className="home-hero-illustration">
            <svg width="72" height="72" viewBox="0 0 72 72" fill="none">
              <rect x="8" y="20" width="56" height="40" rx="6" fill="currentColor" opacity="0.08"/>
              <rect x="8" y="20" width="56" height="40" rx="6" stroke="currentColor" strokeWidth="1.5" opacity="0.2"/>
              {/* Paredes */}
              <rect x="16" y="28" width="18" height="24" rx="2" stroke="currentColor" strokeWidth="1.5" opacity="0.35"/>
              <rect x="38" y="28" width="18" height="24" rx="2" stroke="currentColor" strokeWidth="1.5" opacity="0.35"/>
              {/* Puerta */}
              <path d="M28 52V42a4 4 0 018 0v10" stroke="currentColor" strokeWidth="1.5" opacity="0.5"/>
              {/* LiDAR rays */}
              <circle cx="36" cy="12" r="4" fill="currentColor" opacity="0.6"/>
              <path d="M36 16v6M28 14l3 4M44 14l-3 4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0.4"/>
            </svg>
          </div>
          <h2 className="t-headline" style={{ marginTop: 12 }}>Escanea. Mide. Presupuesta.</h2>
          <p className="muted t-callout" style={{ marginTop: 8, lineHeight: 1.5 }}>
            Usa el LiDAR de tu iPhone para medir cualquier estancia en segundos
            y genera un presupuesto profesional.
          </p>
        </div>

        {/* Feature pills */}
        <div className="home-features anim-up" style={{ animationDelay: '120ms' }}>
          <Feature icon={<LidarIcon />} label="LiDAR" />
          <Feature icon={<RulerIcon />} label="Cálculo m²" />
          <Feature icon={<DocIcon />} label="PDF · Excel" />
        </div>

        {/* Steps */}
        <div className="home-steps glass anim-up" style={{ animationDelay: '180ms' }}>
          <Step n={1} text="Apunta al suelo y mueve el iPhone lentamente" />
          <Step n={2} text="Pulsa Listo cuando tengas la habitación completa" />
          <Step n={3} text="Rellena el presupuesto y exporta en segundos" />
        </div>

        {/* CTA */}
        <div className="home-cta anim-up" style={{ animationDelay: '240ms' }}>
          <button className="home-cta-btn" onClick={onStart}>
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
              <path d="M10 2a8 8 0 100 16A8 8 0 0010 2zm3.5 8.75l-5 3A.75.75 0 017 13V7a.75.75 0 011.5-.75l5 3a.75.75 0 010 1.5z" fill="currentColor"/>
            </svg>
            Iniciar escaneo
          </button>
          <p className="muted t-caption" style={{ marginTop: 10 }}>
            iPhone 12 Pro o posterior · iOS 16+
          </p>
        </div>
      </div>
    </div>
  )
}

// Iconos SVG inline para pills
function LidarIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 15 15" fill="none">
      <circle cx="7.5" cy="7.5" r="2.5" fill="currentColor"/>
      <path d="M7.5 1v2M7.5 12v2M1 7.5h2M12 7.5h2M3.2 3.2l1.4 1.4M10.4 10.4l1.4 1.4M10.4 3.2l-1.4 1.4M4.2 10.4l-1.4 1.4" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"/>
    </svg>
  )
}
function RulerIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 15 15" fill="none">
      <rect x="1" y="5" width="13" height="5" rx="1.5" stroke="currentColor" strokeWidth="1.3"/>
      <path d="M4 5v2M7.5 5v3M11 5v2" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"/>
    </svg>
  )
}
function DocIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 15 15" fill="none">
      <path d="M3 2h6l3 3v8a1 1 0 01-1 1H3a1 1 0 01-1-1V3a1 1 0 011-1z" stroke="currentColor" strokeWidth="1.3"/>
      <path d="M9 2v3h3M5 8h5M5 10.5h3" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"/>
    </svg>
  )
}

function Feature({ icon, label }) {
  return (
    <div className="home-feature-pill glass">
      <span>{icon}</span>
      <span>{label}</span>
    </div>
  )
}

function Step({ n, text }) {
  return (
    <div className="home-step">
      <div className="home-step-n">{n}</div>
      <p>{text}</p>
    </div>
  )
}
