import { useEffect, useState } from 'react'
import { Activity, BarChart3, Building2, CreditCard, Headphones, LogOut, Menu, Settings, ShieldCheck, Users, X } from 'lucide-react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export type DevRole = 'super_admin' | 'support' | 'billing' | 'ops' | 'read_only'
export type DevOutletContext = { role: DevRole; email: string }

export function DevAdminLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const [loading, setLoading] = useState(true)
  const [role, setRole] = useState<DevRole | null>(null)
  const [email, setEmail] = useState('')
  const [mobileOpen, setMobileOpen] = useState(false)

  useEffect(() => {
    void (async () => {
      const { data } = await supabase.auth.getUser()
      if (!data.user) { navigate('/dev-admin/login', { replace: true }); return }
      setEmail(data.user.email || '')
      const { data: devRole } = await supabase.rpc('dev_current_role')
      setRole((devRole || null) as DevRole | null)
      setLoading(false)
    })()
  }, [navigate])

  useEffect(()=>{setMobileOpen(false)},[location.pathname])
  useEffect(()=>{document.body.classList.toggle('nav-drawer-open',mobileOpen);return()=>document.body.classList.remove('nav-drawer-open')},[mobileOpen])
  useEffect(()=>{const close=(e:KeyboardEvent)=>{if(e.key==='Escape')setMobileOpen(false)};const resize=()=>{if(window.innerWidth>900)setMobileOpen(false)};window.addEventListener('keydown',close);window.addEventListener('resize',resize);return()=>{window.removeEventListener('keydown',close);window.removeEventListener('resize',resize)}},[])

  async function logout() { setMobileOpen(false); await supabase.auth.signOut(); navigate('/dev-admin/login') }

  if (loading) return <main className="center-screen">Validando acesso de desenvolvedor...</main>
  if (!role) return <main className="center-screen"><div className="dev-access-card"><ShieldCheck size={34}/><h1>Acesso restrito</h1><p>Esta conta não está cadastrada como Administrador Dev.</p><button className="button button-primary" onClick={() => navigate('/painel/dashboard')}>Ir para o painel</button><button className="button" onClick={logout}>Sair</button></div></main>

  const links = [
    ['/dev-admin', 'Visão global', BarChart3], ['/dev-admin/empresas', 'Empresas', Building2], ['/dev-admin/usuarios', 'Usuários', Users],
    ['/dev-admin/planos', 'Planos', CreditCard], ['/dev-admin/suporte', 'Suporte', Headphones], ['/dev-admin/saude', 'Saúde', Activity],
    ['/dev-admin/configuracoes', 'Configurações', Settings],
  ] as const

  return <main className="dev-shell">
    <header className="dev-mobile-header">
      <div className="dev-mobile-brand"><ShieldCheck size={22}/><div><strong>BarberAgenda</strong><small>DEV CONSOLE</small></div></div>
      <button className="mobile-menu-button" aria-label="Abrir menu Dev" aria-expanded={mobileOpen} onClick={()=>setMobileOpen(v=>!v)}>{mobileOpen?<X size={22}/>:<Menu size={22}/>}</button>
    </header>
    <button className={`mobile-nav-backdrop dev-backdrop ${mobileOpen?'show':''}`} aria-label="Fechar menu Dev" onClick={()=>setMobileOpen(false)}/>
    <aside className={`dev-sidebar ${mobileOpen?'mobile-open':''}`}>
      <div className="sidebar-mobile-close"><button aria-label="Fechar menu" onClick={()=>setMobileOpen(false)}><X size={20}/></button></div>
      <div className="dev-brand"><ShieldCheck/> <div><strong>BarberAgenda</strong><small>DEV CONSOLE</small></div></div>
      <div className="dev-account"><small>ADMINISTRADOR</small><b>{email}</b><span>{role.replace('_', ' ')}</span></div>
      <nav>{links.map(([path, label, Icon]) => <NavLink key={path} to={path} end={path === '/dev-admin'} className={({isActive}) => `dev-nav ${isActive ? 'active' : ''}`}><Icon size={18}/>{label}</NavLink>)}</nav>
      <button className="dev-nav dev-logout" onClick={logout}><LogOut size={18}/>Sair</button>
    </aside>
    <section className="dev-content"><Outlet context={{ role, email } satisfies DevOutletContext}/></section>
  </main>
}
