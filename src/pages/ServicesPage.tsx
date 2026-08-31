import { FormEvent, useCallback, useEffect, useState } from 'react'
import { CalendarDays, Check, LogOut, Pencil, Plus, Radio, Save, Scissors, Settings, Trash2, UserRound, Users, X } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { AdminSidebar } from '../components/AdminSidebar'
import { supabase } from '../lib/supabase'
import type { Business, Service } from '../types'

type ServiceForm = { name: string; description: string; price: string; duration_minutes: string; active: boolean }
const emptyForm: ServiceForm = { name: '', description: '', price: '', duration_minutes: '30', active: true }

export function ServicesPage() {
  const navigate = useNavigate()
  const [business, setBusiness] = useState<Business | null>(null)
  const [services, setServices] = useState<Service[]>([])
  const [editing, setEditing] = useState<Service | null>(null)
  const [form, setForm] = useState<ServiceForm>(emptyForm)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const [realtimeConnected, setRealtimeConnected] = useState(false)

  useEffect(() => {
    async function init() {
      const { data } = await supabase.auth.getUser()
      if (!data.user) return navigate('/login')
      const { data: member } = await supabase.from('business_members').select('business_id').eq('user_id', data.user.id).maybeSingle()
      if (!member) return navigate('/onboarding')
      const { data: biz } = await supabase.from('businesses').select('*').eq('id', member.business_id).single()
      setBusiness(biz)
      setLoading(false)
    }
    init()
  }, [navigate])

  const loadServices = useCallback(async () => {
    if (!business) return
    const { data, error } = await supabase.from('services').select('*').eq('business_id', business.id).order('active', { ascending: false }).order('name')
    if (error) setMessage(error.message)
    else setServices((data || []) as Service[])
  }, [business])

  useEffect(() => { loadServices() }, [loadServices])
  useEffect(() => {
    if (!business) return
    const channel = supabase.channel(`services-crud:${business.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'services', filter: `business_id=eq.${business.id}` }, loadServices)
      .subscribe(status => setRealtimeConnected(status === 'SUBSCRIBED'))
    return () => { setRealtimeConnected(false); supabase.removeChannel(channel) }
  }, [business, loadServices])

  function startEdit(service: Service) {
    setEditing(service)
    setForm({ name: service.name, description: service.description || '', price: String(service.price).replace('.', ','), duration_minutes: String(service.duration_minutes), active: service.active })
    setMessage('')
  }
  function reset() { setEditing(null); setForm(emptyForm); setMessage('') }

  async function save(event: FormEvent) {
    event.preventDefault()
    if (!business) return
    const price = Number(form.price.replace(',', '.'))
    const duration = Number(form.duration_minutes)
    if (!form.name.trim() || !Number.isFinite(price) || price < 0 || !duration) return setMessage('Preencha nome, preço e duração corretamente.')
    setSaving(true); setMessage('')
    const payload = { business_id: business.id, name: form.name.trim(), description: form.description.trim() || null, price, duration_minutes: duration, active: form.active }
    const result = editing
      ? await supabase.from('services').update(payload).eq('id', editing.id).eq('business_id', business.id)
      : await supabase.from('services').insert(payload)
    setSaving(false)
    if (result.error) return setMessage(`Erro: ${result.error.message}`)
    setMessage(editing ? 'Serviço atualizado com sucesso.' : 'Serviço criado com sucesso.')
    reset(); await loadServices()
  }

  async function toggle(service: Service) {
    const { error } = await supabase.from('services').update({ active: !service.active }).eq('id', service.id)
    if (error) setMessage(error.message)
  }

  async function remove(service: Service) {
    if (!confirm(`Excluir o serviço “${service.name}”?`)) return
    const { error } = await supabase.from('services').delete().eq('id', service.id)
    if (error) {
      setMessage(error.code === '23503' ? 'Este serviço possui agendamentos. Desative-o para preservar o histórico.' : `Não foi possível excluir: ${error.message}`)
      return
    }
    if (editing?.id === service.id) reset()
    setMessage('Serviço excluído.')
  }

  async function logout() { await supabase.auth.signOut(); navigate('/login') }
  if (loading) return <div className="center-screen">Carregando serviços...</div>
  if (!business) return null

  return <main className="admin-page">
    <AdminSidebar businessName={business.name} current="services"/>

    <section className="admin-content crud-page">
      <div className="admin-head"><div><span className="eyebrow">CRUD</span><h1>Serviços</h1><div className="live-row"><span className={`live-badge ${realtimeConnected ? 'online' : 'connecting'}`}><Radio size={14}/>{realtimeConnected ? 'Tempo real ativo' : 'Conectando...'}</span></div></div><button className="button button-primary" onClick={reset}><Plus size={16}/>Novo serviço</button></div>
      {message && <div className="crm-feedback"><span>{message}</span><button onClick={() => setMessage('')}><X size={15}/></button></div>}
      <div className="crud-layout">
        <div className="table-card"><div className="table-head"><h2>Serviços cadastrados</h2><span>{services.length}</span></div><div className="table-wrap"><table><thead><tr><th>Serviço</th><th>Preço</th><th>Duração</th><th>Status</th><th>Ações</th></tr></thead><tbody>
          {services.map(service => <tr key={service.id}><td><strong>{service.name}</strong><small>{service.description || 'Sem descrição'}</small></td><td>R$ {Number(service.price).toFixed(2).replace('.', ',')}</td><td>{service.duration_minutes} min</td><td><button className={`crud-status ${service.active ? 'active' : 'inactive'}`} onClick={() => toggle(service)}>{service.active ? <Check size={13}/> : <X size={13}/>} {service.active ? 'Ativo' : 'Inativo'}</button></td><td className="actions"><button onClick={() => startEdit(service)}><Pencil size={14}/>Editar</button><button className="danger-action" onClick={() => remove(service)}><Trash2 size={14}/>Excluir</button></td></tr>)}
          {!services.length && <tr><td colSpan={5} className="empty-row">Nenhum serviço cadastrado.</td></tr>}
        </tbody></table></div></div>

        <form className="crud-form-card" onSubmit={save}><span className="eyebrow">{editing ? 'EDITAR' : 'CRIAR'}</span><h2>{editing ? editing.name : 'Novo serviço'}</h2>
          <label>Nome<input className="input" value={form.name} onChange={e => setForm({...form, name:e.target.value})} placeholder="Nome do serviço" /></label>
          <label>Descrição<textarea className="input" value={form.description} onChange={e => setForm({...form, description:e.target.value})} placeholder="Descrição opcional" /></label>
          <div className="crud-form-grid"><label>Preço (R$)<input className="input" inputMode="decimal" value={form.price} onChange={e => setForm({...form, price:e.target.value})} placeholder="45,00" /></label><label>Duração<select className="input" value={form.duration_minutes} onChange={e => setForm({...form, duration_minutes:e.target.value})}><option value="15">15 min</option><option value="30">30 min</option><option value="45">45 min</option><option value="60">60 min</option><option value="90">90 min</option><option value="120">120 min</option></select></label></div>
          <label className="crud-check"><input type="checkbox" checked={form.active} onChange={e => setForm({...form, active:e.target.checked})}/>Disponível para agendamento</label>
          <button className="button button-primary full" disabled={saving}><Save size={16}/>{saving ? 'Salvando...' : editing ? 'Salvar alterações' : 'Criar serviço'}</button>
          {editing && <button type="button" className="button button-ghost full" onClick={reset}>Cancelar edição</button>}
        </form>
      </div>
    </section>
  </main>
}
