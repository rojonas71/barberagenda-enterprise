import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Ban,
  Cake,
  CalendarDays,
  CheckCircle2,
  Clock4,
  DollarSign,
  Download,
  Filter,
  LogOut,
  Mail,
  Phone,
  Plus,
  Radio,
  Repeat2,
  Save,
  Scissors,
  Search,
  Star,
  StickyNote,
  Tag,
  TrendingUp,
  Trash2,
  Settings,
  UserPlus,
  UserRound,
  Users,
  X,
  XCircle
} from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { AdminSidebar } from '../components/AdminSidebar'
import { supabase } from '../lib/supabase'
import type { Business, ClientHistoryItem, ClientNote, ClientSummary } from '../types'

const money = (value: number | string | null | undefined) =>
  `R$ ${Number(value || 0).toFixed(2).replace('.', ',')}`

const dateBR = (value: string | null | undefined) =>
  value ? value.split('-').reverse().join('/') : '—'

const dateTimeBR = (value: string) =>
  new Date(value).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })

const statusLabel: Record<string, string> = {
  pending: 'Pendente',
  confirmed: 'Confirmado',
  completed: 'Concluído',
  cancelled: 'Cancelado',
  no_show: 'Não compareceu'
}

type SegmentFilter = 'all' | 'vip' | 'recurring' | 'new' | 'inactive' | 'no_show' | 'birthday' | 'blocked'
type SortOption = 'recent' | 'name' | 'spent' | 'visits' | 'inactive'

type ClientForm = {
  name: string
  phone: string
  email: string
  birthday: string
  tags: string
  source: string
  notes: string
  marketing_opt_in: boolean
  blocked: boolean
}

const emptyForm: ClientForm = {
  name: '',
  phone: '',
  email: '',
  birthday: '',
  tags: '',
  source: 'cadastro_manual',
  notes: '',
  marketing_opt_in: false,
  blocked: false
}

function tagsFromText(value: string) {
  return Array.from(new Set(value.split(',').map(item => item.trim()).filter(Boolean))).slice(0, 12)
}

function segmentOf(client: ClientSummary) {
  if (client.blocked) return { key: 'blocked', label: 'Bloqueado', className: 'danger' }
  if (Number(client.total_spent) >= 500 || Number(client.completed_appointments) >= 8) return { key: 'vip', label: 'VIP', className: 'vip' }
  if (Number(client.completed_appointments) >= 3) return { key: 'recurring', label: 'Recorrente', className: 'success' }
  if (Number(client.total_appointments) <= 1) return { key: 'new', label: 'Novo', className: 'info' }
  if ((client.days_since_last ?? 0) > 60 && !client.next_appointment_date) return { key: 'inactive', label: 'Inativo', className: 'warning' }
  return { key: 'active', label: 'Ativo', className: 'neutral' }
}

function isBirthdayMonth(client: ClientSummary) {
  if (!client.birthday) return false
  const month = Number(client.birthday.split('-')[1])
  return month === new Date().getMonth() + 1
}


