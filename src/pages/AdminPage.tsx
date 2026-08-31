import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import { CalendarDays, CheckCircle2, Clock3, LogOut, Pencil, Plus, Radio, Save, Scissors, Settings, Trash2, UserRound, Users, X } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { AdminSidebar } from '../components/AdminSidebar'
import { supabase } from '../lib/supabase'
import type { Appointment, Business, Professional, Service } from '../types'

const localDateISO = () => {
  const now = new Date(); const offset = now.getTimezoneOffset()
  return new Date(now.getTime() - offset * 60_000).toISOString().slice(0, 10)
}
const today = localDateISO()
const toMinutes=(time:string)=>{const[h,m]=time.slice(0,5).split(':').map(Number);return h*60+m}
const fromMinutes=(minutes:number)=>`${String(Math.floor(minutes/60)).padStart(2,'0')}:${String(minutes%60).padStart(2,'0')}`

type AppointmentForm={client_name:string;client_phone:string;service_id:string;professional_id:string;appointment_date:string;start_time:string;status:Appointment['status'];notes:string;discount_amount:string;final_amount:string;payment_status:'unpaid'|'paid'|'refunded';payment_method:string}
const emptyForm=(date=today):AppointmentForm=>({client_name:'',client_phone:'',service_id:'',professional_id:'',appointment_date:date,start_time:'',status:'confirmed',notes:'',discount_amount:'0',final_amount:'',payment_status:'unpaid',payment_method:''})

