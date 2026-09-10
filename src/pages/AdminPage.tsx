import { FormEvent, useCallback, useEffect, useMemo, useState } from 'react'
import {
  CalendarDays,
  CheckCircle2,
  Clock3,
  Filter,
  MoreHorizontal,
  Plus,
  Radio,
  RefreshCw,
  Save,
  UserRound,
  X,
  Wifi,
  WifiOff
} from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { AdminSidebar } from '../components/AdminSidebar'
import { supabase } from '../lib/supabase'
import { getPendingOfflineCount } from '../lib/offline'
import type { Appointment, Business, Professional, Service } from '../types'

const localDateISO = () => { const now = new Date(); const offset = now.getTimezoneOffset(); return new Date(now.getTime() - offset * 60000).toISOString().slice(0, 10) }
const today = localDateISO()
const toMinutes = (time: string) => { const [h, m] = time.slice(0, 5).split(':').map(Number); return h * 60 + m }
const fromMinutes = (minutes: number) => `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`
const newUUID = () => typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; const v = c === 'x' ? r : (r & 3) | 8; return v.toString(16) })

type AppointmentForm = { client_name:string; client_phone:string; service_id:string; professional_id:string; appointment_date:string; start_time:string; status:Appointment['status']; notes:string; discount_amount:string; final_amount:string; payment_status:'unpaid'|'paid'|'refunded'; payment_method:string }
const emptyForm = (date=today):AppointmentForm => ({ client_name:'', client_phone:'', service_id:'', professional_id:'', appointment_date:date, start_time:'', status:'confirmed', notes:'', discount_amount:'0', final_amount:'', payment_status:'unpaid', payment_method:'' })

const statusLabel: Record<Appointment['status'], string> = { pending:'Pendente', confirmed:'Confirmado', completed:'Concluído', cancelled:'Cancelado', no_show:'Não compareceu' }
const statusClass: Record<Appointment['status'], string> = { pending:'status-pending', confirmed:'status-confirmed', completed:'status-completed', cancelled:'status-cancelled', no_show:'status-no-show' }