export function ClientsPage() {
  const navigate = useNavigate()
  const [business, setBusiness] = useState<Business | null>(null)
  const [clients, setClients] = useState<ClientSummary[]>([])
  const [selected, setSelected] = useState<ClientSummary | null>(null)
  const [history, setHistory] = useState<ClientHistoryItem[]>([])
  const [clientNotes, setClientNotes] = useState<ClientNote[]>([])
  const [search, setSearch] = useState('')
  const [segment, setSegment] = useState<SegmentFilter>('all')
  const [sort, setSort] = useState<SortOption>('recent')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [creating, setCreating] = useState(false)
  const [form, setForm] = useState<ClientForm>(emptyForm)
  const [newNote, setNewNote] = useState('')
  const [noteSaving, setNoteSaving] = useState(false)
  const [feedback, setFeedback] = useState('')
  const [realtimeConnected, setRealtimeConnected] = useState(false)

  useEffect(() => {
    async function loadSession() {
      const { data } = await supabase.auth.getUser()
      if (!data.user) return navigate('/login')

      const { data: member } = await supabase
        .from('business_members')
        .select('business_id')
        .eq('user_id', data.user.id)
        .maybeSingle()

      if (!member) {
        navigate('/onboarding', { replace: true })
        return
      }

      const { data: businessData } = await supabase
        .from('businesses')
        .select('*')
        .eq('id', member.business_id)
        .single()

      setBusiness(businessData)
      setLoading(false)
    }

    loadSession()
  }, [navigate])

  const loadClients = useCallback(async () => {
    if (!business) return
    const { data, error } = await supabase.rpc('get_clients_with_stats', {
      p_business_id: business.id
    })

    if (error) {
      console.error(error)
      setFeedback('Não foi possível carregar o CRM. Execute supabase/clients-pro-upgrade.sql.')
      return
    }

    const next = (data || []) as ClientSummary[]
    setClients(next)
    setSelected(current => current ? next.find(item => item.id === current.id) || current : current)
  }, [business])

  useEffect(() => {
    loadClients()
  }, [loadClients])

  const loadClientDetails = useCallback(async (clientId: string) => {
    const [historyResult, notesResult] = await Promise.all([
      supabase.rpc('get_client_history', { p_client_id: clientId }),
      supabase
        .from('client_notes')
        .select('*')
        .eq('client_id', clientId)
        .order('created_at', { ascending: false })
    ])

    if (!historyResult.error) setHistory((historyResult.data || []) as ClientHistoryItem[])
    if (!notesResult.error) setClientNotes((notesResult.data || []) as ClientNote[])
  }, [])

  useEffect(() => {
    if (!business) return

    const refresh = () => loadClients()
    const channel = supabase
      .channel(`admin-client-crm:${business.id}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'clients', filter: `business_id=eq.${business.id}` }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments', filter: `business_id=eq.${business.id}` }, payload => {
        refresh()
        const row = (payload.new || payload.old) as { client_id?: string }
        if (selected?.id && row.client_id === selected.id) loadClientDetails(selected.id)
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'client_notes', filter: `business_id=eq.${business.id}` }, payload => {
        const row = (payload.new || payload.old) as { client_id?: string }
        if (selected?.id && row.client_id === selected.id) loadClientDetails(selected.id)
      })
      .subscribe((status: string) => setRealtimeConnected(status === 'SUBSCRIBED'))

    return () => {
      setRealtimeConnected(false)
      supabase.removeChannel(channel)
    }
  }, [business, loadClients, loadClientDetails, selected?.id])

  function fillForm(client: ClientSummary) {
    setForm({
      name: client.name,
      phone: client.phone,
      email: client.email || '',
      birthday: client.birthday || '',
      tags: (client.tags || []).join(', '),
      source: client.source || 'agendamento_online',
      notes: client.notes || '',
      marketing_opt_in: Boolean(client.marketing_opt_in),
      blocked: Boolean(client.blocked)
    })
  }

  async function openClient(client: ClientSummary) {
    setCreating(false)
    setSelected(client)
    fillForm(client)
    setFeedback('')
    await loadClientDetails(client.id)
  }

  function startCreate() {
    setSelected(null)
    setHistory([])
    setClientNotes([])
    setForm(emptyForm)
    setCreating(true)
    setFeedback('')
  }

  async function saveClient() {
    if (!business) return
    if (!form.name.trim() || !form.phone.trim()) {
      setFeedback('Nome e telefone são obrigatórios.')
      return
    }

    setSaving(true)
    setFeedback('')
    const payload = {
      business_id: business.id,
      name: form.name.trim(),
      phone: form.phone.trim(),
      phone_normalized: form.phone.replace(/\D/g, '') || form.phone.trim().toLowerCase(),
      email: form.email.trim() || null,
      birthday: form.birthday || null,
      tags: tagsFromText(form.tags),
      source: form.source,
      notes: form.notes.trim() || null,
      marketing_opt_in: form.marketing_opt_in,
      blocked: form.blocked,
      updated_at: new Date().toISOString()
    }

    if (creating) {
      const { data, error } = await supabase.from('clients').insert(payload).select('id').single()
      setSaving(false)
      if (error) {
        setFeedback(error.code === '23505' ? 'Já existe um cliente com este telefone.' : `Erro ao criar cliente: ${error.message}`)
        return
      }
      await loadClients()
      setCreating(false)
      setFeedback('Cliente criado com sucesso.')
      if (data?.id) {
        const { data: created } = await supabase.rpc('get_clients_with_stats', { p_business_id: business.id })
        const client = ((created || []) as ClientSummary[]).find(item => item.id === data.id)
        if (client) await openClient(client)
      }
      return
    }

    if (!selected) return
    const { error } = await supabase.from('clients').update(payload).eq('id', selected.id)
    setSaving(false)
    if (error) {
      setFeedback(error.code === '23505' ? 'Este telefone já pertence a outro cliente.' : `Erro ao salvar: ${error.message}`)
      return
    }
    setFeedback('Dados do cliente atualizados.')
    await loadClients()
  }

  async function addInternalNote() {
    if (!business || !selected || !newNote.trim()) return
    setNoteSaving(true)
    const { data: auth } = await supabase.auth.getUser()
    const { error } = await supabase.from('client_notes').insert({
      business_id: business.id,
      client_id: selected.id,
      content: newNote.trim(),
      created_by: auth.user?.id || null
    })
    setNoteSaving(false)
    if (error) {
      setFeedback(`Não foi possível adicionar a nota: ${error.message}`)
      return
    }
    setNewNote('')
    await loadClientDetails(selected.id)
  }

  async function deleteClient() {
    if (!selected) return
    if (!confirm(`Excluir o cliente “${selected.name}”? O histórico de agendamentos será preservado, mas o vínculo com o CRM será removido.`)) return
    const { error } = await supabase.from('clients').delete().eq('id', selected.id)
    if (error) {
      setFeedback(`Não foi possível excluir: ${error.message}`)
      return
    }
    setSelected(null)
    setHistory([])
    setClientNotes([])
    setForm(emptyForm)
    setFeedback('Cliente excluído do CRM.')
    await loadClients()
  }

  async function logout() {
    await supabase.auth.signOut()
    navigate('/login')
  }

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase()
    const digits = term.replace(/\D/g, '')
    let result = clients.filter(client => {
      const matchesSearch = !term ||
        client.name.toLowerCase().includes(term) ||
        client.phone.toLowerCase().includes(term) ||
        Boolean(digits && client.phone.replace(/\D/g, '').includes(digits)) ||
        Boolean(client.email?.toLowerCase().includes(term)) ||
        (client.tags || []).some(tag => tag.toLowerCase().includes(term))

      if (!matchesSearch) return false
      if (segment === 'all') return true
      if (segment === 'vip') return Number(client.total_spent) >= 500 || Number(client.completed_appointments) >= 8
      if (segment === 'recurring') return Number(client.completed_appointments) >= 3
      if (segment === 'new') return Number(client.total_appointments) <= 1
      if (segment === 'inactive') return (client.days_since_last ?? 0) > 60 && !client.next_appointment_date
      if (segment === 'no_show') return Number(client.no_show_appointments) > 0
      if (segment === 'birthday') return isBirthdayMonth(client)
      if (segment === 'blocked') return client.blocked
      return true
    })

    result = [...result].sort((a, b) => {
      if (sort === 'name') return a.name.localeCompare(b.name, 'pt-BR')
      if (sort === 'spent') return Number(b.total_spent) - Number(a.total_spent)
      if (sort === 'visits') return Number(b.completed_appointments) - Number(a.completed_appointments)
      if (sort === 'inactive') return Number(b.days_since_last || 0) - Number(a.days_since_last || 0)
      return new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()
    })

    return result
  }, [clients, search, segment, sort])

  const metrics = useMemo(() => {
    const totalRevenue = clients.reduce((sum, client) => sum + Number(client.total_spent || 0), 0)
    const completed = clients.reduce((sum, client) => sum + Number(client.completed_appointments || 0), 0)
    return {
      recurring: clients.filter(client => Number(client.completed_appointments) >= 3).length,
      inactive: clients.filter(client => (client.days_since_last ?? 0) > 60 && !client.next_appointment_date).length,
      birthdays: clients.filter(isBirthdayMonth).length,
      revenue: totalRevenue,
      averageTicket: completed ? totalRevenue / completed : 0,
      noShow: clients.reduce((sum, client) => sum + Number(client.no_show_appointments || 0), 0)
    }
  }, [clients])

  function exportCsv() {
    const rows = [
      ['Nome', 'Telefone', 'Email', 'Aniversario', 'Tags', 'Visitas concluidas', 'No-show', 'Total gasto', 'Ticket medio', 'Ultima visita', 'Proximo horario', 'Origem', 'Marketing', 'Bloqueado'],
      ...filtered.map(client => [
        client.name,
        client.phone,
        client.email || '',
        client.birthday || '',
        (client.tags || []).join(' | '),
        String(client.completed_appointments),
        String(client.no_show_appointments),
        Number(client.total_spent || 0).toFixed(2),
        Number(client.average_ticket || 0).toFixed(2),
        client.last_appointment_date || '',
        client.next_appointment_date || '',
        client.source || '',
        client.marketing_opt_in ? 'sim' : 'nao',
        client.blocked ? 'sim' : 'nao'
      ])
    ]
    const csv = '\uFEFF' + rows.map(row => row.map(cell => `"${String(cell).replace(/"/g, '""')}"`).join(';')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `clientes-${business?.slug || 'barberagenda'}-${new Date().toISOString().slice(0, 10)}.csv`
    link.click()
    URL.revokeObjectURL(url)
  }

  if (loading) return <div className="center-screen">Carregando clientes...</div>
  if (!business) return <div className="center-screen"><div className="empty-card"><p>Carregando empresa...</p></div></div>

  const selectedSegment = selected ? segmentOf(selected) : null

  return (
    <main className="admin-page">
      <AdminSidebar businessName={business.name} current="clients"/>

      <section className="admin-content client-crm-page">
        <div className="admin-head clients-head">
          <div>
            <span className="eyebrow">CRM PROFISSIONAL</span>
            <h1>Clientes</h1>
            <div className="live-row">
              <span className={`live-badge ${realtimeConnected ? 'online' : 'connecting'}`}>
                <Radio size={14}/>{realtimeConnected ? 'CRM em tempo real' : 'Conectando...'}
              </span>
              <small>Histórico, relacionamento e fidelização em um só lugar</small>
            </div>
          </div>
          <div className="crm-head-actions">
            <button className="button button-ghost" onClick={exportCsv}><Download size={16}/>Exportar CSV</button>
            <button className="button button-primary" onClick={startCreate}><UserPlus size={16}/>Novo cliente</button>
          </div>
        </div>

        {feedback && <div className="crm-feedback"><span>{feedback}</span><button onClick={() => setFeedback('')}><X size={15}/></button></div>}

        <div className="stats-grid client-stats pro-client-stats">
          <article className="stat-card"><Users/><div><small>Total de clientes</small><strong>{clients.length}</strong></div></article>
          <article className="stat-card"><Repeat2/><div><small>Recorrentes</small><strong>{metrics.recurring}</strong></div></article>
          <article className="stat-card"><Clock4/><div><small>Inativos +60 dias</small><strong>{metrics.inactive}</strong></div></article>
          <article className="stat-card"><Cake/><div><small>Aniversariantes</small><strong>{metrics.birthdays}</strong></div></article>
          <article className="stat-card"><DollarSign/><div><small>Receita concluída</small><strong>{money(metrics.revenue)}</strong></div></article>
          <article className="stat-card"><TrendingUp/><div><small>Ticket médio</small><strong>{money(metrics.averageTicket)}</strong></div></article>
        </div>

        <div className="crm-toolbar">
          <div className="search-box"><Search size={18}/><input placeholder="Buscar nome, telefone, e-mail ou tag" value={search} onChange={e => setSearch(e.target.value)} /></div>
          <label className="filter-control"><Filter size={16}/><select value={segment} onChange={e => setSegment(e.target.value as SegmentFilter)}>
            <option value="all">Todos os clientes</option>
            <option value="vip">VIP</option>
            <option value="recurring">Recorrentes</option>
            <option value="new">Novos</option>
            <option value="inactive">Inativos +60 dias</option>
            <option value="no_show">Com no-show</option>
            <option value="birthday">Aniversariantes do mês</option>
            <option value="blocked">Bloqueados</option>
          </select></label>
          <label className="filter-control"><TrendingUp size={16}/><select value={sort} onChange={e => setSort(e.target.value as SortOption)}>
            <option value="recent">Atualizados recentemente</option>
            <option value="name">Nome A-Z</option>
            <option value="spent">Maior valor gasto</option>
            <option value="visits">Mais visitas</option>
            <option value="inactive">Mais tempo sem voltar</option>
          </select></label>
        </div>

        <div className="clients-layout clients-layout-pro">
          <div className="table-card clients-table-card">
            <div className="table-head"><h2>Base de clientes</h2><span>{filtered.length} de {clients.length}</span></div>
            <div className="table-wrap">
              <table className="clients-table clients-table-pro">
                <thead><tr><th>Cliente</th><th>Segmento</th><th>Visitas</th><th>No-show</th><th>Total gasto</th><th>Última visita</th><th>Próximo horário</th></tr></thead>
                <tbody>
                  {filtered.map(client => {
                    const clientSegment = segmentOf(client)
                    return (
                      <tr key={client.id} className={selected?.id === client.id ? 'row-selected' : ''} onClick={() => openClient(client)}>
                        <td>
                          <div className="crm-client-cell"><span className="mini-avatar">{client.name.slice(0, 1).toUpperCase()}</span><div><strong>{client.name}</strong><small>{client.phone}{client.email ? ` • ${client.email}` : ''}</small><div className="row-tags">{(client.tags || []).slice(0, 2).map(tag => <span key={tag}>{tag}</span>)}</div></div></div>
                        </td>
                        <td><span className={`segment-badge ${clientSegment.className}`}>{clientSegment.label}</span></td>
                        <td><strong>{client.completed_appointments}</strong><small>{client.total_appointments} agend.</small></td>
                        <td><span className={Number(client.no_show_appointments) ? 'no-show-count has' : 'no-show-count'}>{client.no_show_appointments}</span></td>
                        <td><strong>{money(client.total_spent)}</strong><small>médio {money(client.average_ticket)}</small></td>
                        <td>{dateBR(client.last_appointment_date)}<small>{client.days_since_last != null ? `${client.days_since_last} dias atrás` : 'sem visita'}</small></td>
                        <td>{dateBR(client.next_appointment_date)}</td>
                      </tr>
                    )
                  })}
                  {filtered.length === 0 && <tr><td colSpan={7} className="empty-row">Nenhum cliente encontrado para este filtro.</td></tr>}
                </tbody>
              </table>
            </div>
          </div>

          <aside className="client-detail-card client-detail-pro">
            {!selected && !creating ? (
              <div className="client-empty-detail">
                <UserRound size={34}/>
                <h3>Perfil 360° do cliente</h3>
                <p>Selecione um cliente para ver histórico, preferências, valor, notas e relacionamento.</p>
                <button className="button button-primary" onClick={startCreate}><Plus size={16}/>Cadastrar cliente</button>
              </div>
            ) : (
              <>
                <div className="client-detail-head pro-detail-head">
                  <div className="client-avatar">{creating ? <Plus size={20}/> : selected?.name.slice(0, 1).toUpperCase()}</div>
                  <div className="detail-title"><span className="eyebrow">{creating ? 'NOVO CADASTRO' : 'PERFIL DO CLIENTE'}</span><h2>{creating ? 'Novo cliente' : selected?.name}</h2>{selected && <span>{selected.phone}</span>}</div>
                  {selectedSegment && <span className={`segment-badge ${selectedSegment.className}`}>{selectedSegment.label}</span>}
                </div>

                {selected && (
                  <div className="client-actions-row client-actions-pro">
                    <a className="button button-ghost" href={`tel:${selected.phone.replace(/\D/g, '')}`}><Phone size={16}/>Ligar</a>
                    {selected.email && <a className="button button-ghost" href={`mailto:${selected.email}`}><Mail size={16}/>E-mail</a>}
                  </div>
                )}

                {selected && (
                  <div className="client-mini-stats pro-mini-stats">
                    <div><small>Visitas concluídas</small><strong>{selected.completed_appointments}</strong></div>
                    <div><small>Total gasto</small><strong>{money(selected.total_spent)}</strong></div>
                    <div><small>Ticket médio</small><strong>{money(selected.average_ticket)}</strong></div>
                    <div><small>No-show</small><strong className={Number(selected.no_show_appointments) ? 'danger-text' : ''}>{selected.no_show_appointments}</strong></div>
                  </div>
                )}

                {selected && (selected.favorite_service_name || selected.favorite_professional_name) && (
                  <div className="preference-box">
                    <div><Star size={15}/><span><small>Serviço favorito</small><strong>{selected.favorite_service_name || '—'}</strong></span></div>
                    <div><UserRound size={15}/><span><small>Profissional preferido</small><strong>{selected.favorite_professional_name || '—'}</strong></span></div>
                  </div>
                )}

                <div className="client-form-grid">
                  <label className="client-field">Nome completo<input className="input" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Nome do cliente" /></label>
                  <label className="client-field">Telefone<input className="input" value={form.phone} onChange={e => setForm({ ...form, phone: e.target.value })} placeholder="(17) 99999-9999" /></label>
                  <label className="client-field">E-mail<input className="input" type="email" value={form.email} onChange={e => setForm({ ...form, email: e.target.value })} placeholder="cliente@email.com" /></label>
                  <label className="client-field">Aniversário<input className="input" type="date" value={form.birthday} onChange={e => setForm({ ...form, birthday: e.target.value })} /></label>
                  <label className="client-field full-span"><span className="field-label-icon"><Tag size={13}/>Tags</span><input className="input" value={form.tags} onChange={e => setForm({ ...form, tags: e.target.value })} placeholder="VIP, barba, mensal, indicação" /><small>Separe as tags por vírgula.</small></label>
                  <label className="client-field">Origem<select className="input" value={form.source} onChange={e => setForm({ ...form, source: e.target.value })}><option value="agendamento_online">Agendamento online</option><option value="cadastro_manual">Cadastro manual</option><option value="instagram">Instagram</option><option value="google">Google</option><option value="indicacao">Indicação</option><option value="outro">Outro</option></select></label>
                  <div className="client-field crm-checks">
                    <label><input type="checkbox" checked={form.marketing_opt_in} onChange={e => setForm({ ...form, marketing_opt_in: e.target.checked })}/><span><Mail size={14}/>Aceita comunicações</span></label>
                    <label className={form.blocked ? 'danger-check' : ''}><input type="checkbox" checked={form.blocked} onChange={e => setForm({ ...form, blocked: e.target.checked })}/><span><Ban size={14}/>Bloquear cliente</span></label>
                  </div>
                  <label className="client-field full-span">Observações gerais<textarea className="input client-notes" value={form.notes} onChange={e => setForm({ ...form, notes: e.target.value })} placeholder="Preferências, alergias informadas, estilo de corte, observações de atendimento..." /></label>
                </div>

                <button className="button button-primary full" onClick={saveClient} disabled={saving}><Save size={16}/>{saving ? 'Salvando...' : creating ? 'Criar cliente' : 'Salvar alterações'}</button>
                {selected && <button className="button danger-button full crm-delete-client" onClick={deleteClient}><Trash2 size={16}/>Excluir cliente</button>}

                {creating && <button className="button button-ghost full crm-cancel-create" onClick={() => { setCreating(false); setForm(emptyForm) }}>Cancelar cadastro</button>}

                {selected && (
                  <>
                    {selected.birthday && isBirthdayMonth(selected) && (
                      <div className="birthday-callout"><Cake size={18}/><span><strong>Aniversariante do mês</strong><small>Cliente faz aniversário neste mês</small></span></div>
                    )}

                    <div className="internal-notes-section">
                      <div className="section-title"><div><StickyNote size={17}/><h3>Notas internas</h3></div><span>{clientNotes.length}</span></div>
                      <div className="note-composer"><textarea className="input" value={newNote} onChange={e => setNewNote(e.target.value)} placeholder="Registre uma conversa, preferência ou observação importante..." maxLength={2000}/><button className="button button-secondary" onClick={addInternalNote} disabled={noteSaving || !newNote.trim()}>{noteSaving ? 'Adicionando...' : 'Adicionar nota'}</button></div>
                      <div className="notes-timeline">
                        {clientNotes.map(note => <div className="note-item" key={note.id}><span className="note-dot"/><div><p>{note.content}</p><small>{dateTimeBR(note.created_at)}</small></div></div>)}
                        {!clientNotes.length && <p className="muted">Nenhuma nota interna registrada.</p>}
                      </div>
                    </div>

                    <div className="client-history">
                      <div className="section-title"><div><CalendarDays size={17}/><h3>Histórico de atendimentos</h3></div><span>{history.length}</span></div>
                      {history.map(item => (
                        <div className="history-item history-item-pro" key={item.appointment_id}>
                          <div className={`history-icon ${item.status}`}>
                            {item.status === 'cancelled' ? <XCircle size={17}/> : item.status === 'no_show' ? <Ban size={17}/> : <Scissors size={17}/>}
                          </div>
                          <div className="history-main"><strong>{item.service_name}</strong><small>{item.professional_name} • {dateBR(item.appointment_date)} • {item.start_time.slice(0,5)}–{item.end_time.slice(0,5)}</small>{item.appointment_notes && <small className="appointment-note">{item.appointment_notes}</small>}</div>
                          <div className="history-price"><strong>{money(item.service_price)}</strong><small className={`history-status ${item.status}`}>{statusLabel[item.status] || item.status}</small></div>
                        </div>
                      ))}
                      {history.length === 0 && <p className="muted">Nenhum atendimento encontrado.</p>}
                    </div>

                    <div className="crm-client-metadata">
                      <span><CalendarDays size={14}/>Primeiro agendamento: <strong>{dateBR(selected.first_appointment_date)}</strong></span>
                      <span><Clock4 size={14}/>Última visita: <strong>{dateBR(selected.last_appointment_date)}</strong></span>
                      <span><CheckCircle2 size={14}/>Próximo: <strong>{dateBR(selected.next_appointment_date)}</strong></span>
                    </div>
                  </>
                )}
              </>
            )}
          </aside>
        </div>
      </section>
    </main>
  )
}
