import { FormEvent, useEffect, useState } from 'react'
import { LockKeyhole, ShieldCheck } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../../lib/supabase'

export function DevLoginPage() {
  const navigate = useNavigate(); const [email,setEmail]=useState(''); const[password,setPassword]=useState(''); const[message,setMessage]=useState(''); const[loading,setLoading]=useState(false)
  useEffect(()=>{ void (async()=>{ const{data}=await supabase.auth.getUser(); if(!data.user)return; const{data:r}=await supabase.rpc('dev_current_role'); if(r)navigate('/dev-admin',{replace:true}) })() },[navigate])
  async function submit(e:FormEvent){e.preventDefault();setLoading(true);setMessage('');const{error}=await supabase.auth.signInWithPassword({email:email.trim().toLowerCase(),password});if(error){setMessage('E-mail ou senha inválidos.');setLoading(false);return}const{data:r,error:re}=await supabase.rpc('dev_current_role');if(re||!r){setMessage('Conta autenticada, mas sem permissão de Administrador Dev.');await supabase.auth.signOut();setLoading(false);return}navigate('/dev-admin',{replace:true})}
  return <main className="dev-login-page"><form className="dev-login-card" onSubmit={submit}><div className="dev-login-icon"><ShieldCheck/></div><span className="eyebrow">BARBERAGENDA PLATFORM</span><h1>Admin Dev</h1><p>Console administrativo global da plataforma.</p><label>E-mail<input className="input" type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="email"/></label><label>Senha<input className="input" type="password" value={password} onChange={e=>setPassword(e.target.value)} required autoComplete="current-password"/></label><button className="button button-primary full" disabled={loading}><LockKeyhole size={17}/>{loading?'Validando...':'Entrar no Dev Console'}</button>{message&&<div className="notice">{message}</div>}</form></main>
}
