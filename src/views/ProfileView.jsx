import { useState } from 'react'
import { useLang, LANG_NAMES } from '../i18n/index.jsx'
import './ProfileView.css'

// ── Persistencia de datos de empresa ────────────────────────────────────────
function loadCompany() {
  try { return JSON.parse(localStorage.getItem('mr_company') || 'null') } catch { return null }
}
function saveCompany(data) {
  try { localStorage.setItem('mr_company', JSON.stringify(data)) } catch {}
}

const DEFAULT_COMPANY = {
  name: 'Zerbitecni',
  email: 'zerbitecni@email.com',
  phone: '',
  address: '',
  cif: '',
  defaultIva: 21,
}

function initials(name = '') {
  return name.trim().split(/\s+/).slice(0, 2).map(w => w[0]?.toUpperCase() || '').join('').slice(0, 2) || 'ZB'
}

// ── Componente principal ─────────────────────────────────────────────────────
export function ProfileView() {
  const { t, lang, setLang, langs } = useLang()
  const [company, setCompanyState] = useState(() => loadCompany() || DEFAULT_COMPANY)
  const [showSettings, setShowSettings]   = useState(false)
  const [showBilling,  setShowBilling]    = useState(false)

  function handleSaveCompany(updated) {
    saveCompany(updated)
    setCompanyState(updated)
    setShowSettings(false)
  }

  return (
    <div className="page">
      <div className="page-header">
        <h1>{t.profile.title}</h1>
      </div>

      <div className="page-content">

        {/* Avatar row — toca para editar */}
        <div className="profile-avatar-row glass" onClick={() => setShowSettings(true)} style={{ cursor: 'pointer' }}>
          <div className="profile-avatar">{initials(company.name)}</div>
          <div className="profile-avatar-info">
            <div className="profile-avatar-name">{company.name}</div>
            <div className="muted" style={{ fontSize: 12 }}>{company.email}</div>
            {company.phone && <div className="muted" style={{ fontSize: 12 }}>📞 {company.phone}</div>}
          </div>
          <span className="muted" style={{ fontSize: 20 }}>›</span>
        </div>

        {/* Idioma */}
        <div className="section-label">{t.profile.account}</div>
        <div className="profile-lang-row glass">
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <span style={{ fontSize: 20 }}>🌐</span>
            <span style={{ fontWeight: 600 }}>{t.profile.language}</span>
          </div>
          <div className="lang-pills">
            {langs.map((l) => (
              <button key={l} className={`lang-pill ${lang === l ? 'lang-pill-active' : ''}`} onClick={() => setLang(l)}>
                {LANG_NAMES[l]}
              </button>
            ))}
          </div>
        </div>

        {/* Settings + Billing */}
        <div className="profile-section">
          <ProfileRow icon="⚙️" label={t.profile.settings}  onClick={() => setShowSettings(true)} />
          <ProfileRow icon="👑" label={t.profile.billing}   onClick={() => setShowBilling(true)} />
        </div>

        {/* Ayuda */}
        <div className="section-label">{t.profile.help}</div>
        <div className="profile-section">
          <ProfileRow icon="🔄" label={t.profile.updates}    onClick={() => alert('mi-render v1.0.0 — estás al día')} />
          <ProfileRow icon="🤚" label={t.profile.helpCenter} onClick={() => alert('zerbitecni.com/ayuda')} />
          <ProfileRow icon="✨" label={t.profile.whatsNew}   onClick={() => alert('v1.0.0 — LiDAR, Fotogrametría, Walkthrough, Presupuestos')} />
          <ProfileRow icon="🐛" label={t.profile.reportBug}  onClick={() => window.open && window.open('mailto:hola@zerbitecni.com?subject=Bug en mi-render')} />
        </div>

        <div className="profile-version muted">mi-render v1.0.0 · Zerbitecni</div>
      </div>

      {/* ── Sheet Configuración ───────────────────────────────────────────── */}
      {showSettings && (
        <SettingsSheet
          company={company}
          onSave={handleSaveCompany}
          onClose={() => setShowSettings(false)}
        />
      )}

      {/* ── Sheet Facturación ─────────────────────────────────────────────── */}
      {showBilling && (
        <BillingSheet onClose={() => setShowBilling(false)} />
      )}
    </div>
  )
}

