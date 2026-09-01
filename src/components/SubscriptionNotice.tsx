import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, CheckCircle2, CreditCard, ExternalLink } from 'lucide-react'
import { supabase } from '../lib/supabase'

type Plan = {
  id: string
  code: string
  name: string
  price_monthly: number
  payment_url: string | null
  max_professionals: number | null
  max_team_members: number | null
}

type Subscription = {
  business_id: string
  plan_id: string | null
  status: 'trialing' | 'active' | 'past_due' | 'paused' | 'canceled'
  trial_ends_at: string | null
  current_period_ends_at: string | null
  subscription_plans: Plan | null
}

const FALLBACK_PAYMENT_URL = 'https://mpago.la/2tn4qBx'
const money = (value: number) => new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(value || 0))

function daysUntil(value: string | null) {
  if (!value) return null
  const end = new Date(value).getTime()
  const now = Date.now()
  return Math.ceil((end - now) / 86400000)
}

export function SubscriptionNotice({ businessId }: { businessId: string }) {
  const [subscription, setSubscription] = useState<Subscription | null>(null)
  const [defaultPlan, setDefaultPlan] = useState<Plan | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    const [{ data: sub }, { data: fallback }] = await Promise.all([
      supabase
        .from('business_subscriptions')
        .select('business_id,plan_id,status,trial_ends_at,current_period_ends_at,subscription_plans(id,code,name,price_monthly,payment_url,max_professionals,max_team_members)')
        .eq('business_id', businessId)
        .maybeSingle(),
      supabase
        .from('subscription_plans')
        .select('id,code,name,price_monthly,payment_url,max_professionals,max_team_members')
        .eq('code', 'professional')
        .eq('active', true)
        .maybeSingle(),
    ])
    setSubscription((sub || null) as Subscription | null)
    setDefaultPlan((fallback || null) as Plan | null)
    setLoading(false)
  }, [businessId])

  useEffect(() => { void load() }, [load])

  useEffect(() => {
    const ch = supabase
      .channel(`subscription-notice:${businessId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'business_subscriptions', filter: `business_id=eq.${businessId}` }, () => void load())
      .subscribe()
    return () => { void supabase.removeChannel(ch) }
  }, [businessId, load])

  const plan = subscription?.subscription_plans || defaultPlan
  const dueIn = daysUntil(subscription?.current_period_ends_at || subscription?.trial_ends_at || null)

  const state = useMemo(() => {
    if (!subscription) return 'not_subscribed' as const
    if (subscription.status === 'past_due') return 'past_due' as const
    if (subscription.status === 'paused' || subscription.status === 'canceled') return 'inactive' as const
    if (dueIn !== null && dueIn < 0) return 'past_due' as const
    if (dueIn !== null && dueIn <= 5) return 'due_soon' as const
    return 'active' as const
  }, [subscription, dueIn])

  if (loading || !plan) return null

  const paymentUrl = plan.payment_url || FALLBACK_PAYMENT_URL
  const price = money(Number(plan.price_monthly || 80))
  const dueDate = subscription?.current_period_ends_at
    ? new Date(subscription.current_period_ends_at).toLocaleDateString('pt-BR')
    : null

  const copy = state === 'past_due'
    ? { title: 'Pagamento pendente', text: `Sua mensalidade de ${price}/mês está em aberto. Regularize para manter o BarberAgenda ativo.`, tone: 'danger' }
    : state === 'due_soon'
      ? { title: 'Sua mensalidade vence em breve', text: `O plano ${plan.name} custa ${price}/mês${dueDate ? ` e vence em ${dueDate}` : ''}.`, tone: 'warning' }
      : state === 'inactive'
        ? { title: 'Assinatura inativa', text: `Regularize o plano ${plan.name} por ${price}/mês para continuar utilizando os recursos contratados.`, tone: 'danger' }
        : state === 'not_subscribed'
          ? { title: 'Ative seu plano BarberAgenda', text: `${plan.name} por ${price}/mês, com profissionais e equipe ilimitados.`, tone: 'warning' }
          : { title: `${plan.name} ativo`, text: `${price}/mês${dueDate ? ` • próxima renovação em ${dueDate}` : ''}.`, tone: 'success' }

  return <section className={`subscription-notice subscription-notice-${copy.tone}`}>
    <div className="subscription-notice-icon">
      {copy.tone === 'success' ? <CheckCircle2 size={24}/> : copy.tone === 'danger' ? <AlertTriangle size={24}/> : <CreditCard size={24}/>} 
    </div>
    <div className="subscription-notice-copy">
      <span className="eyebrow">PLANO & MENSALIDADE</span>
      <h2>{copy.title}</h2>
      <p>{copy.text}</p>
      <div className="subscription-notice-meta">
        <span>Profissionais: <strong>{plan.max_professionals ?? 'Ilimitado'}</strong></span>
        <span>Equipe: <strong>{plan.max_team_members ?? 'Ilimitado'}</strong></span>
      </div>
    </div>
    <a className="button button-primary subscription-pay-button" href={paymentUrl} target="_blank" rel="noreferrer">
      <CreditCard size={17}/>{state === 'active' ? `Pagar ${price}` : state === 'past_due' || state === 'inactive' ? 'Regularizar pagamento' : `Pagar ${price}`}<ExternalLink size={14}/>
    </a>
  </section>
}
