import { useState } from 'react'
import './TeamView.css'

const ROLES = ['Responsable', 'Pintor', 'Electricista', 'Fontanero', 'Carpintero', 'Albañil', 'Comercial', 'Otro']

function loadMembers() {
  try { return JSON.parse(localStorage.getItem('mr_team') || '[]') } catch { return [] }
}
function saveMembers(list) {
  try { localStorage.setItem('mr_team', JSON.stringify(list)) } catch {}
}

function initials(name = '') {
  return name.trim().split(/\s+/).slice(0, 2).map(w => w[0]?.toUpperCase() || '').join('') || '?'
}

const AVATAR_COLORS = ['#6c8fff','#f0a500','#2dd4bf','#a78bfa','#f87171','#34d399','#fb923c','#e879f9']
function avatarColor(name = '') {
  let h = 0; for (const c of name) h = (h * 31 + c.charCodeAt(0)) & 0xfffff
  return AVATAR_COLORS[h % AVATAR_COLORS.length]
}

export function TeamView() {
  const [members, setMembers] = useState(loadMembers)
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing]  = useState(null)   // member object | null
  const [form, setForm]        = useState({ name: '', role: ROLES[0], phone: '', email: '' })

  function openAdd() {
    setForm({ name: '', role: ROLES[0], phone: '', email: '' })
    setEditing(null)
    setShowForm(true)
  }

  function openEdit(member) {
    setForm({ name: member.name, role: member.role, phone: member.phone || '', email: member.email || '' })
    setEditing(member)
    setShowForm(true)
  }

  function handleSave() {
    if (!form.name.trim()) return
    let updated
    if (editing) {
      updated = members.map(m => m.id === editing.id ? { ...m, ...form } : m)
    } else {
      updated = [...members, { id: Date.now(), ...form }]
    }
    saveMembers(updated)
    setMembers(updated)
    setShowForm(false)
  }

  function handleDelete(id) {
    const updated = members.filter(m => m.id !== id)
    saveMembers(updated)
    setMembers(updated)
    setShowForm(false)
  }

  return (
    <div className="page">
      <div className="page-header">
        <h1>Equipo</h1>
        <button className="btn btn-ghost btn-sm" onClick={openAdd}>+ Añadir</button>
      </div>

      <div className="page-content">
        {members.length === 0 ? (
          <div className="team-empty">
            <div className="team-empty-icon">👥</div>
            <p className="team-empty-title">Sin miembros todavía</p>
            <p className="muted" style={{ fontSize: 13 }}>Añade a tu equipo para tenerlos localizados</p>
            <button className="btn btn-primary" style={{ marginTop: 16 }} onClick={openAdd}>
              + Añadir primer miembro
            </button>
          </div>
        ) : (
          <>
            <div className="team-list">
              {members.map(m => (
                <div key={m.id} className="team-card glass" onClick={() => openEdit(m)}>
                  <div className="team-avatar" style={{ background: avatarColor(m.name) + '33', border: `2px solid ${avatarColor(m.name)}66`, color: avatarColor(m.name) }}>
                    {initials(m.name)}
                  </div>
                  <div className="team-card-body">
                    <div className="team-card-name">{m.name}</div>
                    <div className="team-card-role muted">{m.role}</div>
                    <div className="team-card-contacts">
                      {m.phone && (
                        <a className="team-contact-btn" href={`tel:${m.phone}`} onClick={e => e.stopPropagation()}>
                          📞 {m.phone}
                        </a>
                      )}
                      {m.email && (
                        <a className="team-contact-btn" href={`mailto:${m.email}`} onClick={e => e.stopPropagation()}>
                          ✉️ {m.email}
                        </a>
                      )}
                    </div>
                  </div>
                  <span className="muted" style={{ fontSize: 20 }}>›</span>
                </div>
              ))}
            </div>
            <p className="muted" style={{ fontSize: 12, textAlign: 'center', padding: '12px 0' }}>
              {members.length} {members.length === 1 ? 'miembro' : 'miembros'} en el equipo
            </p>
          </>
        )}
      </div>

      {/* Sheet añadir / editar */}
      {showForm && (
        <div className="team-overlay" onClick={e => e.target === e.currentTarget && setShowForm(false)}>
          <div className="team-sheet">
            <div className="sheet-handle" />
            <div className="team-sheet-header">
              <h3>{editing ? 'Editar miembro' : 'Nuevo miembro'}</h3>
              <button className="sheet-close" onClick={() => setShowForm(false)}>✕</button>
            </div>

            {/* Avatar preview */}
            <div style={{ display: 'flex', justifyContent: 'center', margin: '8px 0 16px' }}>
              <div className="team-avatar team-avatar-lg"
                style={{ background: avatarColor(form.name) + '33', border: `3px solid ${avatarColor(form.name)}88`, color: avatarColor(form.name) }}>
                {initials(form.name) || '?'}
              </div>
            </div>

            <div className="team-form">
              <div className="form-field">
                <label>Nombre *</label>
                <input type="text" placeholder="Ej. Ana García" value={form.name}
                  onChange={e => setForm(f => ({ ...f, name: e.target.value }))} maxLength={80} autoFocus />
              </div>
              <div className="form-field">
                <label>Rol</label>
                <select value={form.role} onChange={e => setForm(f => ({ ...f, role: e.target.value }))}>
                  {ROLES.map(r => <option key={r} value={r}>{r}</option>)}
                </select>
              </div>
              <div className="form-field">
                <label>Teléfono</label>
                <input type="tel" placeholder="+34 600 000 000" value={form.phone}
                  onChange={e => setForm(f => ({ ...f, phone: e.target.value }))} />
              </div>
              <div className="form-field">
                <label>Email</label>
                <input type="email" placeholder="nombre@empresa.com" value={form.email}
                  onChange={e => setForm(f => ({ ...f, email: e.target.value }))} />
              </div>
            </div>

            <div className="team-sheet-actions">
              {editing && (
                <button className="btn btn-ghost btn-sm" style={{ color: 'var(--color-danger)' }}
                  onClick={() => handleDelete(editing.id)}>
                  Eliminar
                </button>
              )}
              <button className="btn btn-ghost btn-sm" onClick={() => setShowForm(false)}>Cancelar</button>
              <button className="btn btn-primary" onClick={handleSave} disabled={!form.name.trim()}>
                {editing ? 'Guardar' : 'Añadir'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
