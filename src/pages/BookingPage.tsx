import { useCallback, useEffect, useMemo, useState } from 'react'
import type { FormEvent, ReactNode } from 'react'
import {
  ArrowRight,
  BadgeCheck,
  CalendarCheck2,
  CalendarDays,
  Check,
  Clock3,
  Info,
  ListOrdered,
  MapPin,
  MessageCircle,
  Phone,
  Radio,
  Scissors,
  ShieldCheck,
  Sparkles,
  UserRound,
} from 'lucide-react'
import { useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { getPendingOfflineCount } from '../lib/offline'
import type { Business, Professional, Service } from '../types'

type BusyRange = { start_time: string; end_time: string }
type DayRules = {
  is_open: boolean
  open_time: string
  close_time: string
  timezone: string
  booking_advance_days: number
  min_booking_notice_minutes: number
}
type MessageKind = 'error' | 'success' | 'info'
type BookingResult = {
  status: 'confirmed' | 'pending' | 'queued'
  serviceName: string
  professionalName: string
  appointmentDate: string
  appointmentTime: string
  duration: number
  price: number
}

const toMinutes = (time: string) => {
  const [h, m] = time.slice(0, 5).split(':').map(Number)
  return h * 60 + m
}
const fromMinutes = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`
const localISO = (d = new Date()) => {
  const offset = d.getTimezoneOffset()
  return new Date(d.getTime() - offset * 60000).toISOString().slice(0, 10)
}
const addDays = (days: number) => {
  const d = new Date()
  d.setDate(d.getDate() + days)
  return localISO(d)
}
const cleanPhone = (v: string) => v.replace(/\D/g, '').slice(0, 15)
const money = (value: number) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(value || 0))

const whatsappNumber = (value: string) => {
  const digits = cleanPhone(value)
  if (!digits) return ''
  if (digits.startsWith('55') && digits.length >= 12) return digits
  if (digits.length === 10 || digits.length === 11) return `55${digits}`
  return digits
}
const whatsappLink = (phone: string, message: string) => {
  const number = whatsappNumber(phone)
  return number ? `https://wa.me/${number}?text=${encodeURIComponent(message)}` : ''
}
const formatDate = (value: string, compact = false) => {
  if (!value) return '—'
  const date = new Date(`${value}T12:00:00`)
  return new Intl.DateTimeFormat('pt-BR', compact
    ? { weekday: 'short', day: '2-digit', month: '2-digit' }
    : { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' }).format(date)
}
const formatPhone = (value: string) => {
  const digits = cleanPhone(value)
  if (digits.length <= 2) return digits
  if (digits.length <= 6) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`
  if (digits.length <= 10) return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`
  if (digits.length <= 11) return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`
  return digits
}

export function BookingPage() {
  const { slug } = useParams()
  const [business, setBusiness] = useState<Business | null>(null)
  const [services, setServices] = useState<Service[]>([])
  const [professionals, setProfessionals] = useState<Professional[]>([])
  const [serviceId, setServiceId] = useState('')
  const [professionalId, setProfessionalId] = useState('')
  const [date, setDate] = useState(localISO())
  const [time, setTime] = useState('')
  const [busyRanges, setBusyRanges] = useState<BusyRange[]>([])
  const [blockRanges, setBlockRanges] = useState<BusyRange[]>([])
  const [dayRules, setDayRules] = useState<DayRules | null>(null)
  const [clientName, setClientName] = useState('')
  const [clientPhone, setClientPhone] = useState('')
  const [appointmentNotes, setAppointmentNotes] = useState('')
  const [acceptedPolicy, setAcceptedPolicy] = useState(false)
  const [message, setMessage] = useState('')
  const [messageKind, setMessageKind] = useState<MessageKind>('info')
  const [loading, setLoading] = useState(true)
  const [availabilityLoading, setAvailabilityLoading] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [realtimeConnected, setRealtimeConnected] = useState(false)
  const [waitlistOpen, setWaitlistOpen] = useState(false)
  const [waitlistPeriod, setWaitlistPeriod] = useState('any')
  const [waitlistNotes, setWaitlistNotes] = useState('')
  const [waitlistSubmitting, setWaitlistSubmitting] = useState(false)
  const [bookingResult, setBookingResult] = useState<BookingResult | null>(null)
  const [isOnline, setIsOnline] = useState(() => typeof navigator === 'undefined' ? true : navigator.onLine)

  const showMessage = (text: string, kind: MessageKind = 'error') => {
    setMessage(text)
    setMessageKind(kind)
  }
  const clearMessage = () => setMessage('')

  useEffect(() => {
    const online = () => setIsOnline(true)
    const offline = () => { setIsOnline(false); setRealtimeConnected(false) }
    window.addEventListener('online', online)
    window.addEventListener('offline', offline)
    return () => {
      window.removeEventListener('online', online)
      window.removeEventListener('offline', offline)
    }
  }, [])

  useEffect(() => {
    ;(async () => {
      setLoading(true)
      const { data: b, error } = await supabase.from('businesses').select('*').eq('slug', slug).maybeSingle()
      if (error || !b) {
        setLoading(false)
        return
      }
      setBusiness(b)
      const [{ data: s }, { data: p }] = await Promise.all([
        supabase.from('services').select('*').eq('business_id', b.id).eq('active', true).order('name'),
        supabase.from('professionals').select('*').eq('business_id', b.id).eq('active', true).order('name'),
      ])
      setServices(s || [])
      setProfessionals(p || [])
      setLoading(false)
    })()
  }, [slug])

  const loadAvailability = useCallback(async () => {
    if (!business || !professionalId || !date) {
      setBusyRanges([])
      setBlockRanges([])
      setDayRules(null)
      return
    }
    setAvailabilityLoading(true)
    const [{ data: busy, error }, { data: rules, error: rulesError }, { data: blocks, error: blocksError }] =
      await Promise.all([
        supabase.rpc('get_busy_ranges', {
          p_business_id: business.id,
          p_professional_id: professionalId,
          p_date: date,
        }),
        supabase.rpc('get_booking_day_rules', {
          p_business_id: business.id,
          p_professional_id: professionalId,
          p_date: date,
        }),
        supabase.rpc('get_public_schedule_blocks', {
          p_business_id: business.id,
          p_professional_id: professionalId,
          p_date: date,
        }),
      ])
    setAvailabilityLoading(false)
    if (error || rulesError || blocksError) {
      const e = error || rulesError || blocksError
      console.error(e)
      if ((e?.message || '').includes('schema cache') || (e?.code || '') === 'PGRST202') {
        showMessage('A agenda ainda está sendo configurada. Tente novamente em alguns instantes.', 'info')
      }
    }
    setBusyRanges((busy || []).map((x: BusyRange) => ({ start_time: x.start_time.slice(0, 5), end_time: x.end_time.slice(0, 5) })))
    setBlockRanges((blocks || []).map((x: BusyRange) => ({ start_time: x.start_time.slice(0, 5), end_time: x.end_time.slice(0, 5) })))
    setDayRules((rules?.[0] || null) as DayRules | null)
  }, [business, professionalId, date])

  useEffect(() => {
    loadAvailability()
  }, [loadAvailability])

  useEffect(() => {
    if (!business) return
    const ch = supabase
      .channel(`booking-live:${business.id}:${professionalId || 'all'}:${date}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'availability_slots', filter: `business_id=eq.${business.id}` }, loadAvailability)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'availability_blocks', filter: `business_id=eq.${business.id}` }, loadAvailability)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'business_hours', filter: `business_id=eq.${business.id}` }, loadAvailability)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'appointments', filter: `business_id=eq.${business.id}` }, loadAvailability)
      .subscribe((s) => setRealtimeConnected(s === 'SUBSCRIBED'))
    return () => {
      setRealtimeConnected(false)
      supabase.removeChannel(ch)
    }
  }, [business, professionalId, date, loadAvailability])

  const selectedService = services.find((s) => s.id === serviceId)
  const selectedProfessional = professionals.find((p) => p.id === professionalId)

  const availableTimes = useMemo(() => {
    if (!selectedService || !dayRules?.is_open) return []
    const opening = toMinutes(dayRules.open_time)
    const closing = toMinutes(dayRules.close_time)
    const step = business?.slot_interval || 30
    const result: string[] = []
    const allBlocked = [...busyRanges, ...blockRanges]
    const now = new Date()
    for (let current = opening; current + selectedService.duration_minutes <= closing; current += step) {
      const candidate = fromMinutes(current)
      const candidateEnd = current + selectedService.duration_minutes
      const overlaps = allBlocked.some((r) => current < toMinutes(r.end_time) && candidateEnd > toMinutes(r.start_time))
      let tooSoon = false
      if (date === localISO()) {
        const currentNow = now.getHours() * 60 + now.getMinutes()
        tooSoon = current < currentNow + (dayRules.min_booking_notice_minutes || 0)
      }
      if (!overlaps && !tooSoon) result.push(candidate)
    }
    return result
  }, [selectedService, dayRules, business, busyRanges, blockRanges, date])

  const timeGroups = useMemo(() => ({
    morning: availableTimes.filter((slot) => toMinutes(slot) < 12 * 60),
    afternoon: availableTimes.filter((slot) => toMinutes(slot) >= 12 * 60 && toMinutes(slot) < 18 * 60),
    evening: availableTimes.filter((slot) => toMinutes(slot) >= 18 * 60),
  }), [availableTimes])

  const quickDates = useMemo(() => {
    const maxDays = Math.max(1, Math.min(7, business?.booking_advance_days || 60))
    return Array.from({ length: maxDays }, (_, index) => {
      const value = addDays(index)
      return { value, label: index === 0 ? 'Hoje' : index === 1 ? 'Amanhã' : formatDate(value, true) }
    })
  }, [business?.booking_advance_days])

  useEffect(() => {
    if (time && !availableTimes.includes(time)) {
      setTime('')
      showMessage('Esse horário não está mais disponível. Escolha outro horário.')
    }
  }, [availableTimes, time])

  const currentStep = !serviceId ? 1 : !professionalId ? 2 : !time ? 3 : 4
  const completion = currentStep === 4 ? (clientName.trim() && cleanPhone(clientPhone).length >= 8 ? 100 : 88) : currentStep === 3 ? 62 : currentStep === 2 ? 38 : 15
  const canSubmit = Boolean(
    business && selectedService && professionalId && date && time && clientName.trim() && cleanPhone(clientPhone).length >= 8 && acceptedPolicy,
  )

  const businessWhatsAppUrl = business?.phone
    ? whatsappLink(business.phone, `Olá! Vim pela agenda online da ${business.name} e gostaria de tirar uma dúvida.`)
    : ''

  const bookingWhatsAppUrl = business?.phone && bookingResult
    ? whatsappLink(
        business.phone,
        [
          `Olá! Fiz um agendamento pela agenda online da ${business.name}.`,
          '',
          `Cliente: ${clientName.trim()}`,
          `Serviço: ${bookingResult.serviceName}`,
          `Profissional: ${bookingResult.professionalName}`,
          `Data: ${formatDate(bookingResult.appointmentDate)}`,
          `Horário: ${bookingResult.appointmentTime}`,
          `Duração: ${bookingResult.duration} min`,
          `Valor: ${money(bookingResult.price)}`,
          `Status: ${bookingResult.status === 'queued' ? 'Salvo offline, aguardando sincronização' : bookingResult.status === 'confirmed' ? 'Confirmado' : 'Aguardando confirmação'}.`,
        ].join('\n'),
      )
    : ''

  async function submitBooking() {
    if (!business || !selectedService || !selectedProfessional || !professionalId || !date || !time) {
      return showMessage('Escolha serviço, profissional, data e horário.')
    }
    if (!clientName.trim() || cleanPhone(clientPhone).length < 8) {
      return showMessage('Preencha seu nome e um telefone válido.')
    }
    if (!acceptedPolicy) {
      return showMessage('Confirme que revisou os dados e as regras do agendamento.')
    }
    setSubmitting(true)
    clearMessage()
    const endTime = fromMinutes(toMinutes(time) + selectedService.duration_minutes)
    const status: 'pending' | 'confirmed' = business.auto_confirm_bookings === false ? 'pending' : 'confirmed'
    const pendingBefore = await getPendingOfflineCount()
    const { error } = await supabase.from('appointments').insert({
      business_id: business.id,
      professional_id: professionalId,
      service_id: selectedService.id,
      client_name: clientName.trim(),
      client_phone: cleanPhone(clientPhone),
      appointment_date: date,
      start_time: time,
      end_time: endTime,
      status,
      notes: appointmentNotes.trim() || null,
      final_amount: Number(selectedService.price),
      payment_status: 'unpaid',
    })
    setSubmitting(false)
    const pendingAfter = await getPendingOfflineCount()
    const queuedOffline = pendingAfter > pendingBefore
    if (error) {
      await loadAvailability()
      const msg = error.message.includes('appointments_no_overlap')
        ? 'Esse horário acabou de ser reservado por outra pessoa. Escolha outro horário.'
        : error.message.includes('appointment_schedule_blocked')
          ? 'Este período foi bloqueado pela empresa. Escolha outro horário.'
          : error.message.includes('appointment_outside_working_hours')
            ? 'O horário está fora da jornada do profissional.'
            : `Não foi possível agendar: ${error.message}`
      showMessage(msg)
      return
    }
    setBookingResult({
      status: queuedOffline ? 'queued' : status,
      serviceName: selectedService.name,
      professionalName: selectedProfessional.name,
      appointmentDate: date,
      appointmentTime: time,
      duration: selectedService.duration_minutes,
      price: Number(selectedService.price),
    })
    showMessage(queuedOffline
      ? 'Agendamento salvo neste aparelho. Quando a internet voltar, o sistema irá sincronizar e validar o horário.'
      : status === 'confirmed' ? 'Agendamento confirmado com sucesso!' : 'Solicitação enviada com sucesso!', 'success')
    if (!queuedOffline) await loadAvailability()
  }

  async function joinWaitlist(e: FormEvent) {
    e.preventDefault()
    if (!business || !selectedService || !clientName.trim() || cleanPhone(clientPhone).length < 8) {
      return showMessage('Informe seu nome, telefone e o serviço desejado.')
    }
    setWaitlistSubmitting(true)
    const pendingBefore = await getPendingOfflineCount()
    const { error } = await supabase.from('waitlist_entries').insert({
      business_id: business.id,
      service_id: selectedService.id,
      professional_id: professionalId || null,
      client_name: clientName.trim(),
      client_phone: cleanPhone(clientPhone),
      desired_date: date,
      preferred_period: waitlistPeriod,
      notes: waitlistNotes.trim() || null,
      status: 'waiting',
      source: 'public',
    })
    setWaitlistSubmitting(false)
    const pendingAfter = await getPendingOfflineCount()
    if (error) return showMessage(`Não foi possível entrar na lista de espera: ${error.message}`)
    showMessage(pendingAfter > pendingBefore
      ? 'Lista de espera salva offline. Ela será sincronizada quando a conexão voltar.'
      : 'Você entrou na lista de espera. A empresa poderá entrar em contato caso surja uma vaga.', 'success')
    setWaitlistOpen(false)
    setWaitlistNotes('')
  }

  function resetBooking() {
    setServiceId('')
    setProfessionalId('')
    setDate(localISO())
    setTime('')
    setClientName('')
    setClientPhone('')
    setAppointmentNotes('')
    setAcceptedPolicy(false)
    setWaitlistOpen(false)
    setBookingResult(null)
    clearMessage()
  }

  if (loading) {
    return <div className="center-screen booking-loading"><div className="booking-loader"/><p>Carregando agenda...</p></div>
  }
  if (!business) {
    return <div className="center-screen"><div className="empty-card"><h2>Empresa não encontrada</h2><p>Verifique se o link de agendamento está correto.</p></div></div>
  }
  if (business.platform_status && business.platform_status !== 'active') {
    return <div className="center-screen"><div className="empty-card"><h2>Agenda indisponível</h2><p>Esta empresa está temporariamente indisponível na plataforma.</p></div></div>
  }
  if (business.booking_enabled === false) {
    return <div className="center-screen"><div className="empty-card"><h2>Agendamentos pausados</h2><p>A empresa desativou temporariamente novos agendamentos online.</p></div></div>
  }

  if (bookingResult) {
    return <main className="booking-page booking-success-page">
      <div className="booking-success-shell">
        <div className="booking-success-icon"><BadgeCheck size={42}/></div>
        <span className="eyebrow">AGENDAMENTO RECEBIDO</span>
        <h1>{bookingResult.status === 'queued' ? 'Agendamento salvo offline.' : bookingResult.status === 'confirmed' ? 'Seu horário está confirmado.' : 'Sua solicitação foi enviada.'}</h1>
        <p>{bookingResult.status === 'queued'
          ? 'Sem internet no momento. O BarberAgenda guardou a solicitação neste aparelho e tentará sincronizar automaticamente quando a conexão voltar. O horário só será confirmado após a sincronização.'
          : bookingResult.status === 'confirmed' ? 'Pronto! Guarde os dados abaixo para o dia do atendimento.' : 'A empresa irá analisar a solicitação antes de confirmar o horário.'}</p>
        <div className="booking-success-card">
          <div><span>Serviço</span><strong>{bookingResult.serviceName}</strong></div>
          <div><span>Profissional</span><strong>{bookingResult.professionalName}</strong></div>
          <div><span>Data</span><strong>{formatDate(bookingResult.appointmentDate)}</strong></div>
          <div><span>Horário</span><strong>{bookingResult.appointmentTime}</strong></div>
          <div><span>Duração</span><strong>{bookingResult.duration} min</strong></div>
          <div><span>Valor</span><strong>{money(bookingResult.price)}</strong></div>
        </div>
        {(business.address || business.phone) && <div className="booking-business-details">
          {business.address && <span><MapPin size={16}/>{business.address}</span>}
          {business.phone && <span><Phone size={16}/>{business.phone}</span>}
        </div>}
        <div className="booking-success-actions">
          {bookingWhatsAppUrl && <a className="button booking-whatsapp-button" href={bookingWhatsAppUrl} target="_blank" rel="noreferrer"><MessageCircle size={17}/> Enviar confirmação no WhatsApp</a>}
          <button className="button button-primary" onClick={resetBooking}>Fazer outro agendamento <ArrowRight size={17}/></button>
        </div>
        <small className="booking-secure-note"><ShieldCheck size={14}/> Seus dados são usados somente para a gestão do agendamento.</small>
      </div>
    </main>
  }

  return <main className="booking-page booking-pro-page">
    <header className="booking-pro-header">
      <div className="container booking-pro-header-inner">
        <div className="booking-business-brand">
          {business.logo_url ? <img src={business.logo_url} alt={business.name}/> : <span className="brand-icon"><Scissors size={21}/></span>}
          <div><strong>{business.name}</strong><small>{business.public_booking_message || 'Escolha seu serviço e reserve um horário em tempo real.'}</small></div>
        </div>
        <div className="booking-header-meta">
          {businessWhatsAppUrl && <a className="booking-header-whatsapp" href={businessWhatsAppUrl} target="_blank" rel="noreferrer"><MessageCircle size={14}/><span>WhatsApp</span></a>}
          <span className={`live-badge ${!isOnline ? 'offline' : realtimeConnected ? 'online' : 'connecting'}`}><Radio size={14}/>{!isOnline ? 'Modo offline' : realtimeConnected ? 'Agenda ao vivo' : 'Conectando...'}</span>
          {business.address && <span className="booking-location"><MapPin size={14}/>{business.address}</span>}
        </div>
      </div>
    </header>

    <div className="container booking-pro-container">
      <section className="booking-progress-card">
        <div className="booking-progress-head">
          <div><span className="eyebrow">AGENDAMENTO ONLINE</span><h1>Reserve seu horário</h1></div>
          <strong>{completion}%</strong>
        </div>
        <div className="booking-progress-track"><span style={{ width: `${completion}%` }}/></div>
        <div className="booking-stepper">
          {[
            [1, 'Serviço'], [2, 'Profissional'], [3, 'Data e horário'], [4, 'Seus dados'],
          ].map(([step, label]) => <div key={String(step)} className={`booking-stepper-item ${currentStep >= Number(step) ? 'active' : ''} ${currentStep > Number(step) ? 'done' : ''}`}>
            <span>{currentStep > Number(step) ? <Check size={14}/> : step}</span><small>{label}</small>
          </div>)}
        </div>
      </section>

      <div className="booking-pro-layout">
        <div className="booking-pro-main">
          <section className={`booking-card booking-pro-card ${serviceId ? 'completed' : 'current'}`}>
            <div className="booking-card-head"><div className="step-title"><span>1</span><Scissors size={18}/><div><strong>Escolha o serviço</strong><small>Selecione o atendimento que deseja realizar.</small></div></div>{serviceId && <BadgeCheck size={20}/>}</div>
            <div className="booking-service-grid">
              {services.map((s) => <button key={s.id} className={`booking-service-card ${serviceId === s.id ? 'selected' : ''}`} onClick={() => { setServiceId(s.id); setProfessionalId(''); setTime(''); setWaitlistOpen(false); clearMessage() }}>
                <div className="booking-service-main"><span className="booking-service-icon"><Scissors size={17}/></span><div><strong>{s.name}</strong><small>{s.description || 'Atendimento profissional'}</small></div></div>
                <div className="booking-service-meta"><span><Clock3 size={14}/>{s.duration_minutes} min</span><b>{money(Number(s.price))}</b></div>
              </button>)}
            </div>
            {!services.length && <div className="booking-empty-state"><Info size={18}/><p>Nenhum serviço disponível no momento.</p></div>}
          </section>

          <section className={`booking-card booking-pro-card ${!serviceId ? 'locked' : professionalId ? 'completed' : 'current'}`}>
            <div className="booking-card-head"><div className="step-title"><span>2</span><UserRound size={18}/><div><strong>Escolha o profissional</strong><small>{serviceId ? 'Selecione quem irá realizar o atendimento.' : 'Escolha um serviço para continuar.'}</small></div></div>{professionalId && <BadgeCheck size={20}/>}</div>
            {serviceId && <div className="booking-professional-grid">
              {professionals.map((p) => <button key={p.id} className={`booking-professional-card ${professionalId === p.id ? 'selected' : ''}`} onClick={() => { setProfessionalId(p.id); setTime(''); setWaitlistOpen(false); clearMessage() }}>
                <span className="booking-avatar">{p.photo_url ? <img src={p.photo_url} alt={p.name}/> : <UserRound size={20}/>}</span>
                <div><strong>{p.name}</strong><small>{p.bio || 'Profissional'}</small></div>
                <span className="booking-select-indicator">{professionalId === p.id ? <Check size={15}/> : null}</span>
              </button>)}
            </div>}
          </section>

          <section className={`booking-card booking-pro-card ${!serviceId || !professionalId ? 'locked' : time ? 'completed' : 'current'}`}>
            <div className="booking-card-head"><div className="step-title"><span>3</span><CalendarDays size={18}/><div><strong>Escolha a data e o horário</strong><small>{professionalId ? 'A disponibilidade é atualizada automaticamente.' : 'Escolha serviço e profissional para ver a agenda.'}</small></div></div>{time && <BadgeCheck size={20}/>}</div>
            {serviceId && professionalId && <>
              <div className="booking-quick-dates">
                {quickDates.map((item) => <button key={item.value} className={date === item.value ? 'selected' : ''} onClick={() => { setDate(item.value); setTime(''); setWaitlistOpen(false); clearMessage() }}><small>{item.label}</small><strong>{item.value.slice(8, 10)}</strong></button>)}
              </div>
              <label className="booking-date-field"><span>Outra data</span><input className="input" type="date" min={localISO()} max={addDays(business.booking_advance_days || 60)} value={date} onChange={(e) => { setDate(e.target.value); setTime(''); setWaitlistOpen(false); clearMessage() }}/></label>
              <div className="booking-selected-date"><CalendarCheck2 size={16}/><span>{formatDate(date)}</span>{dayRules?.is_open && <small>{dayRules.open_time.slice(0, 5)} às {dayRules.close_time.slice(0, 5)}</small>}</div>
              {availabilityLoading && <div className="booking-availability-loading"><div className="booking-loader small"/> Buscando horários livres...</div>}
              {!availabilityLoading && dayRules && !dayRules.is_open && <div className="notice"><Info size={16}/> Este profissional não atende nesta data.</div>}
              {!availabilityLoading && dayRules?.is_open && availableTimes.length > 0 && <div className="booking-time-sections">
                {timeGroups.morning.length > 0 && <TimeGroup title="Manhã" times={timeGroups.morning} selected={time} onSelect={(slot) => { setTime(slot); setWaitlistOpen(false); clearMessage() }}/>} 
                {timeGroups.afternoon.length > 0 && <TimeGroup title="Tarde" times={timeGroups.afternoon} selected={time} onSelect={(slot) => { setTime(slot); setWaitlistOpen(false); clearMessage() }}/>} 
                {timeGroups.evening.length > 0 && <TimeGroup title="Noite" times={timeGroups.evening} selected={time} onSelect={(slot) => { setTime(slot); setWaitlistOpen(false); clearMessage() }}/>} 
              </div>}
              {!availabilityLoading && serviceId && professionalId && dayRules?.is_open && availableTimes.length === 0 && <div className="booking-no-slots">
                <div><CalendarDays size={22}/><div><strong>Sem horários livres nesta data</strong><p>Escolha outro dia ou entre na lista de espera.</p></div></div>
                {business.allow_waitlist !== false && <button className="button button-secondary" onClick={() => setWaitlistOpen(true)}><ListOrdered size={16}/> Entrar na lista de espera</button>}
              </div>}
            </>}
          </section>

          <section className={`booking-card booking-pro-card ${!time && !waitlistOpen ? 'locked' : 'current'}`}>
            <div className="booking-card-head"><div className="step-title"><span>4</span><UserRound size={18}/><div><strong>Seus dados</strong><small>{waitlistOpen ? 'Preencha para entrar na lista de espera.' : time ? 'Só falta identificar quem está reservando.' : 'Escolha um horário para continuar.'}</small></div></div></div>
            {(time || waitlistOpen) && <>
              <div className="booking-form-grid">
                <label><span>Nome completo</span><input className="input" placeholder="Ex.: Jonas Henrique" value={clientName} onChange={(e) => setClientName(e.target.value)}/></label>
                <label><span>Telefone</span><input className="input" inputMode="tel" placeholder="(17) 99999-9999" value={clientPhone} onChange={(e) => setClientPhone(formatPhone(e.target.value))}/></label>
              </div>
              {!waitlistOpen && <label className="booking-full-field"><span>Observação <em>opcional</em></span><textarea className="input textarea" value={appointmentNotes} onChange={(e) => setAppointmentNotes(e.target.value)} placeholder="Ex.: preferência, observação do atendimento ou informação importante."/></label>}

              {!waitlistOpen ? <>
                <label className="booking-policy-check"><input type="checkbox" checked={acceptedPolicy} onChange={(e) => setAcceptedPolicy(e.target.checked)}/><span><strong>Revisei os dados do agendamento</strong><small>Estou ciente do horário escolhido{business.cancellation_notice_hours ? ` e do prazo de ${business.cancellation_notice_hours}h para cancelamento.` : '.'}</small></span></label>
                <button className="button button-primary full booking-confirm-button" onClick={submitBooking} disabled={submitting || !canSubmit}>{submitting ? 'Confirmando...' : business.auto_confirm_bookings === false ? 'Enviar solicitação de agendamento' : 'Confirmar agendamento'} {!submitting && <ArrowRight size={17}/>}</button>
              </> : <form className="waitlist-public-form booking-waitlist-pro" onSubmit={joinWaitlist}>
                <div className="waitlist-public-head"><ListOrdered size={18}/><div><strong>Lista de espera</strong><small>Data desejada: {formatDate(date)}</small></div></div>
                <label>Período preferido<select className="input" value={waitlistPeriod} onChange={(e) => setWaitlistPeriod(e.target.value)}><option value="any">Qualquer horário</option><option value="morning">Manhã</option><option value="afternoon">Tarde</option><option value="evening">Noite</option></select></label>
                <label>Observação (opcional)<textarea className="input textarea" value={waitlistNotes} onChange={(e) => setWaitlistNotes(e.target.value)} placeholder="Ex.: consigo chegar com 20 minutos de antecedência."/></label>
                <div className="form-actions"><button type="button" className="button button-secondary" onClick={() => setWaitlistOpen(false)}>Voltar</button><button className="button button-primary" disabled={waitlistSubmitting}>{waitlistSubmitting ? 'Enviando...' : 'Entrar na lista'}</button></div>
              </form>}
            </>}
            {message && <div className={`notice booking-message ${messageKind}`}><Info size={16}/><span>{message}</span></div>}
          </section>
        </div>

        <aside className="booking-summary-column">
          <div className="booking-summary-card">
            <div className="booking-summary-head"><div><span className="eyebrow">RESUMO</span><h2>Seu agendamento</h2></div><Sparkles size={20}/></div>
            <div className="booking-summary-list">
              <SummaryRow icon={<Scissors size={17}/>} label="Serviço" value={selectedService?.name || 'Não selecionado'} muted={!selectedService}/>
              <SummaryRow icon={<UserRound size={17}/>} label="Profissional" value={selectedProfessional?.name || 'Não selecionado'} muted={!selectedProfessional}/>
              <SummaryRow icon={<CalendarDays size={17}/>} label="Data" value={date ? formatDate(date, true) : 'Não selecionada'} muted={!professionalId}/>
              <SummaryRow icon={<Clock3 size={17}/>} label="Horário" value={time || 'Não selecionado'} muted={!time}/>
            </div>
            {selectedService && <div className="booking-summary-total"><div><span>Duração estimada</span><strong>{selectedService.duration_minutes} min</strong></div><div><span>Valor do serviço</span><strong>{money(Number(selectedService.price))}</strong></div></div>}
            <div className="booking-summary-info">
              <span><ShieldCheck size={15}/> Reserva protegida por validação de disponibilidade.</span>
              <span><Radio size={15}/> Horários sincronizados em tempo real.</span>
              {business.auto_confirm_bookings === false && <span><Info size={15}/> O agendamento depende de confirmação da empresa.</span>}
            </div>
          </div>

          <div className="booking-business-card">
            <div className="booking-business-card-title">Sobre o estabelecimento</div>
            {business.address && <span><MapPin size={16}/><div><small>Endereço</small><strong>{business.address}</strong></div></span>}
            {business.phone && <span><Phone size={16}/><div><small>Telefone</small><strong>{business.phone}</strong></div></span>}
            {businessWhatsAppUrl && <a className="booking-business-whatsapp" href={businessWhatsAppUrl} target="_blank" rel="noreferrer"><MessageCircle size={16}/><div><small>Atendimento</small><strong>Falar no WhatsApp</strong></div><ArrowRight size={14}/></a>}
            <span><Clock3 size={16}/><div><small>Horário geral</small><strong>{business.opening_time?.slice(0, 5)} às {business.closing_time?.slice(0, 5)}</strong></div></span>
          </div>
        </aside>
      </div>

      <footer className="booking-public-footer"><ShieldCheck size={15}/> <span>Agendamento seguro • Seus dados são utilizados somente para operação do atendimento.</span></footer>
    </div>
  </main>
}

function TimeGroup({ title, times, selected, onSelect }: { title: string; times: string[]; selected: string; onSelect: (slot: string) => void }) {
  return <div className="booking-time-group"><div className="booking-time-group-title"><span>{title}</span><small>{times.length} {times.length === 1 ? 'horário' : 'horários'}</small></div><div className="time-grid booking-time-grid">{times.map((slot) => <button key={slot} className={`time-button ${selected === slot ? 'selected' : ''}`} onClick={() => onSelect(slot)}><Clock3 size={15}/>{slot}</button>)}</div></div>
}

function SummaryRow({ icon, label, value, muted }: { icon: ReactNode; label: string; value: string; muted?: boolean }) {
  return <div className={`booking-summary-row ${muted ? 'muted-row' : ''}`}><span className="booking-summary-icon">{icon}</span><div><small>{label}</small><strong>{value}</strong></div>{!muted && <Check size={15}/>}</div>
}
