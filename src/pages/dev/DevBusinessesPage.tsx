import { useEffect, useMemo, useState } from 'react'
import { Building2, Copy, Download, ExternalLink, MessageCircle, RefreshCcw, Search, ShieldBan, UsersRound, WalletCards, X } from 'lucide-react'
import { useOutletContext } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import type { DevOutletContext } from '../../components/DevAdminLayout'
import { copyText, dateOnly, dateTime, downloadCsv, money } from './devUtils'

type PlatformStatus = 'active' | 'suspended' | 'archived'
type Row = {
  id:string; name:string; slug:string; platform_status:PlatformStatus; created_at:string; owner_email:string|null;
  member_count:number; client_count:number; appointment_count:number; completed_revenue:number; plan_id:string|null;
  plan_name:string|null; subscription_status:string|null; current_period_ends_at:string|null; last_appointment_at:string|null;
  phone:string|null; plan_price_monthly:number|null; payment_url:string|null
}
type Plan={id:string;name:string;code:string;active:boolean}

type SortKey='recent'|'name'|'clients'|'appointments'|'revenue'

export function DevBusinessesPage(){
  const {role}=useOutletContext<DevOutletContext>()
  const [rows,setRows]=useState<Row[]>([])
  const [plans,setPlans]=useState<Plan[]>([])
  const [q,setQ]=useState('')
  const [statusFilter,setStatusFilter]=useState<'all'|PlatformStatus>('all')
  const [planFilter,setPlanFilter]=useState('all')
  const [sort,setSort]=useState<SortKey>('recent')
  const [selected,setSelected]=useState<Row|null>(null)
  const [msg,setMsg]=useState('')
  const [loading,setLoading]=useState(false)
  const canStatus=['super_admin','ops'].includes(role)
  const canBilling=['super_admin','billing'].includes(role)

  function whatsappNumber(value:string|null){
    const digits=(value||'').replace(/\D/g,'')
    if(!digits)return ''
    if(digits.startsWith('55')&&digits.length>=12)return digits
    if(digits.length===10||digits.length===11)return `55${digits}`
    return digits
  }

  function billingWhatsAppUrl(b:Row){
    const number=whatsappNumber(b.phone)
    if(!number)return ''

    const price=money(Number(b.plan_price_monthly||80))
    const payment=b.payment_url||'https://mpago.la/2tn4qBx'
    const dueDate=b.current_period_ends_at?new Date(b.current_period_ends_at):null
    const now=new Date()
    const today=new Date(now.getFullYear(),now.getMonth(),now.getDate())
    const due=dueDate?dateOnly(b.current_period_ends_at):null
    const dueDay=dueDate?new Date(dueDate.getFullYear(),dueDate.getMonth(),dueDate.getDate()):null
    const daysUntilDue=dueDay?Math.ceil((dueDay.getTime()-today.getTime())/86400000):null

    const overdue=b.subscription_status==='past_due'||b.subscription_status==='inactive'||(daysUntilDue!==null&&daysUntilDue<0)
    const dueSoon=!overdue&&daysUntilDue!==null&&daysUntilDue>=0&&daysUntilDue<=5

    const lines=overdue?[
      `\u{1F534} *Mensalidade pendente — BarberAgenda*`,
      ``,
      `Olá! \u{1F44B} Tudo bem?`,
      ``,
      `Identificamos que sua mensalidade do BarberAgenda está pendente.`,
      ``,
      `\u{1F4E6} *Plano:* ${b.plan_name||'Plano Profissional'}`,
      `\u{1F4B0} *Valor:* ${price}/mês`,
      ...(due?[`\u{1F4C5} *Vencimento:* ${due}`]:[]),
      ``,
      `\u{26A0}\u{FE0F} Regularize o pagamento para manter seu acesso ao BarberAgenda normalmente.`,
      ``,
      `\u{1F4B3} *Pagamento:*`,
      `\u{1F517} ${payment}`,
      ``,
      `\u{1F4F8} Depois do pagamento, envie o comprovante por aqui.`,
      ``,
      `\u{2705} Assim que confirmarmos, sua mensalidade ficará regularizada.`,
      ``,
      `\u{2702}\u{FE0F} Obrigado por utilizar o BarberAgenda! \u{1F488}\u{1F4C5}\u{1F680}`
    ]:dueSoon?[
      `\u{1F7E1} *Lembrete de mensalidade — BarberAgenda*`,
      ``,
      `Olá! \u{1F44B} Tudo bem?`,
      ``,
      `Sua mensalidade do BarberAgenda vence em breve.`,
      ``,
      `\u{1F4E6} *Plano:* ${b.plan_name||'Plano Profissional'}`,
      `\u{1F4B0} *Valor:* ${price}/mês`,
      ...(due?[`\u{1F4C5} *Vencimento:* ${due}`]:[]),
      ``,
      `\u{1F4B3} Você já pode realizar o pagamento pelo link abaixo:`,
      `\u{1F517} ${payment}`,
      ``,
      `\u{1F4F2} Após o pagamento, envie o comprovante por aqui.`,
      ``,
      `\u{1F488} Obrigado por fazer parte do BarberAgenda! \u{2702}\u{FE0F}\u{1F680}`
    ]:[
      `\u{1F44B} Olá! Tudo bem?`,
      ``,
      `\u{1F488} Este é um lembrete da sua mensalidade do *BarberAgenda*.`,
      ``,
      `\u{1F4E6} *Plano:* ${b.plan_name||'Plano Profissional'}`,
      `\u{1F4B0} *Valor:* ${price}/mês`,
      ...(due?[`\u{1F4C5} *Vencimento:* ${due}`]:[]),
      ``,
      `\u{1F6A8} Para manter seu acesso ao sistema ativo e continuar utilizando todos os recursos, realize o pagamento pelo link abaixo:`,
      ``,
      `\u{1F517} ${payment}`,
      ``,
      `\u{1F4F2} Após o pagamento, envie o comprovante por aqui.`,
      ``,
      `\u{2705} Assim que confirmarmos, sua mensalidade fica regularizada.`,
      ``,
      `\u{2702}\u{FE0F} Obrigado por utilizar o BarberAgenda! \u{1F680}`
    ]

    return `https://wa.me/${number}?text=${encodeURIComponent(lines.join('\n'))}`
  }

  function sendBillingWhatsApp(b:Row){
    const url=billingWhatsAppUrl(b)
    if(!url){
      setMsg(`A empresa ${b.name} não possui telefone/WhatsApp cadastrado.`)
      return
    }
    window.open(url,'_blank','noopener,noreferrer')
  }

  async function load(){
    setLoading(true); setMsg('')
    const [{data:r,error},{data:p,error:pe}]=await Promise.all([
      supabase.rpc('dev_list_businesses',{p_search:q.trim()||null,p_limit:500,p_offset:0}),
      supabase.from('subscription_plans').select('id,name,code,active').order('sort_order').order('name')
    ])
    if(error||pe)setMsg(error?.message||pe?.message||'Não foi possível carregar empresas.')
    setRows((r||[]) as Row[]); setPlans((p||[]) as Plan[]); setLoading(false)
  }
  useEffect(()=>{void load()},[])

  const filtered=useMemo(()=>{
    const data=rows.filter(b=>(statusFilter==='all'||b.platform_status===statusFilter)&&(planFilter==='all'||(planFilter==='none'?!b.plan_id:b.plan_id===planFilter)))
    return [...data].sort((a,b)=>sort==='name'?a.name.localeCompare(b.name):sort==='clients'?b.client_count-a.client_count:sort==='appointments'?b.appointment_count-a.appointment_count:sort==='revenue'?Number(b.completed_revenue)-Number(a.completed_revenue):new Date(b.created_at).getTime()-new Date(a.created_at).getTime())
  },[rows,statusFilter,planFilter,sort])

  const stats=useMemo(()=>({
    total:rows.length,
    active:rows.filter(x=>x.platform_status==='active').length,
    suspended:rows.filter(x=>x.platform_status==='suspended').length,
    clients:rows.reduce((s,x)=>s+Number(x.client_count||0),0),
    revenue:rows.reduce((s,x)=>s+Number(x.completed_revenue||0),0)
  }),[rows])

  async function changeStatus(b:Row,next:PlatformStatus){
    if(!canStatus)return
    let reason:string|null=null
    if(next==='suspended'){reason=window.prompt(`Motivo da suspensão de ${b.name}:`)?.trim()||null;if(!reason)return}
    if(!window.confirm(`Alterar o status de “${b.name}” para ${next}?`))return
    const{error}=await supabase.rpc('dev_set_business_status',{p_business_id:b.id,p_status:next,p_reason:reason})
    setMsg(error?error.message:'Status da empresa atualizado.'); if(!error)setSelected(null); void load()
  }
  async function setPlan(b:Row,planId:string){
    if(!canBilling)return
    const{error}=await supabase.rpc('dev_upsert_subscription',{p_business_id:b.id,p_plan_id:planId||null,p_status:planId?'active':'canceled',p_period_end:null,p_notes:null})
    setMsg(error?error.message:'Assinatura atualizada.'); void load()
  }
  function exportRows(){downloadCsv(`empresas-${new Date().toISOString().slice(0,10)}.csv`,filtered.map(b=>({empresa:b.name,slug:b.slug,proprietario:b.owner_email,status:b.platform_status,plano:b.plan_name,assinatura:b.subscription_status,clientes:b.client_count,equipe:b.member_count,agendamentos:b.appointment_count,receita_concluida:b.completed_revenue,ultimo_agendamento:b.last_appointment_at,criada_em:b.created_at})))}

  return <>
    <header className="dev-page-head"><div><span className="eyebrow">TENANTS & OPERAÇÃO</span><h1>Empresas</h1><p>Gestão global de estabelecimentos, assinatura, atividade, receita e status operacional.</p></div><div className="dev-head-actions"><button className="button" onClick={exportRows}><Download size={16}/>Exportar</button><button className="button" onClick={()=>void load()} disabled={loading}><RefreshCcw size={16}/>{loading?'Atualizando...':'Atualizar'}</button></div></header>
    {msg&&<div className="notice">{msg}</div>}

    <div className="dev-kpis compact dev-kpis-five">
      <article><Building2/><small>Empresas</small><strong>{stats.total}</strong><span>tenants cadastrados</span></article>
      <article><Building2/><small>Ativas</small><strong>{stats.active}</strong><span>operando normalmente</span></article>
      <article className={stats.suspended?'danger':''}><ShieldBan/><small>Suspensas</small><strong>{stats.suspended}</strong><span>acesso operacional limitado</span></article>
      <article><UsersRound/><small>Clientes finais</small><strong>{stats.clients}</strong><span>somados nas empresas</span></article>
      <article><WalletCards/><small>Receita concluída</small><strong>{money(stats.revenue)}</strong><span>histórico agregado</span></article>
    </div>

    <div className="dev-toolbar dev-toolbar-advanced">
      <div className="search-box"><Search size={17}/><input placeholder="Buscar empresa, slug ou proprietário" value={q} onChange={e=>setQ(e.target.value)} onKeyDown={e=>{if(e.key==='Enter')void load()}}/></div>
      <select value={statusFilter} onChange={e=>setStatusFilter(e.target.value as typeof statusFilter)}><option value="all">Todos os status</option><option value="active">Ativas</option><option value="suspended">Suspensas</option><option value="archived">Arquivadas</option></select>
      <select value={planFilter} onChange={e=>setPlanFilter(e.target.value)}><option value="all">Todos os planos</option><option value="none">Sem plano</option>{plans.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select>
      <select value={sort} onChange={e=>setSort(e.target.value as SortKey)}><option value="recent">Mais recentes</option><option value="name">Nome A-Z</option><option value="clients">Mais clientes</option><option value="appointments">Mais agendamentos</option><option value="revenue">Maior receita</option></select>
      <button className="button button-primary" onClick={()=>void load()}>Buscar</button>
    </div>

    <section className="dev-panel"><div className="dev-panel-head"><div><h2>Base de empresas</h2><p>{filtered.length} resultado(s) no filtro atual.</p></div></div><div className="dev-table-wrap"><table className="dev-table wide"><thead><tr><th>Empresa</th><th>Proprietário</th><th>Status</th><th>Plano</th><th>Clientes</th><th>Equipe</th><th>Agenda</th><th>Receita</th><th>Última atividade</th><th>Ações</th></tr></thead><tbody>{filtered.map(b=><tr key={b.id} onDoubleClick={()=>setSelected(b)}><td><b>{b.name}</b><small>/{b.slug}</small></td><td>{b.owner_email||'—'}</td><td><span className={`dev-status ${b.platform_status}`}>{b.platform_status}</span></td><td>{canBilling?<select value={b.plan_id||''} onChange={e=>void setPlan(b,e.target.value)}><option value="">Sem plano</option>{plans.filter(p=>p.active).map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select>:b.plan_name||'Sem plano'}<small>{b.subscription_status||'sem assinatura'}</small></td><td>{b.client_count}</td><td>{b.member_count}</td><td>{b.appointment_count}</td><td>{money(b.completed_revenue)}</td><td>{dateOnly(b.last_appointment_at)}</td><td><div className="dev-actions"><button onClick={()=>setSelected(b)}>Detalhes</button><button title="Abrir agenda pública" onClick={()=>window.open(`/b/${b.slug}`,'_blank')}><ExternalLink size={15}/></button>{canBilling&&<button title={b.phone?'Enviar aviso de mensalidade pelo WhatsApp':'WhatsApp não cadastrado'} disabled={!b.phone} onClick={()=>sendBillingWhatsApp(b)}><MessageCircle size={15}/>Cobrar</button>}{canStatus&&b.platform_status!=='suspended'&&<button className="danger" onClick={()=>void changeStatus(b,'suspended')}><ShieldBan size={15}/>Suspender</button>}{canStatus&&b.platform_status!=='active'&&<button onClick={()=>void changeStatus(b,'active')}>Ativar</button>}</div></td></tr>)}{!filtered.length&&<tr><td colSpan={10}>Nenhuma empresa encontrada com os filtros atuais.</td></tr>}</tbody></table></div></section>

    {selected&&<div className="dev-detail-backdrop" onClick={()=>setSelected(null)}><aside className="dev-detail-drawer" onClick={e=>e.stopPropagation()}><div className="dev-detail-head"><div><span className="eyebrow">EMPRESA</span><h2>{selected.name}</h2><p>/{selected.slug}</p></div><button onClick={()=>setSelected(null)}><X/></button></div><div className="dev-detail-grid"><div><small>Status</small><strong><span className={`dev-status ${selected.platform_status}`}>{selected.platform_status}</span></strong></div><div><small>Plano</small><strong>{selected.plan_name||'Sem plano'}</strong></div><div><small>Clientes</small><strong>{selected.client_count}</strong></div><div><small>Equipe</small><strong>{selected.member_count}</strong></div><div><small>Agendamentos</small><strong>{selected.appointment_count}</strong></div><div><small>Receita</small><strong>{money(selected.completed_revenue)}</strong></div></div><section className="dev-detail-section"><h3>Identificação</h3><dl><div><dt>ID</dt><dd><code>{selected.id}</code></dd></div><div><dt>Proprietário</dt><dd>{selected.owner_email||'—'}</dd></div><div><dt>Criada em</dt><dd>{dateTime(selected.created_at)}</dd></div><div><dt>Último agendamento</dt><dd>{dateTime(selected.last_appointment_at)}</dd></div><div><dt>Fim do período</dt><dd>{dateTime(selected.current_period_ends_at)}</dd></div></dl></section><div className="dev-detail-actions"><button className="button" onClick={()=>void copyText(`${window.location.origin}/b/${selected.slug}`)}><Copy size={15}/>Copiar link</button><button className="button" onClick={()=>window.open(`/b/${selected.slug}`,'_blank')}><ExternalLink size={15}/>Abrir agenda</button>{canBilling&&<button className="button" disabled={!selected.phone} onClick={()=>sendBillingWhatsApp(selected)}><MessageCircle size={15}/>Avisar mensalidade</button>}{canStatus&&selected.platform_status==='active'&&<button className="button danger-button" onClick={()=>void changeStatus(selected,'suspended')}><ShieldBan size={15}/>Suspender</button>}{canStatus&&selected.platform_status!=='active'&&<button className="button button-primary" onClick={()=>void changeStatus(selected,'active')}>Reativar empresa</button>}</div></aside></div>}
  </>
}
