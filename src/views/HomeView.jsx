import './HomeView.css'

export function HomeView({ onStart }) {
  return (
    <div className="home-root scroll-view">
      <div className="home-bg-gradient" />

      <div className="home-content safe-top safe-bottom">
        {/* Logo / brand */}
        <div className="home-brand">
          <div className="home-logo">
            <svg width="40" height="40" viewBox="0 0 40 40" fill="none">
              <rect width="40" height="40" rx="12" fill="url(#lg)" />
              <path d="M10 28L20 12L30 28H10Z" fill="white" fillOpacity="0.9" />
              <defs>
                <linearGradient id="lg" x1="0" y1="0" x2="40" y2="40">
                  <stop stopColor="#6c8fff" />
                  <stop offset="1" stopColor="#a78bfa" />
                </linearGradient>
              </defs>
            </svg>
          </div>
          <div>
            <h1 className="home-title">mi-render</h1>
            <p className="home-subtitle">by <strong>Zerbitecni</strong></p>
          </div>
        </div>

        {/* Hero description */}
        <div className="home-hero glass">
          <div className="home-hero-icon">📐</div>
          <h2>Escanea. Mide. Presupuesta.</h2>
          <p className="text-muted" style={{ marginTop: 10 }}>
            Usa el LiDAR de tu iPhone para medir cualquier estancia en segundos
            y genera un presupuesto profesional en Word, PDF y Excel.
          </p>
        </div>

        {/* Feature pills */}
        <div className="home-features">
          <Feature icon="📡" label="LiDAR WebXR" />
          <Feature icon="📏" label="Cálculo m²" />
          <Feature icon="📄" label="Word · PDF · Excel" />
        </div>

        {/* Steps */}
        <div className="home-steps glass">
          <Step n={1} text="Pulsa «Iniciar escaneo» y apunta al suelo" />
          <Step n={2} text="Toca las 4 esquinas de la habitación" />
          <Step n={3} text="Rellena el presupuesto y exporta" />
        </div>

        {/* CTA */}
        <div className="home-cta">
          <button className="btn btn-primary btn-lg" onClick={onStart}>
            <span>Iniciar escaneo</span>
            <svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" />
            </svg>
          </button>
          <p className="text-muted" style={{ fontSize: 13, marginTop: 12 }}>
            Requiere iPhone 12 Pro o posterior con iOS 15+
          </p>
        </div>
      </div>
    </div>
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