export function AdminPage() {
  const navigate = useNavigate()
  const [business,setBusiness]=useState<Business|null>(null)
  const [appointments,setAppointments]=useState<Appointment[]>([])
  const [services,setServices]=useState<Service[]>([])
  const [professionals,setProfessionals]=useState<Professional[]>([])
  const [loading,setLoading]=useState(true)
  const [filterDate,setFilterDate]=useState(today)
  const [professionalFilter,setProfessionalFilter]=useState('all')
  const [online,setOnline]=useState(typeof navigator==='undefined'?true:navigator.onLine)
  const [realtimeConnected,setRealtimeConnected]=useState(false)
  const [pendingOffline,setPendingOffline]=useState(0)
  const [lastLiveUpdate,setLastLiveUpdate]=useState<Date|null>(null)
  const [creating,setCreating]=useState(false)
  const [editing,setEditing]=useState<Appointment|null>(null)
  const [form,setForm]=useState<AppointmentForm>(emptyForm())
  const [saving,setSaving]=useState(false)
  const [message,setMessage]=useState('')

  const refreshQueue=useCallback(async()=>setPendingOffline(await getPendingOfflineCount()),[])

  useEffect(()=>{
    const onOnline=()=>setOnline(true), onOffline=()=>setOnline(false), onQueue=()=>void refreshQueue(), onSync=()=>void refreshQueue()
    window.addEventListener('online',onOnline); window.addEventListener('offline',onOffline); window.addEventListener('barberagenda:offline-queue',onQueue); window.addEventListener('barberagenda:offline-sync',onSync)
    void refreshQueue(); return()=>{window.removeEventListener('online',onOnline);window.removeEventListener('offline',onOffline);window.removeEventListener('barberagenda:offline-queue',onQueue);window.removeEventListener('barberagenda:offline-sync',onSync)}
  },[refreshQueue])

  useEffect(()=>{ (async()=>{
    const {data}=await supabase.auth.getUser(); if(!data.user){navigate('/login');return}
    const {data:member}=await supabase.from('business_members').select('business_id').eq('user_id',data.user.id).maybeSingle()
    if(!member){navigate('/onboarding',{replace:true});return}
    const {data:b}=await supabase.from('businesses').select('*').eq('id',member.business_id).single()
    setBusiness(b); setLoading(false)
  })() },[navigate])

  const loadCatalog=useCallback(async()=>{ if(!business)return; const [{data:s},{data:p}]=await Promise.all([
    supabase.from('services').select('*').eq('business_id',business.id).order('active',{ascending:false}).order('name'),
    supabase.from('professionals').select('*').eq('business_id',business.id).order('active',{ascending:false}).order('name')
  ]); setServices((s||[]) as Service[]); setProfessionals((p||[]) as Professional[]) },[business])
  useEffect(()=>{void loadCatalog()},[loadCatalog])

  const loadAppointments=useCallback(async()=>{ if(!business)return
    const {data,error}=await supabase.from('appointments').select('*, services(name, price), professionals(name)').eq('business_id',business.id).eq('appointment_date',filterDate).order('start_time')
    if(error){setMessage(error.message);return}
    setAppointments((data||[]) as Appointment[]); await refreshQueue()
  },[business,filterDate,refreshQueue])
  useEffect(()=>{void loadAppointments()},[loadAppointments])

  useEffect(()=>{ if(!business)return
    const channel=supabase.channel(`admin-appointments-v4-4:${business.id}`)
      .on('postgres_changes',{event:'*',schema:'public',table:'appointments',filter:`business_id=eq.${business.id}`},(payload:any)=>{
        const row=(payload.new&&Object.keys(payload.new).length?payload.new:payload.old) as {appointment_date?:string}
        if(row.appointment_date===filterDate)void loadAppointments(); setLastLiveUpdate(new Date())
      })
      .on('postgres_changes',{event:'*',schema:'public',table:'services',filter:`business_id=eq.${business.id}`},()=>void loadCatalog())
      .on('postgres_changes',{event:'*',schema:'public',table:'professionals',filter:`business_id=eq.${business.id}`},()=>void loadCatalog())
      .subscribe(status=>setRealtimeConnected(status==='SUBSCRIBED'))
    return()=>{setRealtimeConnected(false);void supabase.removeChannel(channel)}
  },[business,filterDate,loadAppointments,loadCatalog])

  useEffect(()=>{ if(!online)return; const timer=window.setTimeout(()=>void loadAppointments(),350); return()=>window.clearTimeout(timer) },[online,loadAppointments])

  const visibleAppointments=useMemo(()=>appointments.filter(a=>professionalFilter==='all'||a.professional_id===professionalFilter).sort((a,b)=>a.start_time.localeCompare(b.start_time)),[appointments,professionalFilter])
  const active=visibleAppointments.filter(a=>a.status==='pending'||a.status==='confirmed')
  const confirmed=visibleAppointments.filter(a=>a.status==='confirmed')
  const next=active.find(a=>filterDate!==today||a.start_time.slice(0,5)>=new Date().toTimeString().slice(0,5))
  const revenue=useMemo(()=>confirmed.reduce((sum,a)=>sum+Number(a.final_amount ?? a.services?.price ?? 0),0),[confirmed])

  const mergeOptimistic=(item:Appointment)=>setAppointments(prev=>[...prev.filter(a=>a.id!==item.id),item].sort((a,b)=>a.start_time.localeCompare(b.start_time)))
  const offlineMessage=()=>setMessage('Sem internet: alteração salva na fila local e será sincronizada automaticamente.')

  async function updateStatus(id:string,status:Appointment['status']){
    const previous=appointments.find(a=>a.id===id); if(!previous)return
    setAppointments(prev=>prev.map(a=>a.id===id?{...a,status,updated_at:new Date().toISOString()}:a))
    const {error}=await supabase.from('appointments').update({status,updated_at:new Date().toISOString()}).eq('id',id).eq('business_id',business?.id||'')
    if(error){setAppointments(prev=>prev.map(a=>a.id===id?previous:a));setMessage(error.message);return}
    await refreshQueue(); if(!online)offlineMessage(); else setMessage(`Status atualizado para ${statusLabel[status]}.`)
  }

  function newAppointment(){setEditing(null);setCreating(true);setForm(emptyForm(filterDate));setMessage('')}
  function editAppointment(item:Appointment){setCreating(false);setEditing(item);setForm({client_name:item.client_name,client_phone:item.client_phone,service_id:item.service_id,professional_id:item.professional_id,appointment_date:item.appointment_date,start_time:item.start_time.slice(0,5),status:item.status,notes:item.notes||'',discount_amount:String(item.discount_amount||0),final_amount:item.final_amount==null?'':String(item.final_amount),payment_status:item.payment_status||'unpaid',payment_method:item.payment_method||''});setMessage('')}
  function closeForm(){setCreating(false);setEditing(null);setForm(emptyForm(filterDate))}

  async function saveAppointment(e:FormEvent){ e.preventDefault(); if(!business)return
    const service=services.find(s=>s.id===form.service_id)
    if(!form.client_name.trim()||!form.client_phone.trim()||!service||!form.professional_id||!form.appointment_date||!form.start_time){setMessage('Preencha todos os campos obrigatórios.');return}
    const endTime=fromMinutes(toMinutes(form.start_time)+service.duration_minutes)
    const discount=Math.max(0,Number(form.discount_amount||0)); const finalAmount=form.final_amount===''?Math.max(0,Number(service.price)-discount):Math.max(0,Number(form.final_amount))
    const id=editing?.id||newUUID(); const now=new Date().toISOString()
    const payload={id,business_id:business.id,client_name:form.client_name.trim(),client_phone:form.client_phone.trim(),service_id:form.service_id,professional_id:form.professional_id,appointment_date:form.appointment_date,start_time:form.start_time,end_time:endTime,status:form.status,notes:form.notes.trim()||null,discount_amount:discount,final_amount:finalAmount,payment_status:form.payment_status,payment_method:form.payment_method||null,updated_at:now}
    const optimistic={...payload,created_at:editing?.created_at||now,services:{name:service.name,price:Number(service.price)},professionals:{name:professionals.find(p=>p.id===form.professional_id)?.name||'Profissional'}} as Appointment
    setSaving(true); mergeOptimistic(optimistic)
    const result=editing?await supabase.from('appointments').update(payload).eq('id',editing.id).eq('business_id',business.id):await supabase.from('appointments').insert(payload)
    setSaving(false)
    if(result.error){setAppointments(prev=>prev.filter(a=>a.id!==id));setMessage(result.error.message.includes('appointments_no_overlap')?'Este profissional já possui atendimento neste intervalo.':result.error.message.includes('appointment_outside_working_hours')?'O horário está fora da jornada do profissional.':result.error.message.includes('appointment_schedule_blocked')?'Este horário está bloqueado na agenda.':`Erro: ${result.error.message}`);return}
    await refreshQueue(); setFilterDate(form.appointment_date);closeForm(); setMessage(online?(editing?'Agendamento atualizado.':'Agendamento criado.'):'Sem internet: agendamento criado localmente e aguardando sincronização.'); if(online)await loadAppointments()
  }

  async function deleteAppointment(item:Appointment){ if(!confirm(`Excluir definitivamente o agendamento de ${item.client_name} às ${item.start_time.slice(0,5)}?`))return
    setAppointments(prev=>prev.filter(a=>a.id!==item.id)); const {error}=await supabase.from('appointments').delete().eq('id',item.id).eq('business_id',business?.id||'')
    if(error){mergeOptimistic(item);setMessage(`Não foi possível excluir: ${error.message}`);return} await refreshQueue(); setMessage(online?'Agendamento excluído.':'Sem internet: exclusão colocada na fila de sincronização.')
  }

  if(loading)return <div className="center-screen">Carregando painel...</div>
  if(!business)return <div className="center-screen"><div className="empty-card"><p>Carregando empresa...</p></div></div>

  return <main className="admin-page">
    <AdminSidebar businessName={business.name} current="agenda"/>
    <section className="admin-content">
      <div className="admin-head">
        <div><span className="eyebrow">PAINEL • AGENDA 4.4</span><h1>Agenda do dia</h1><div className="live-row">
          <span className={`live-badge ${online?'online':'offline'}`}>{online?<Wifi size={14}/>:<WifiOff size={14}/>} {online?'Online':'Offline'}</span>
          <span className={`live-badge ${realtimeConnected?'online':'connecting'}`}><Radio size={14}/>{realtimeConnected?'Realtime ativo':'Realtime aguardando'}</span>
          {pendingOffline>0&&<span className="live-badge pending"><RefreshCw size={14}/>{pendingOffline} pendente{pendingOffline>1?'s':''}</span>}
          {lastLiveUpdate&&<small>Atualizado às {lastLiveUpdate.toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit',second:'2-digit'})}</small>}
        </div></div>
        <div className="admin-head-actions"><input className="input date-filter" type="date" value={filterDate} onChange={e=>setFilterDate(e.target.value)}/><button className="button button-primary" onClick={newAppointment}><Plus size={16}/>Novo agendamento</button></div>
      </div>
      {!online&&<div className="offline-banner"><WifiOff size={17}/><div><strong>Modo Offline First</strong><span>Você pode criar, editar e alterar status. A sincronização acontecerá quando a internet voltar.</span></div></div>}
      {message&&<div className="crm-feedback"><span>{message}</span><button onClick={()=>setMessage('')}><X size={15}/></button></div>}
      <div className="stats-grid"><article className="stat-card"><CalendarDays/><div><small>Agendamentos</small><strong>{visibleAppointments.length}</strong></div></article><article className="stat-card"><CheckCircle2/><div><small>Confirmados</small><strong>{confirmed.length}</strong></div></article><article className="stat-card"><Clock3/><div><small>Próximo horário</small><strong>{next?.start_time?.slice(0,5)||'--:--'}</strong></div></article><article className="stat-card"><span className="money">R$</span><div><small>Faturamento previsto</small><strong>R$ {revenue.toFixed(2).replace('.',',')}</strong></div></article></div>
      <div className="toolbar-card"><Filter size={16}/><label>Profissional<select className="input" value={professionalFilter} onChange={e=>setProfessionalFilter(e.target.value)}><option value="all">Todos</option>{professionals.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label><span className="toolbar-spacer"/><small>{visibleAppointments.length} atendimento(s)</small></div>
      <div className="appointments-list">{visibleAppointments.length===0?<div className="empty-card"><CalendarDays size={28}/><h3>Nenhum agendamento</h3><p>Não há atendimentos para esta data e filtro.</p><button className="button button-primary" onClick={newAppointment}><Plus size={16}/>Criar agendamento</button></div>:visibleAppointments.map(item=><article className="appointment-card" key={item.id}>
        <div className="appointment-time"><strong>{item.start_time.slice(0,5)}</strong><span>{item.end_time.slice(0,5)}</span></div><div className="appointment-main"><div className="appointment-title"><strong>{item.client_name}</strong><span className={`status-pill ${statusClass[item.status]}`}>{statusLabel[item.status]}</span></div><div className="appointment-meta"><span><UserRound size={14}/>{item.professionals?.name||professionals.find(p=>p.id===item.professional_id)?.name||'Profissional'}</span><span>✂ {item.services?.name||services.find(s=>s.id===item.service_id)?.name||'Serviço'}</span><span>R$ {Number(item.final_amount ?? item.services?.price ?? 0).toFixed(2).replace('.',',')}</span></div>{item.notes&&<p>{item.notes}</p>}</div>
        <div className="appointment-actions"><select className="input compact" value={item.status} onChange={e=>void updateStatus(item.id,e.target.value as Appointment['status'])}><option value="pending">Pendente</option><option value="confirmed">Confirmado</option><option value="completed">Concluído</option><option value="no_show">Não compareceu</option><option value="cancelled">Cancelado</option></select><button className="button button-secondary" onClick={()=>editAppointment(item)}>Editar</button><button className="icon-button" title="Excluir" onClick={()=>void deleteAppointment(item)}><MoreHorizontal size={18}/></button></div>
      </article>)}</div>
      {(creating||editing)&&<div className="modal-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)closeForm()}}><div className="modal-card"><div className="modal-head"><div><span className="eyebrow">AGENDA • OFFLINE FIRST</span><h2>{editing?'Editar agendamento':'Novo agendamento'}</h2></div><button className="icon-button" onClick={closeForm}><X size={18}/></button></div>
        <form className="crud-form" onSubmit={saveAppointment}><div className="crud-form-grid"><label>Cliente *<input className="input" value={form.client_name} onChange={e=>setForm({...form,client_name:e.target.value})}/></label><label>WhatsApp *<input className="input" value={form.client_phone} onChange={e=>setForm({...form,client_phone:e.target.value})}/></label></div><div className="crud-form-grid"><label>Serviço *<select className="input" value={form.service_id} onChange={e=>setForm({...form,service_id:e.target.value})}><option value="">Selecione</option>{services.filter(s=>s.active).map(s=><option key={s.id} value={s.id}>{s.name} — {s.duration_minutes} min</option>)}</select></label><label>Profissional *<select className="input" value={form.professional_id} onChange={e=>setForm({...form,professional_id:e.target.value})}><option value="">Selecione</option>{professionals.filter(p=>p.active).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label></div><div className="crud-form-grid"><label>Data *<input className="input" type="date" value={form.appointment_date} onChange={e=>setForm({...form,appointment_date:e.target.value})}/></label><label>Início *<input className="input" type="time" value={form.start_time} onChange={e=>setForm({...form,start_time:e.target.value})}/></label></div><div className="crud-form-grid"><label>Status<select className="input" value={form.status} onChange={e=>setForm({...form,status:e.target.value as Appointment['status']})}>{Object.entries(statusLabel).map(([v,l])=><option key={v} value={v}>{l}</option>)}</select></label><label>Valor final<input className="input" type="number" min="0" step="0.01" value={form.final_amount} placeholder="Automático pelo serviço" onChange={e=>setForm({...form,final_amount:e.target.value})}/></label></div><label>Observações<textarea className="input" value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></label><button className="button button-primary full" disabled={saving}><Save size={16}/>{saving?'Salvando...':editing?'Salvar alterações':'Criar agendamento'}</button>{!online&&<small className="form-hint">Este registro receberá um UUID local e ficará na fila até a conexão voltar.</small>}</form>
      </div></div>}
    </section>
  </main>
}
