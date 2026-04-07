import { useLang, LANG_NAMES } from '../i18n/index.jsx'
import './ProfileView.css'

export function ProfileView() {
  const { t, lang, setLang, langs } = useLang()

  return (
    <div className="page">
      <div className="page-header">
        <h1>{t.profile.title}</h1>
      </div>

      <div className="page-content">
        {/* Avatar row */}
        <div className="profile-avatar-row glass">
          <div className="profile-avatar">ZB</div>
          <div className="profile-avatar-info">
            <div className="profile-avatar-name">Zerbitecni</div>
            <div className="muted" style={{ fontSize: 12 }}>zerbitecni@email.com</div>
          </div>
          <span className="muted" style={{ fontSize: 20 }}>›</span>
        </div>

        {/* Language selector */}
        <div className="section-label">{t.profile.account}</div>

        <div className="profile-lang-row glass">
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <span style={{ fontSize: 20 }}>🌐</span>
            <span style={{ fontWeight: 600 }}>{t.profile.language}</span>
          </div>
          <div className="lang-pills">
            {langs.map((l) => (
              <button
                key={l}
                className={`lang-pill ${lang === l ? 'lang-pill-active' : ''}`}
                onClick={() => setLang(l)}
              >
                {LANG_NAMES[l]}
              </button>
            ))}
          </div>
        </div>

        {/* Settings rows */}
        <div className="profile-section">
          {[
            { icon: '⚙️', label: t.profile.settings },
            { icon: '👑', label: t.profile.billing },
          ].map((item) => (
            <ProfileRow key={item.label} icon={item.icon} label={item.label} />
          ))}
        </div>

        <div className="section-label">{t.profile.help}</div>
        <div className="profile-section">
          {[
            { icon: '🔄', label: t.profile.updates },
            { icon: '🤚', label: t.profile.helpCenter },
            { icon: '✨', label: t.profile.whatsNew },
            { icon: '🐛', label: t.profile.reportBug },
          ].map((item) => (
            <ProfileRow key={item.label} icon={item.icon} label={item.label} />
          ))}
        </div>

        <div className="profile-version muted">
          mi-render v1.0.0 · Zerbitecni
        </div>
      </div>
    </div>
  )
}

function ProfileRow({ icon, label }) {
  return (
    <div className="list-row">
      <div className="list-row-icon">{icon}</div>
      <div className="list-row-body">
        <div className="list-row-title">{label}</div>
      </div>
      <span className="list-row-chevron">›</span>
    </div>
  )
}
