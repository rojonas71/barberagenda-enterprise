import { FormEvent, useCallback, useEffect, useState } from 'react'
import { CalendarDays, Check, LogOut, Pencil, Plus, Radio, Save, Scissors, Settings, Trash2, UserRound, Users, X } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { AdminSidebar } from '../components/AdminSidebar'
import { supabase } from '../lib/supabase'
import type { Business, Professional } from '../types'

type ProForm = { name: string; bio: string; photo_url: string; commission_percent: string; active: boolean }
const emptyForm: ProForm = { name: '', bio: '', photo_url: '', commission_percent: '0', active: true }

export function ProfessionalsPage() {
  const navigate = useNavigate()
  const [business, setBusiness] = useState<Business | null>(null)
  const [professionals, setProfessionals] = useState<Professional[]>([])
  const [editing, setEditing] = useState<Professional | null>(null)
  const [form, setForm] = useState<ProForm>(emptyForm)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')
  const [realtimeConnected, setRealtimeConnected] = useState(false)

  useEffect(() => { (async () => {
    const { data } = await supabase.auth.getUser(); if (!data.user) return navigate('/login')
    const { data: member } = await supabase.from('business_members').select('business_id').eq('user_id', data.user.id).maybeSingle(); if (!member) return navigate('/onboarding')
    const { data: biz } = await supabase.from('businesses').select('*').eq('id', member.business_id).single(); setBusiness(biz); setLoading(false)
  })() }, [navigate])

  const load = useCallback(async () => {
    if (!business) return
    const { data, error } = await supabase.from('professionals').select('*').eq('business_id', business.id).order('active', { ascending:false }).order('name')
    if (error) setMessage(error.message); else setProfessionals((data || []) as Professional[])
  }, [business])
  useEffect(() => { load() }, [load])
  useEffect(() => {
    if (!business) return
    const channel = supabase.channel(`professionals-crud:${business.id}`).on('postgres_changes',{event:'*',schema:'public',table:'professionals',filter:`business_id=eq.${business.id}`},load).subscribe(status=>setRealtimeConnected(status==='SUBSCRIBED'))
    return () => { setRealtimeConnected(false); supabase.removeChannel(channel) }
  }, [business, load])

  function reset(){setEditing(null);setForm(emptyForm);setMessage('')}
  function startEdit(pro:Professional){setEditing(pro);setForm({name:pro.name,bio:pro.bio||'',photo_url:pro.photo_url||'',commission_percent:String(pro.commission_percent||0),active:pro.active});setMessage('')}
  async function save(e:FormEvent){e.preventDefault();if(!business)return;if(!form.name.trim())return setMessage('Informe o nome do profissional.');setSaving(true);const payload={business_id:business.id,name:form.name.trim(),bio:form.bio.trim()||null,photo_url:form.photo_url.trim()||null,commission_percent:Number(form.commission_percent||0),active:form.active};const result=editing?await supabase.from('professionals').update(payload).eq('id',editing.id).eq('business_id',business.id):await supabase.from('professionals').insert(payload);setSaving(false);if(result.error)return setMessage(`Erro: ${result.error.message}`);reset();await load();setMessage(editing?'Profissional atualizado.':'Profissional criado.')}
  async function toggle(pro:Professional){const{error}=await supabase.from('professionals').update({active:!pro.active}).eq('id',pro.id);if(error)setMessage(error.message)}
  async function remove(pro:Professional){if(!confirm(`Excluir o profissional “${pro.name}”?`))return;const{error}=await supabase.from('professionals').delete().eq('id',pro.id);if(error){setMessage(error.code==='23503'?'Este profissional possui agendamentos. Desative-o para preservar o histórico.':`Não foi possível excluir: ${error.message}`);return}if(editing?.id===pro.id)reset();setMessage('Profissional excluído.')}
  async function logout(){await supabase.auth.signOut();navigate('/login')}
  if(loading)return <div className="center-screen">Carregando profissionais...</div>; if(!business)return null

  return <main className="admin-page"><AdminSidebar businessName={business.name} current="professionals"/>
  <section className="admin-content crud-page"><div className="admin-head"><div><span className="eyebrow">CRUD</span><h1>Profissionais</h1><div className="live-row"><span className={`live-badge ${realtimeConnected?'online':'connecting'}`}><Radio size={14}/>{realtimeConnected?'Tempo real ativo':'Conectando...'}</span></div></div><button className="button button-primary" onClick={reset}><Plus size={16}/>Novo profissional</button></div>{message&&<div className="crm-feedback"><span>{message}</span><button onClick={()=>setMessage('')}><X size={15}/></button></div>}
  <div className="crud-layout"><div className="table-card"><div className="table-head"><h2>Equipe</h2><span>{professionals.length}</span></div><div className="table-wrap"><table><thead><tr><th>Profissional</th><th>Bio</th><th>Comissão</th><th>Status</th><th>Ações</th></tr></thead><tbody>{professionals.map(pro=><tr key={pro.id}><td><div className="crud-person"><span className="crud-avatar">{pro.photo_url?<img src={pro.photo_url} alt=""/>:pro.name.slice(0,1).toUpperCase()}</span><strong>{pro.name}</strong></div></td><td>{pro.bio||'—'}</td><td><strong>{Number(pro.commission_percent||0).toFixed(1).replace('.',',')}%</strong></td><td><button className={`crud-status ${pro.active?'active':'inactive'}`} onClick={()=>toggle(pro)}>{pro.active?<Check size={13}/>:<X size={13}/>} {pro.active?'Ativo':'Inativo'}</button></td><td className="actions"><button onClick={()=>startEdit(pro)}><Pencil size={14}/>Editar</button><button className="danger-action" onClick={()=>remove(pro)}><Trash2 size={14}/>Excluir</button></td></tr>)}{!professionals.length&&<tr><td colSpan={5} className="empty-row">Nenhum profissional cadastrado.</td></tr>}</tbody></table></div></div>
  <form className="crud-form-card" onSubmit={save}><span className="eyebrow">{editing?'EDITAR':'CRIAR'}</span><h2>{editing?editing.name:'Novo profissional'}</h2><label>Nome<input className="input" value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="Nome do profissional"/></label><label>Bio<textarea className="input" value={form.bio} onChange={e=>setForm({...form,bio:e.target.value})} placeholder="Especialidades, experiência..."/></label><label>URL da foto<input className="input" type="url" value={form.photo_url} onChange={e=>setForm({...form,photo_url:e.target.value})} placeholder="https://..."/></label><label>Comissão padrão (%)<input className="input" type="number" min="0" max="100" step="0.1" value={form.commission_percent} onChange={e=>setForm({...form,commission_percent:e.target.value})}/><small className="field-hint">Usada nos indicadores financeiros de comissão.</small></label><label className="crud-check"><input type="checkbox" checked={form.active} onChange={e=>setForm({...form,active:e.target.checked})}/>Disponível para agendamento</label><button className="button button-primary full" disabled={saving}><Save size={16}/>{saving?'Salvando...':editing?'Salvar alterações':'Criar profissional'}</button>{editing&&<button type="button" className="button button-ghost full" onClick={reset}>Cancelar edição</button>}</form></div></section></main>
}
