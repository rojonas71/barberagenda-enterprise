import { FormEvent, useEffect, useMemo, useState } from 'react'
import { Building2, CheckCircle2, Clock3, Scissors, UserRound } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'

function slugify(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60)
}

export function OnboardingPage() {
  const navigate = useNavigate()
  const [name, setName] = useState('')
  const [slug, setSlug] = useState('')
  const [slugEdited, setSlugEdited] = useState(false)
  const [phone, setPhone] = useState('')
  const [address, setAddress] = useState('')
  const [openingTime, setOpeningTime] = useState('08:00')
  const [closingTime, setClosingTime] = useState('19:00')
  const [slotInterval, setSlotInterval] = useState('30')
  const [serviceName, setServiceName] = useState('')
  const [servicePrice, setServicePrice] = useState('')
  const [serviceDuration, setServiceDuration] = useState('30')
  const [professionalName, setProfessionalName] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState('')

  useEffect(() => {
    async function checkAccount() {
      const { data } = await supabase.auth.getUser()
      if (!data.user) {
        navigate('/login', { replace: true })
        return
      }

      const { data: member } = await supabase
        .from('business_members')
        .select('business_id')
        .eq('user_id', data.user.id)
        .limit(1)
        .maybeSingle()

      if (member) {
        navigate('/painel/dashboard', { replace: true })
        return
      }

      setLoading(false)
    }

    checkAccount()
  }, [navigate])

  const publicUrl = useMemo(() => {
    const finalSlug = slugify(slug || name) || 'sua-empresa'
    return `${window.location.origin}/b/${finalSlug}`
  }, [name, slug])

  function handleName(value: string) {
    setName(value)
    if (!slugEdited) setSlug(slugify(value))
  }

  async function submit(event: FormEvent) {
    event.preventDefault()
    setMessage('')

    const finalSlug = slugify(slug || name)
    const price = Number(String(servicePrice).replace(',', '.'))
    const duration = Number(serviceDuration)
    const interval = Number(slotInterval)

    if (name.trim().length < 2) return setMessage('Informe o nome real da empresa.')
    if (finalSlug.length < 3) return setMessage('O endereço público precisa ter pelo menos 3 caracteres.')
    if (!serviceName.trim()) return setMessage('Cadastre pelo menos um serviço real.')
    if (!professionalName.trim()) return setMessage('Cadastre pelo menos um profissional real.')
    if (!Number.isFinite(price) || price < 0) return setMessage('Informe um preço válido para o serviço.')
    if (!Number.isFinite(duration) || duration <= 0) return setMessage('Informe uma duração válida para o serviço.')
    if (openingTime >= closingTime) return setMessage('O horário de abertura deve ser anterior ao de fechamento.')

    setSaving(true)

    try {
      const { data, error } = await supabase.rpc('create_business_for_current_user', {
        p_name: name.trim(),
        p_slug: finalSlug,
        p_phone: phone.trim() || null,
        p_address: address.trim() || null,
        p_opening_time: openingTime,
        p_closing_time: closingTime,
        p_slot_interval: interval,
        p_service_name: serviceName.trim(),
        p_service_price: price,
        p_service_duration: duration,
        p_professional_name: professionalName.trim()
      })

      if (error) {
        const normalized = error.message.toLowerCase()
        if (normalized.includes('duplicate') || normalized.includes('business_slug_taken')) {
          setMessage('Esse endereço público já está em uso. Escolha outro slug.')
        } else if (normalized.includes('user_already_has_business')) {
          navigate('/painel/dashboard', { replace: true })
        } else if (error.code === 'PGRST202' || normalized.includes('schema cache') || normalized.includes('could not find the function')) {
          setMessage('O banco ainda não possui a função de criação da empresa. Execute supabase/fix-onboarding-rpc.sql no Supabase → SQL Editor e tente novamente.')
        } else if (normalized.includes('authentication_required')) {
          setMessage('Sua sessão expirou. Entre novamente para continuar.')
        } else {
          setMessage(`Não foi possível criar a empresa: ${error.message}`)
        }
        return
      }

      if (!data) {
        setMessage('A empresa não foi criada. Tente novamente.')
        return
      }

      navigate('/painel/dashboard', { replace: true })
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <div className="center-screen"><div className="empty-card"><p>Carregando configuração...</p></div></div>

  return (
    <main className="onboarding-page">
      <div className="onboarding-shell">
        <div className="onboarding-brand brand"><span className="brand-icon"><Scissors size={20}/></span> BarberAgenda</div>
        <div className="onboarding-intro">
          <span className="eyebrow">CONFIGURAÇÃO INICIAL</span>
          <h1>Cadastre sua empresa real</h1>
          <p>Nenhum dado de demonstração será criado. Use as informações verdadeiras da sua barbearia ou salão.</p>
        </div>

        <form className="onboarding-card" onSubmit={submit}>
          <section className="onboarding-section">
            <div className="onboarding-section-title"><Building2 size={20}/><div><strong>Empresa</strong><small>Informações que aparecem na agenda pública.</small></div></div>
            <div className="onboarding-grid">
              <label>Nome da empresa<input className="input" value={name} onChange={e => handleName(e.target.value)} placeholder="Ex.: Studio Central" required /></label>
              <label>Telefone<input className="input" value={phone} onChange={e => setPhone(e.target.value)} placeholder="(00) 00000-0000" /></label>
              <label className="full-span">Endereço<input className="input" value={address} onChange={e => setAddress(e.target.value)} placeholder="Rua, número, bairro, cidade" /></label>
              <label className="full-span">Endereço público
                <div className="slug-field"><span>/b/</span><input className="input" value={slug} onChange={e => { setSlugEdited(true); setSlug(slugify(e.target.value)) }} placeholder="studio-central" required /></div>
                <small className="field-hint">Seu link: {publicUrl}</small>
              </label>
            </div>
          </section>

          <section className="onboarding-section">
            <div className="onboarding-section-title"><Clock3 size={20}/><div><strong>Horários</strong><small>Configuração inicial da agenda.</small></div></div>
            <div className="onboarding-grid three-cols">
              <label>Abertura<input className="input" type="time" value={openingTime} onChange={e => setOpeningTime(e.target.value)} required /></label>
              <label>Fechamento<input className="input" type="time" value={closingTime} onChange={e => setClosingTime(e.target.value)} required /></label>
              <label>Intervalo<select className="input" value={slotInterval} onChange={e => setSlotInterval(e.target.value)}><option value="15">15 min</option><option value="20">20 min</option><option value="30">30 min</option><option value="45">45 min</option><option value="60">60 min</option></select></label>
            </div>
          </section>

          <section className="onboarding-section">
            <div className="onboarding-section-title"><Scissors size={20}/><div><strong>Primeiro serviço</strong><small>Você poderá adicionar outros serviços depois.</small></div></div>
            <div className="onboarding-grid three-cols">
              <label>Serviço<input className="input" value={serviceName} onChange={e => setServiceName(e.target.value)} placeholder="Ex.: Corte" required /></label>
              <label>Preço (R$)<input className="input" inputMode="decimal" value={servicePrice} onChange={e => setServicePrice(e.target.value)} placeholder="45,00" required /></label>
              <label>Duração<select className="input" value={serviceDuration} onChange={e => setServiceDuration(e.target.value)}><option value="15">15 min</option><option value="30">30 min</option><option value="45">45 min</option><option value="60">60 min</option><option value="90">90 min</option><option value="120">120 min</option></select></label>
            </div>
          </section>

          <section className="onboarding-section">
            <div className="onboarding-section-title"><UserRound size={20}/><div><strong>Primeiro profissional</strong><small>Cadastre uma pessoa real da equipe.</small></div></div>
            <label>Nome do profissional<input className="input" value={professionalName} onChange={e => setProfessionalName(e.target.value)} placeholder="Nome completo" required /></label>
          </section>

          {message && <div className="notice">{message}</div>}

          <div className="onboarding-submit">
            <div><CheckCircle2 size={18}/><span>Sem dados fictícios ou empresa de demonstração.</span></div>
            <button className="button button-primary" disabled={saving}>{saving ? 'Criando empresa...' : 'Criar minha agenda'}</button>
          </div>
        </form>
      </div>
    </main>
  )
}