export function AdminPage() {
  const navigate = useNavigate()
  const [business, setBusiness] = useState<Business | null>(null)
  const [appointments, setAppointments] = useState<Appointment[]>([])
  const [services,setServices]=useState<Service[]>([])
  const [professionals,setProfessionals]=useState<Professional[]>([])
  const [loading, setLoading] = useState(true)
  const [filterDate, setFilterDate] = useState(today)
  const [realtimeConnected, setRealtimeConnected] = useState(false)
  const [lastLiveUpdate, setLastLiveUpdate] = useState<Date | null>(null)
  const [creating,setCreating]=useState(false)
  const [editing,setEditing]=useState<Appointment|null>(null)
  const [form,setForm]=useState<AppointmentForm>(emptyForm())
  const [saving,setSaving]=useState(false)
  const [message,setMessage]=useState('')

  useEffect(() => { (async()=>{
    const { data } = await supabase.auth.getUser(); if (!data.user) return navigate('/login')
    const { data: owner } = await supabase.from('business_members').select('business_id').eq('user_id', data.user.id).maybeSingle()
    if (!owner) { navigate('/onboarding', { replace: true }); return }
    const { data: businessData } = await supabase.from('businesses').select('*').eq('id', owner.business_id).single()
    setBusiness(businessData); setLoading(false)
  })() }, [navigate])

  const loadCatalog=useCallback(async()=>{
    if(!business)return
    const[{data:s},{data:p}]=await Promise.all([
      supabase.from('services').select('*').eq('business_id',business.id).order('active',{ascending:false}).order('name'),
      supabase.from('professionals').select('*').eq('business_id',business.id).order('active',{ascending:false}).order('name')
    ])
    setServices((s||[]) as Service[]);setProfessionals((p||[]) as Professional[])
  },[business])
  useEffect(()=>{loadCatalog()},[loadCatalog])

  const loadAppointments = useCallback(async () => {
    if (!business) return
    const { data, error } = await supabase.from('appointments').select('*, services(name, price), professionals(name)').eq('business_id', business.id).eq('appointment_date', filterDate).order('start_time')
    if (error) { setMessage(error.message); return }
    setAppointments((data as Appointment[]) || [])
  }, [business, filterDate])
  useEffect(() => { loadAppointments() }, [loadAppointments])

  useEffect(() => {
    if (!business) return
    const channel = supabase.channel(`admin-appointments:${business.id}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'appointments',filter:`business_id=eq.${business.id}`},(payload:any)=>{
        const row=(payload.new&&Object.keys(payload.new).length?payload.new:payload.old) as {appointment_date?:string}
        if(row.appointment_date===filterDate)loadAppointments();setLastLiveUpdate(new Date())
      })
      .on('postgres_changes',{event:'*',schema:'public',table:'services',filter:`business_id=eq.${business.id}`},loadCatalog)
      .on('postgres_changes',{event:'*',schema:'public',table:'professionals',filter:`business_id=eq.${business.id}`},loadCatalog)
      .subscribe(status=>setRealtimeConnected(status==='SUBSCRIBED'))
    return()=>{setRealtimeConnected(false);supabase.removeChannel(channel)}
  },[business,filterDate,loadAppointments,loadCatalog])

  const confirmed = appointments.filter(a => a.status === 'confirmed')
  const upcomingConfirmed = confirmed.filter(a => filterDate !== today || a.start_time.slice(0, 5) >= new Date().toTimeString().slice(0, 5)).sort((a,b)=>a.start_time.localeCompare(b.start_time))
  const revenue = useMemo(() => confirmed.reduce((sum,item)=>sum+Number(item.services?.price||0),0), [confirmed])

  async function updateStatus(id:string,status:Appointment['status']){const{error}=await supabase.from('appointments').update({status}).eq('id',id);if(error)setMessage(error.message);else setAppointments(prev=>prev.map(a=>a.id===id?{...a,status}:a))}

  function newAppointment(){setEditing(null);setCreating(true);setForm(emptyForm(filterDate));setMessage('')}
  function editAppointment(item:Appointment){setCreating(false);setEditing(item);setForm({client_name:item.client_name,client_phone:item.client_phone,service_id:item.service_id,professional_id:item.professional_id,appointment_date:item.appointment_date,start_time:item.start_time.slice(0,5),status:item.status,notes:item.notes||'',discount_amount:String(item.discount_amount||0),final_amount:item.final_amount==null?'':String(item.final_amount),payment_status:item.payment_status||'unpaid',payment_method:item.payment_method||''});setMessage('')}
  function closeForm(){setCreating(false);setEditing(null);setForm(emptyForm(filterDate))}

  async function saveAppointment(e:FormEvent){
    e.preventDefault(); if(!business)return
    const service=services.find(s=>s.id===form.service_id)
    if(!form.client_name.trim()||!form.client_phone.trim()||!service||!form.professional_id||!form.appointment_date||!form.start_time)return setMessage('Preencha todos os campos obrigatórios.')
    const endTime=fromMinutes(toMinutes(form.start_time)+service.duration_minutes)
    const discount=Math.max(0,Number(form.discount_amount||0)); const finalAmount=form.final_amount===''?Math.max(0,Number(service.price)-discount):Math.max(0,Number(form.final_amount)); const payload={business_id:business.id,client_name:form.client_name.trim(),client_phone:form.client_phone.trim(),service_id:form.service_id,professional_id:form.professional_id,appointment_date:form.appointment_date,start_time:form.start_time,end_time:endTime,status:form.status,notes:form.notes.trim()||null,discount_amount:discount,final_amount:finalAmount,payment_status:form.payment_status,payment_method:form.payment_method||null}
    setSaving(true)
    const result=editing?await supabase.from('appointments').update(payload).eq('id',editing.id).eq('business_id',business.id):await supabase.from('appointments').insert(payload)
    setSaving(false)
    if(result.error){setMessage(result.error.message.includes('appointments_no_overlap')?'Este profissional já possui atendimento neste intervalo.':`Erro: ${result.error.message}`);return}
    setFilterDate(form.appointment_date);closeForm();setMessage(editing?'Agendamento atualizado.':'Agendamento criado.');await loadAppointments()
  }

  async function deleteAppointment(item:Appointment){if(!confirm(`Excluir definitivamente o agendamento de ${item.client_name} às ${item.start_time.slice(0,5)}?`))return;const{error}=await supabase.from('appointments').delete().eq('id',item.id);if(error)return setMessage(`Não foi possível excluir: ${error.message}`);if(editing?.id===item.id)closeForm();setMessage('Agendamento excluído.');await loadAppointments()}
  async function logout(){await supabase.auth.signOut();navigate('/login')}

  if (loading) return <div className="center-screen">Carregando painel...</div>
  if (!business) return <div className="center-screen"><div className="empty-card"><p>Carregando empresa...</p></div></div>

  return <main className="admin-page">
    <AdminSidebar businessName={business.name} current="agenda"/>
    <section className="admin-content">
      <div className="admin-head"><div><span className="eyebrow">PAINEL • CRUD</span><h1>Agenda do dia</h1><div className="live-row"><span className={`live-badge ${realtimeConnected?'online':'connecting'}`}><Radio size={14}/>{realtimeConnected?'Tempo real ativo':'Conectando...'}</span>{lastLiveUpdate&&<small>Atualizado às {lastLiveUpdate.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit',second:'2-digit'})}</small>}</div></div><div className="admin-head-actions"><input className="input date-filter" type="date" value={filterDate} onChange={e=>setFilterDate(e.target.value)}/><button className="button button-primary" onClick={newAppointment}><Plus size={16}/>Novo agendamento</button></div></div>
      {message&&<div className="crm-feedback"><span>{message}</span><button onClick={()=>setMessage('')}><X size={15}/></button></div>}
      <div className="stats-grid"><article className="stat-card"><CalendarDays/><div><small>Agendamentos</small><strong>{appointments.length}</strong></div></article><article className="stat-card"><CheckCircle2/><div><small>Confirmados</small><strong>{confirmed.length}</strong></div></article><article className="stat-card"><Clock3/><div><small>Próximo horário</small><strong>{upcomingConfirmed[0]?.start_time?.slice(0,5)||'--:--'}</strong></div></article><article className="stat-card"><span className="money">R$</span><div><small>Faturamento previsto</small><strong>R$ {revenue.toFixed(2).replace('.',',')}</strong></div></article></div>
      <div className={`agenda-crud-layout ${(creating||editing)?'with-form':''}`}><div className="table-card"><div className="table-head"><h2>Agendamentos</h2><span>{filterDate.split('-').reverse().join('/')}</span></div><div className="table-wrap"><table><thead><tr><th>Horário</th><th>Cliente</th><th>Serviço</th><th>Profissional</th><th>Status</th><th>Pagamento</th><th>Ações</th></tr></thead><tbody>{appointments.map(item=><tr key={item.id}><td><strong>{item.start_time.slice(0,5)}</strong><small>até {item.end_time.slice(0,5)}</small></td><td>{item.client_name}<small>{item.client_phone}</small></td><td>{item.services?.name||'-'}</td><td>{item.professionals?.name||'-'}</td><td><span className={`status status-${item.status}`}>{item.status}</span></td><td><span className={`payment-badge ${item.payment_status||'unpaid'}`}>{item.payment_status==='paid'?'Pago':item.payment_status==='refunded'?'Estornado':'Pendente'}</span><small>{item.payment_method||''}</small></td><td className="actions crud-actions"><button onClick={()=>editAppointment(item)}><Pencil size={14}/>Editar</button>{item.status!=='completed'&&item.status!=='cancelled'&&item.status!=='no_show'&&<button onClick={()=>updateStatus(item.id,'completed')}>Concluir</button>}{item.status!=='cancelled'&&item.status!=='no_show'&&<button onClick={()=>updateStatus(item.id,'no_show')}>Não veio</button>}{item.status!=='cancelled'&&<button onClick={()=>updateStatus(item.id,'cancelled')}>Cancelar</button>}<button className="danger-action" onClick={()=>deleteAppointment(item)}><Trash2 size={14}/>Excluir</button></td></tr>)}{appointments.length===0&&<tr><td colSpan={7} className="empty-row">Nenhum agendamento nesta data.</td></tr>}</tbody></table></div></div>
      {(creating||editing)&&<form className="crud-form-card appointment-form-card" onSubmit={saveAppointment}><div className="crud-form-title"><div><span className="eyebrow">{editing?'EDITAR':'CRIAR'}</span><h2>{editing?'Editar agendamento':'Novo agendamento'}</h2></div><button type="button" onClick={closeForm}><X size={18}/></button></div><label>Cliente<input className="input" value={form.client_name} onChange={e=>setForm({...form,client_name:e.target.value})}/></label><label>Telefone<input className="input" value={form.client_phone} onChange={e=>setForm({...form,client_phone:e.target.value})}/></label><label>Serviço<select className="input" value={form.service_id} onChange={e=>setForm({...form,service_id:e.target.value})}><option value="">Selecione</option>{services.map(s=><option key={s.id} value={s.id} disabled={!s.active}>{s.name}{!s.active?' (inativo)':''}</option>)}</select></label><label>Profissional<select className="input" value={form.professional_id} onChange={e=>setForm({...form,professional_id:e.target.value})}><option value="">Selecione</option>{professionals.map(p=><option key={p.id} value={p.id} disabled={!p.active}>{p.name}{!p.active?' (inativo)':''}</option>)}</select></label><div className="crud-form-grid"><label>Data<input className="input" type="date" min={editing?undefined:today} value={form.appointment_date} onChange={e=>setForm({...form,appointment_date:e.target.value})}/></label><label>Início<input className="input" type="time" value={form.start_time} onChange={e=>setForm({...form,start_time:e.target.value})}/></label></div><label>Status<select className="input" value={form.status} onChange={e=>setForm({...form,status:e.target.value as Appointment['status']})}><option value="pending">Pendente</option><option value="confirmed">Confirmado</option><option value="completed">Concluído</option><option value="cancelled">Cancelado</option><option value="no_show">Não compareceu</option></select></label><div className="crud-form-grid"><label>Desconto (R$)<input className="input" type="number" min="0" step="0.01" value={form.discount_amount} onChange={e=>setForm({...form,discount_amount:e.target.value})}/></label><label>Valor final (R$)<input className="input" type="number" min="0" step="0.01" value={form.final_amount} onChange={e=>setForm({...form,final_amount:e.target.value})} placeholder="Automático"/></label></div><div className="crud-form-grid"><label>Pagamento<select className="input" value={form.payment_status} onChange={e=>setForm({...form,payment_status:e.target.value as AppointmentForm['payment_status']})}><option value="unpaid">Pendente</option><option value="paid">Pago</option><option value="refunded">Estornado</option></select></label><label>Forma<select className="input" value={form.payment_method} onChange={e=>setForm({...form,payment_method:e.target.value})}><option value="">Não informado</option><option value="pix">Pix</option><option value="cash">Dinheiro</option><option value="credit_card">Crédito</option><option value="debit_card">Débito</option><option value="other">Outro</option></select></label></div><label>Observações<textarea className="input" value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></label><button className="button button-primary full" disabled={saving}><Save size={16}/>{saving?'Salvando...':editing?'Salvar alterações':'Criar agendamento'}</button></form>}</div>
    </section>
  </main>
}