// ── Sheet Configuración de empresa ───────────────────────────────────────────
function SettingsSheet({ company, onSave, onClose }) {
  const [form, setForm] = useState({ ...company })
  const f = (key) => (e) => setForm(prev => ({ ...prev, [key]: e.target.value }))

  return (
    <div className="profile-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="profile-sheet">
        <div className="sheet-handle" />
        <div className="profile-sheet-header">
          <h3>Configuración de empresa</h3>
          <button className="sheet-close" onClick={onClose}>✕</button>
        </div>

        {/* Avatar preview */}
        <div style={{ display: 'flex', justifyContent: 'center', margin: '4px 0 16px' }}>
          <div className="profile-avatar profile-avatar-lg">{initials(form.name)}</div>
        </div>

        <div className="profile-form">
          <Field label="Nombre de empresa *">
            <input type="text" value={form.name} onChange={f('name')} placeholder="Ej. Zerbitecni" maxLength={80} />
          </Field>
          <Field label="Email de contacto">
            <input type="email" value={form.email} onChange={f('email')} placeholder="empresa@email.com" />
          </Field>
          <Field label="Teléfono">
            <input type="tel" value={form.phone} onChange={f('phone')} placeholder="+34 600 000 000" />
          </Field>
          <Field label="Dirección">
            <input type="text" value={form.address} onChange={f('address')} placeholder="Calle, número, ciudad" maxLength={120} />
          </Field>
          <Field label="CIF / NIF">
            <input type="text" value={form.cif} onChange={f('cif')} placeholder="B12345678" maxLength={12} />
          </Field>
          <Field label="IVA por defecto (%)">
            <input type="number" value={form.defaultIva} onChange={f('defaultIva')} min={0} max={100} step={1} style={{ maxWidth: 90 }} />
          </Field>
        </div>

        <div className="profile-sheet-actions">
          <button className="btn btn-ghost btn-sm" onClick={onClose}>Cancelar</button>
          <button className="btn btn-primary" onClick={() => onSave(form)} disabled={!form.name.trim()}>
            Guardar
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Sheet Facturación ─────────────────────────────────────────────────────────
function BillingSheet({ onClose }) {
  return (
    <div className="profile-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="profile-sheet">
        <div className="sheet-handle" />
        <div className="profile-sheet-header">
          <h3>Plan y facturación</h3>
          <button className="sheet-close" onClick={onClose}>✕</button>
        </div>

        {/* Plan actual */}
        <div className="billing-plan-card billing-plan-free glass">
          <div className="billing-plan-badge">Plan actual</div>
          <div className="billing-plan-name">Free</div>
          <div className="billing-plan-price">0 € / mes</div>
          <ul className="billing-plan-features">
            <li>✓ Escaneo LiDAR ilimitado</li>
            <li>✓ Presupuestos Word / PDF / Excel</li>
            <li>✓ Catálogo de reformas</li>
            <li>✓ Exportación 3D (OBJ, USDZ…)</li>
            <li>✓ Gestión de equipo local</li>
          </ul>
        </div>

        {/* Plan Pro */}
        <div className="billing-plan-card billing-plan-pro glass">
          <div className="billing-plan-badge billing-plan-badge-pro">Próximamente</div>
          <div className="billing-plan-name" style={{ color: '#a78bfa' }}>Pro</div>
          <div className="billing-plan-price">9,99 € / mes</div>
          <ul className="billing-plan-features">
            <li>✓ Todo lo del plan Free</li>
            <li>⬆ Sincronización en la nube</li>
            <li>⬆ Compartir proyectos con el equipo</li>
            <li>⬆ Plantillas de presupuesto personalizadas</li>
            <li>⬆ Soporte prioritario</li>
          </ul>
          <button className="btn btn-primary" style={{ width: '100%', marginTop: 12, opacity: 0.5 }} disabled>
            Próximamente disponible
          </button>
        </div>

        <button className="btn btn-ghost btn-sm" style={{ width: '100%', marginTop: 8 }} onClick={onClose}>
          Cerrar
        </button>
      </div>
    </div>
  )
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function ProfileRow({ icon, label, onClick }) {
  return (
    <div className="list-row" onClick={onClick} style={{ cursor: 'pointer' }}>
      <div className="list-row-icon">{icon}</div>
      <div className="list-row-body"><div className="list-row-title">{label}</div></div>
      <span className="list-row-chevron">›</span>
    </div>
  )
}

function Field({ label, children }) {
  return (
    <div className="form-field">
      <label>{label}</label>
      {children}
    </div>
  )
}
