import { useCallback, useEffect, useMemo, useState } from 'react'
import { CalendarCheck2, CircleDollarSign, Clock3, Radio, Scissors, TrendingUp, UserRound, Users } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { AdminSidebar } from '../components/AdminSidebar'
import { supabase } from '../lib/supabase'
import type { Appointment, Business } from '../types'

const localISO=(d=new Date())=>{const z=d.getTimezoneOffset();return new Date(d.getTime()-z*60000).toISOString().slice(0,10)}
const monthStart=()=>localISO(new Date(new Date().getFullYear(),new Date().getMonth(),1))
const monthEnd=()=>localISO(new Date(new Date().getFullYear(),new Date().getMonth()+1,0))
const money=(v:number)=>v.toLocaleString('pt-BR',{style:'currency',currency:'BRL'})

type Row=Appointment & {services?:{name:string;price:number}|null;professionals?:{name:string}|null;final_amount?:number|null;discount_amount?:number|null}
export function DashboardPage(){
 const navigate=useNavigate();const[business,setBusiness]=useState<Business|null>(null);const[rows,setRows]=useState<Row[]>([]);const[clientCount,setClientCount]=useState(0);const[expenses,setExpenses]=useState(0);const[waitlistCount,setWaitlistCount]=useState(0);const[loading,setLoading]=useState(true);const[live,setLive]=useState(false)
 useEffect(()=>{(async()=>{const{data:u}=await supabase.auth.getUser();if(!u.user)return navigate('/login');const{data:m}=await supabase.from('business_members').select('business_id').eq('user_id',u.user.id).maybeSingle();if(!m)return navigate('/onboarding');const{data:b}=await supabase.from('businesses').select('*').eq('id',m.business_id).single();setBusiness(b);setLoading(false)})()},[navigate])
 const load=useCallback(async()=>{if(!business)return;const [{data:a},{count:c},{data:t},{count:w}]=await Promise.all([
  supabase.from('appointments').select('*,services(name,price),professionals(name)').eq('business_id',business.id).gte('appointment_date',monthStart()).lte('appointment_date',monthEnd()).order('appointment_date').order('start_time'),
  supabase.from('clients').select('id',{count:'exact',head:true}).eq('business_id',business.id),
  supabase.from('financial_transactions').select('amount,type,status').eq('business_id',business.id).eq('type','expense').eq('status','paid').gte('transaction_date',monthStart()).lte('transaction_date',monthEnd()),
  supabase.from('waitlist_entries').select('id',{count:'exact',head:true}).eq('business_id',business.id).in('status',['waiting','contacted'])
 ]);setRows((a||[]) as Row[]);setClientCount(c||0);setExpenses((t||[]).reduce((s:any,x:any)=>s+Number(x.amount||0),0));setWaitlistCount(w||0)},[business])
 useEffect(()=>{load()},[load])
 useEffect(()=>{if(!business)return;const ch=supabase.channel(`dashboard:${business.id}`).on('postgres_changes',{event:'*',schema:'public',table:'appointments',filter:`business_id=eq.${business.id}`},load).on('postgres_changes',{event:'*',schema:'public',table:'financial_transactions',filter:`business_id=eq.${business.id}`},load).on('postgres_changes',{event:'*',schema:'public',table:'clients',filter:`business_id=eq.${business.id}`},load).on('postgres_changes',{event:'*',schema:'public',table:'waitlist_entries',filter:`business_id=eq.${business.id}`},load).subscribe(s=>setLive(s==='SUBSCRIBED'));return()=>{supabase.removeChannel(ch)}},[business,load])
 const completed=rows.filter(r=>r.status==='completed');const noShow=rows.filter(r=>r.status==='no_show');const revenue=completed.reduce((s,r)=>s+Number(r.final_amount??(Number(r.services?.price||0)-Number(r.discount_amount||0))),0);const net=revenue-expenses
 const serviceRank=useMemo(()=>{const m=new Map<string,{name:string,count:number,revenue:number}>();completed.forEach(r=>{const n=r.services?.name||'Serviço';const x=m.get(n)||{name:n,count:0,revenue:0};x.count++;x.revenue+=Number(r.final_amount ?? r.services?.price ?? 0);m.set(n,x)});return [...m.values()].sort((a,b)=>b.revenue-a.revenue).slice(0,5)},[completed])
 const proRank=useMemo(()=>{const m=new Map<string,{name:string,count:number,revenue:number}>();completed.forEach(r=>{const n=r.professionals?.name||'Profissional';const x=m.get(n)||{name:n,count:0,revenue:0};x.count++;x.revenue+=Number(r.final_amount ?? r.services?.price ?? 0);m.set(n,x)});return [...m.values()].sort((a,b)=>b.revenue-a.revenue).slice(0,5)},[completed])
 const today=localISO();const now=new Date().toTimeString().slice(0,5);const next=rows.filter(r=>r.appointment_date===today&&['pending','confirmed'].includes(r.status)&&r.start_time.slice(0,5)>=now).slice(0,6)
 if(loading)return <div className="center-screen">Carregando dashboard...</div>;if(!business)return null
 return <main className="admin-page"><AdminSidebar businessName={business.name} current="dashboard"/><section className="admin-content advanced-page">
  <div className="admin-head"><div><span className="eyebrow">VISÃO EXECUTIVA</span><h1>Dashboard</h1><div className="live-row"><span className={`live-badge ${live?'online':'connecting'}`}><Radio size={14}/>{live?'Dados ao vivo':'Conectando...'}</span></div></div><button className="button button-primary" onClick={()=>navigate('/painel')}><CalendarCheck2 size={16}/>Abrir agenda</button></div>
  <div className="advanced-kpis">
   <article><CircleDollarSign/><small>Faturamento do mês</small><strong>{money(revenue)}</strong><span>{completed.length} atendimentos concluídos</span></article>
   <article><TrendingUp/><small>Resultado estimado</small><strong>{money(net)}</strong><span>Despesas: {money(expenses)}</span></article>
   <article><CalendarCheck2/><small>Agendamentos</small><strong>{rows.length}</strong><span>{rows.length?Math.round(completed.length/rows.length*100):0}% concluídos</span></article>
   <article><Users/><small>Base de clientes</small><strong>{clientCount}</strong><span>{noShow.length} no-show no mês</span></article>
  </div>
  <div className="advanced-grid-2">
   <section className="panel-card"><div className="panel-title"><div><Clock3/><h2>Próximos de hoje</h2></div><button onClick={()=>navigate('/painel')}>Ver agenda</button></div>{next.length?next.map(r=><div className="compact-row" key={r.id}><strong>{r.start_time.slice(0,5)}</strong><div><b>{r.client_name}</b><small>{r.services?.name} • {r.professionals?.name}</small></div><span className={`status status-${r.status}`}>{r.status}</span></div>):<p className="empty-inline">Nenhum próximo atendimento hoje.</p>}</section>
   <section className="panel-card"><div className="panel-title"><div><Scissors/><h2>Serviços que mais faturam</h2></div></div>{serviceRank.length?serviceRank.map((x,i)=><div className="rank-row" key={x.name}><span>#{i+1}</span><div><b>{x.name}</b><small>{x.count} atendimentos</small></div><strong>{money(x.revenue)}</strong></div>):<p className="empty-inline">Ainda não há atendimentos concluídos no mês.</p>}</section>
  </div>
  <section className="panel-card action-card dashboard-waitlist-action"><div><Clock3/><div><h2>Lista de espera</h2><p>{waitlistCount} cliente(s) aguardando oportunidade de horário.</p></div></div><button className="button button-secondary" onClick={()=>navigate('/painel/lista-espera')}>Gerenciar fila</button></section>
  <section className="panel-card"><div className="panel-title"><div><UserRound/><h2>Performance por profissional</h2></div><button onClick={()=>navigate('/painel/relatorios')}>Relatório completo</button></div><div className="performance-grid">{proRank.map(x=><article key={x.name}><span className="crud-avatar">{x.name.slice(0,1).toUpperCase()}</span><div><b>{x.name}</b><small>{x.count} atendimentos</small></div><strong>{money(x.revenue)}</strong></article>)}{!proRank.length&&<p className="empty-inline">Sem dados de performance ainda.</p>}</div></section>
 </section></main>
}
