import { ChangeEvent, FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { CalendarClock, Check, Image as ImageIcon, Mail, Pencil, Phone, Plus, Radio, Save, Search, Trash2, Upload, UserRound, Users, X } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { AdminSidebar } from '../components/AdminSidebar'
import { supabase } from '../lib/supabase'
import type { Business, Professional } from '../types'

type ProForm = {
  name: string
  bio: string
  photo_url: string
  phone: string
  email: string
  specialty: string
  commission_percent: string
  active: boolean
}

const emptyForm: ProForm = {
  name: '', bio: '', photo_url: '', phone: '', email: '', specialty: '', commission_percent: '0', active: true,
}

const BUCKET = 'business-assets'
const ALLOWED_TYPES = ['image/png', 'image/jpeg', 'image/webp']
const MAX_FILE_SIZE = 5 * 1024 * 1024

function cleanPhone(value: string) {
  return value.replace(/\D/g, '').slice(0, 15)
}
function formatPhone(value: string) {
  const d = cleanPhone(value)
  if (d.length <= 2) return d
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  if (d.length <= 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
  return d
}
function ext(file: File) {
  if (file.type === 'image/png') return 'png'
  if (file.type === 'image/webp') return 'webp'
  return 'jpg'
}

export function ProfessionalsPage() {
  const navigate = useNavigate()
  const photoInput = useRef<HTMLInputElement | null>(null)
  const [business, setBusiness] = useState<Business | null>(null)
  const [professionals, setProfessionals] = useState<Professional[]>([])
  const [editing, setEditing] = useState<Professional | null>(null)
  const [form, setForm] = useState<ProForm>(emptyForm)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [uploadingPhoto, setUploadingPhoto] = useState(false)
  const [message, setMessage] = useState('')
  const [realtimeConnected, setRealtimeConnected] = useState(false)
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState<'all' | 'active' | 'inactive'>('all')

  useEffect(() => { (async () => {
    const { data } = await supabase.auth.getUser()
    if (!data.user) return navigate('/login')
    const { data: member } = await supabase.from('business_members').select('business_id').eq('user_id', data.user.id).maybeSingle()
    if (!member) return navigate('/onboarding')
    const { data: biz } = await supabase.from('businesses').select('*').eq('id', member.business_id).single()
    setBusiness(biz)
    setLoading(false)
  })() }, [navigate])

  const load = useCallback(async () => {
    if (!business) return
    const { data, error } = await supabase.from('professionals').select('*').eq('business_id', business.id).order('active', { ascending:false }).order('name')
    if (error) setMessage(error.message)
    else setProfessionals((data || []) as Professional[])
  }, [business])

  useEffect(() => { load() }, [load])

  useEffect(() => {
    if (!business) return
    const channel = supabase
      .channel(`professionals-crud:${business.id}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'professionals',filter:`business_id=eq.${business.id}`},load)
      .subscribe(s => setRealtimeConnected(s === 'SUBSCRIBED'))
    return () => { setRealtimeConnected(false); supabase.removeChannel(channel) }
  }, [business, load])

  const filtered = useMemo(() => professionals.filter(pro => {
    const q = search.trim().toLowerCase()
    const matchSearch = !q || [pro.name, pro.specialty || '', pro.email || '', pro.phone || ''].some(v => v.toLowerCase().includes(q))
    const matchStatus = status === 'all' || (status === 'active' ? pro.active : !pro.active)
    return matchSearch && matchStatus
  }), [professionals, search, status])

  const metrics = useMemo(() => ({
    total: professionals.length,
    active: professionals.filter(p => p.active).length,
    inactive: professionals.filter(p => !p.active).length,
    avgCommission: professionals.length ? professionals.reduce((sum, p) => sum + Number(p.commission_percent || 0), 0) / professionals.length : 0,
  }), [professionals])

  function reset() {
    setEditing(null)
    setForm(emptyForm)
    setMessage('')
  }

  function startEdit(pro: Professional) {
    setEditing(pro)
    setForm({
      name: pro.name,
      bio: pro.bio || '',
      photo_url: pro.photo_url || '',
      phone: pro.phone || '',
      email: pro.email || '',
      specialty: pro.specialty || '',
      commission_percent: String(pro.commission_percent || 0),
      active: pro.active,
    })
    setMessage('')
  }

  async function uploadPhoto(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file || !business) return
    if (!ALLOWED_TYPES.includes(file.type)) return setMessage('A foto deve ser PNG, JPG ou WEBP.')
    if (file.size > MAX_FILE_SIZE) return setMessage('A foto deve ter no máximo 5 MB.')

    setUploadingPhoto(true)
    const path = `${business.id}/professionals/${crypto.randomUUID()}.${ext(file)}`
    const { error } = await supabase.storage.from(BUCKET).upload(path, file, {
      contentType: file.type, cacheControl: '31536000', upsert: false,
    })
    setUploadingPhoto(false)
    if (error) return setMessage(`Erro ao enviar foto: ${error.message}`)
    const { data } = supabase.storage.from(BUCKET).getPublicUrl(path)
    setForm(v => ({ ...v, photo_url: data.publicUrl }))
    setMessage('Foto enviada. Clique em salvar para concluir.')
  }

  async function save(e: FormEvent) {
    e.preventDefault()
    if (!business) return
    if (!form.name.trim()) return setMessage('Informe o nome do profissional.')
    if (form.email && !/^\S+@\S+\.\S+$/.test(form.email)) return setMessage('Informe um e-mail válido.')
    const commission = Number(form.commission_percent || 0)
    if (commission < 0 || commission > 100) return setMessage('A comissão deve estar entre 0% e 100%.')

    setSaving(true)
    const payload = {
      business_id: business.id,
      name: form.name.trim(),
      bio: form.bio.trim() || null,
      photo_url: form.photo_url || null,
      phone: cleanPhone(form.phone) || null,
      email: form.email.trim().toLowerCase() || null,
      specialty: form.specialty.trim() || null,
      commission_percent: commission,
      active: form.active,
    }
    const wasEditing = Boolean(editing)
    const result = editing
      ? await supabase.from('professionals').update(payload).eq('id', editing.id).eq('business_id', business.id)
      : await supabase.from('professionals').insert(payload)

    setSaving(false)
    if (result.error) return setMessage(`Erro: ${result.error.message}`)
    reset()
    await load()
    setMessage(wasEditing ? 'Profissional atualizado com sucesso.' : 'Profissional criado com sucesso.')
  }

  async function toggle(pro: Professional) {
    const { error } = await supabase.from('professionals').update({ active: !pro.active }).eq('id', pro.id).eq('business_id', business?.id)
    if (error) setMessage(error.message)
  }

  async function remove(pro: Professional) {
    if (!confirm(`Excluir o profissional “${pro.name}”?`)) return
    const { error } = await supabase.from('professionals').delete().eq('id', pro.id).eq('business_id', business?.id)
    if (error) {
      setMessage(error.code === '23503' ? 'Este profissional possui agendamentos. Desative-o para preservar o histórico.' : `Não foi possível excluir: ${error.message}`)
      return
    }
    if (editing?.id === pro.id) reset()
    setMessage('Profissional excluído.')
  }

  if (loading) return <div className="center-screen">Carregando profissionais...</div>
  if (!business) return null

  return <main className="admin-page">
    <AdminSidebar businessName={business.name} current="professionals"/>
    <section className="admin-content crud-page professionals-v421">
      <div className="admin-head">
        <div>
          <span className="eyebrow">EQUIPE PROFISSIONAL</span>
          <h1>Profissionais</h1>
          <div className="live-row"><span className={`live-badge ${realtimeConnected ? 'online' : 'connecting'}`}><Radio size={14}/>{realtimeConnected ? 'Tempo real ativo' : 'Conectando...'}</span></div>
        </div>
        <button className="button button-primary" onClick={reset}><Plus size={16}/>Novo profissional</button>
      </div>

      {message && <div className="crm-feedback"><span>{message}</span><button onClick={() => setMessage('')}><X size={15}/></button></div>}

      <div className="professional-kpis">
        <div><Users size={18}/><span>Total</span><strong>{metrics.total}</strong></div>
        <div><Check size={18}/><span>Ativos</span><strong>{metrics.active}</strong></div>
        <div><X size={18}/><span>Inativos</span><strong>{metrics.inactive}</strong></div>
        <div><span className="percent-symbol">%</span><span>Comissão média</span><strong>{metrics.avgCommission.toFixed(1).replace('.', ',')}%</strong></div>
      </div>

      <div className="professional-toolbar">
        <label className="professional-search"><Search size={16}/><input value={search} onChange={e => setSearch(e.target.value)} placeholder="Buscar profissional, especialidade, telefone..."/></label>
        <select className="input" value={status} onChange={e => setStatus(e.target.value as typeof status)}>
          <option value="all">Todos</option>
          <option value="active">Ativos</option>
          <option value="inactive">Inativos</option>
        </select>
      </div>

      <div className="crud-layout">
        <div className="table-card">
          <div className="table-head"><h2>Equipe</h2><span>{filtered.length}</span></div>
          <div className="professional-cards-mobile">
            {filtered.map(pro => <article className="professional-mobile-card" key={pro.id}>
              <div className="professional-mobile-head">
                <span className="crud-avatar">{pro.photo_url ? <img src={pro.photo_url} alt={pro.name}/> : pro.name.slice(0,1).toUpperCase()}</span>
                <div><strong>{pro.name}</strong><small>{pro.specialty || 'Profissional'}</small></div>
                <button className={`crud-status ${pro.active ? 'active' : 'inactive'}`} onClick={() => toggle(pro)}>{pro.active ? 'Ativo' : 'Inativo'}</button>
              </div>
              <div className="professional-mobile-meta">
                {pro.phone && <span><Phone size={13}/>{formatPhone(pro.phone)}</span>}
                {pro.email && <span><Mail size={13}/>{pro.email}</span>}
                <span>Comissão: {Number(pro.commission_percent || 0).toFixed(1).replace('.', ',')}%</span>
              </div>
              <div className="professional-mobile-actions">
                <button onClick={() => startEdit(pro)}><Pencil size={14}/>Editar</button>
                <button onClick={() => navigate(`/painel/disponibilidade?professional=${pro.id}`)}><CalendarClock size={14}/>Jornada</button>
                <button className="danger-action" onClick={() => remove(pro)}><Trash2 size={14}/>Excluir</button>
              </div>
            </article>)}
            {!filtered.length && <div className="empty-row">Nenhum profissional encontrado.</div>}
          </div>

          <div className="table-wrap professionals-table-desktop"><table>
            <thead><tr><th>Profissional</th><th>Contato</th><th>Especialidade</th><th>Comissão</th><th>Status</th><th>Ações</th></tr></thead>
            <tbody>
              {filtered.map(pro => <tr key={pro.id}>
                <td><div className="crud-person"><span className="crud-avatar">{pro.photo_url ? <img src={pro.photo_url} alt={pro.name}/> : pro.name.slice(0,1).toUpperCase()}</span><div><strong>{pro.name}</strong><small>{pro.bio || '—'}</small></div></div></td>
                <td><div className="professional-contact-cell">{pro.phone ? <span><Phone size={13}/>{formatPhone(pro.phone)}</span> : <span>—</span>}{pro.email && <small><Mail size={12}/>{pro.email}</small>}</div></td>
                <td>{pro.specialty || '—'}</td>
                <td><strong>{Number(pro.commission_percent || 0).toFixed(1).replace('.', ',')}%</strong></td>
                <td><button className={`crud-status ${pro.active ? 'active' : 'inactive'}`} onClick={() => toggle(pro)}>{pro.active ? <Check size={13}/> : <X size={13}/>} {pro.active ? 'Ativo' : 'Inativo'}</button></td>
                <td className="actions"><button onClick={() => startEdit(pro)}><Pencil size={14}/>Editar</button><button onClick={() => navigate(`/painel/disponibilidade?professional=${pro.id}`)}><CalendarClock size={14}/>Jornada</button><button className="danger-action" onClick={() => remove(pro)}><Trash2 size={14}/>Excluir</button></td>
              </tr>)}
              {!filtered.length && <tr><td colSpan={6} className="empty-row">Nenhum profissional encontrado.</td></tr>}
            </tbody>
          </table></div>
        </div>

        <form className="crud-form-card professional-form-v421" onSubmit={save}>
          <span className="eyebrow">{editing ? 'EDITAR' : 'CRIAR'}</span>
          <h2>{editing ? editing.name : 'Novo profissional'}</h2>

          <div className="professional-photo-upload">
            <div className="professional-photo-preview">{form.photo_url ? <img src={form.photo_url} alt="Preview"/> : <UserRound size={34}/>}</div>
            <div><strong>Foto do profissional</strong><small>PNG, JPG ou WEBP • máximo 5 MB</small><button type="button" className="button button-secondary" disabled={uploadingPhoto} onClick={() => photoInput.current?.click()}><Upload size={15}/>{uploadingPhoto ? 'Enviando...' : form.photo_url ? 'Trocar foto' : 'Enviar foto'}</button>{form.photo_url && <button type="button" className="button button-ghost" onClick={() => setForm(v => ({ ...v, photo_url: '' }))}>Remover</button>}</div>
            <input ref={photoInput} type="file" hidden accept="image/png,image/jpeg,image/webp" onChange={uploadPhoto}/>
          </div>

          <label>Nome<input className="input" value={form.name} onChange={e => setForm({...form,name:e.target.value})} placeholder="Nome do profissional"/></label>
          <label>Especialidade<input className="input" value={form.specialty} onChange={e => setForm({...form,specialty:e.target.value})} placeholder="Ex.: Barbeiro, cabelo e barba"/></label>
          <div className="form-grid">
            <label>Telefone<input className="input" inputMode="tel" value={form.phone} onChange={e => setForm({...form,phone:formatPhone(e.target.value)})} placeholder="(17) 99999-9999"/></label>
            <label>E-mail<input className="input" type="email" value={form.email} onChange={e => setForm({...form,email:e.target.value})} placeholder="profissional@email.com"/></label>
          </div>
          <label>Bio<textarea className="input" value={form.bio} onChange={e => setForm({...form,bio:e.target.value})} placeholder="Especialidades, experiência, apresentação..."/></label>
          <label>Comissão padrão (%)<input className="input" type="number" min="0" max="100" step="0.1" value={form.commission_percent} onChange={e => setForm({...form,commission_percent:e.target.value})}/><small className="field-hint">Usada nos indicadores financeiros e relatórios.</small></label>
          <label className="crud-check"><input type="checkbox" checked={form.active} onChange={e => setForm({...form,active:e.target.checked})}/>Disponível para agendamento</label>
          <button className="button button-primary full" disabled={saving || uploadingPhoto}><Save size={16}/>{saving ? 'Salvando...' : editing ? 'Salvar alterações' : 'Criar profissional'}</button>
          {editing && <button type="button" className="button button-ghost full" onClick={reset}>Cancelar edição</button>}
        </form>
      </div>
    </section>
  </main>
}
