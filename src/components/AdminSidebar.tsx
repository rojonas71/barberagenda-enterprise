import { useEffect, useState } from 'react'
import { BarChart3, CalendarDays, CircleDollarSign, FileClock, Headphones, LayoutDashboard, ListOrdered, LogOut, Menu, Scissors, Settings, ShieldCheck, UserRound, Users, X } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

type Section='dashboard'|'agenda'|'clients'|'services'|'professionals'|'availability'|'waitlist'|'finance'|'reports'|'team'|'support'|'settings'
type Role='owner'|'manager'|'receptionist'|'professional'

export function AdminSidebar({businessName,current}:{businessName:string;current:Section}){
 const navigate=useNavigate();const[role,setRole]=useState<Role>('professional');const[mobileOpen,setMobileOpen]=useState(false)
 useEffect(()=>{(async()=>{const{data:u}=await supabase.auth.getUser();if(!u.user)return;const{data:m}=await supabase.from('business_members').select('role').eq('user_id',u.user.id).limit(1).maybeSingle();if(m?.role)setRole(m.role as Role)})()},[])
 useEffect(()=>{setMobileOpen(false)},[current])
 useEffect(()=>{document.body.classList.toggle('nav-drawer-open',mobileOpen);return()=>document.body.classList.remove('nav-drawer-open')},[mobileOpen])
 useEffect(()=>{const close=(e:KeyboardEvent)=>{if(e.key==='Escape')setMobileOpen(false)};const resize=()=>{if(window.innerWidth>900)setMobileOpen(false)};window.addEventListener('keydown',close);window.addEventListener('resize',resize);return()=>{window.removeEventListener('keydown',close);window.removeEventListener('resize',resize)}},[])
 const items=[
  {key:'dashboard' as const,label:'Dashboard',path:'/painel/dashboard',icon:LayoutDashboard,roles:['owner','manager','receptionist','professional']},
  {key:'agenda' as const,label:'Agenda',path:'/painel',icon:CalendarDays,roles:['owner','manager','receptionist','professional']},
  {key:'clients' as const,label:'Clientes',path:'/painel/clientes',icon:Users,roles:['owner','manager','receptionist','professional']},
  {key:'services' as const,label:'Serviços',path:'/painel/servicos',icon:Scissors,roles:['owner','manager']},
  {key:'professionals' as const,label:'Profissionais',path:'/painel/profissionais',icon:UserRound,roles:['owner','manager']},
  {key:'availability' as const,label:'Disponibilidade',path:'/painel/disponibilidade',icon:FileClock,roles:['owner','manager','receptionist','professional']},
  {key:'waitlist' as const,label:'Lista de espera',path:'/painel/lista-espera',icon:ListOrdered,roles:['owner','manager','receptionist','professional']},
  {key:'finance' as const,label:'Financeiro',path:'/painel/financeiro',icon:CircleDollarSign,roles:['owner','manager']},
  {key:'reports' as const,label:'Relatórios',path:'/painel/relatorios',icon:BarChart3,roles:['owner','manager','professional']},
  {key:'team' as const,label:'Equipe',path:'/painel/equipe',icon:ShieldCheck,roles:['owner','manager']},
  {key:'support' as const,label:'Suporte',path:'/painel/suporte',icon:Headphones,roles:['owner','manager','receptionist','professional']},
  {key:'settings' as const,label:'Configurações',path:'/painel/configuracoes',icon:Settings,roles:['owner']},
 ]
 const visibleItems=items.filter(i=>i.roles.includes(role))
 function go(path:string){setMobileOpen(false);navigate(path)}
 async function logout(){setMobileOpen(false);await supabase.auth.signOut();navigate('/login')}
 return <>
   <header className="mobile-admin-header">
     <div className="mobile-admin-brand"><span className="brand-icon"><Scissors size={18}/></span><div><strong>BarberAgenda</strong><small>{businessName}</small></div></div>
     <button className="mobile-menu-button" aria-label="Abrir menu" aria-expanded={mobileOpen} onClick={()=>setMobileOpen(v=>!v)}>{mobileOpen?<X size={22}/>:<Menu size={22}/>}</button>
   </header>
   <button className={`mobile-nav-backdrop ${mobileOpen?'show':''}`} aria-label="Fechar menu" onClick={()=>setMobileOpen(false)}/>
   <aside className={`sidebar advanced-sidebar ${mobileOpen?'mobile-open':''}`}>
     <div className="sidebar-mobile-close"><button aria-label="Fechar menu" onClick={()=>setMobileOpen(false)}><X size={20}/></button></div>
     <div className="brand"><span className="brand-icon"><Scissors size={20}/></span> BarberAgenda</div>
     <div className="sidebar-business"><small>EMPRESA</small><strong>{businessName}</strong><span className="role-chip">{role}</span></div>
     <nav>{visibleItems.map(i=>{const Icon=i.icon;return <button key={i.key} className={`nav-item ${current===i.key?'active':''}`} onClick={()=>go(i.path)}><Icon/>{i.label}</button>})}</nav>
     <button className="nav-item logout" onClick={logout}><LogOut/>Sair</button>
   </aside>
 </>
}
