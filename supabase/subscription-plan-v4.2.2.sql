-- BarberAgenda 4.2.2 — Plano Profissional + link de pagamento
-- Execute no Supabase SQL Editor.

alter table public.subscription_plans
  add column if not exists payment_url text;

insert into public.subscription_plans (
  code,
  name,
  description,
  price_monthly,
  max_professionals,
  max_team_members,
  features,
  active,
  sort_order,
  payment_url
)
values (
  'professional',
  'Plano Profissional',
  'Plano completo do BarberAgenda para gestão e agendamento de barbearias.',
  80.00,
  null,
  null,
  jsonb_build_object('items', jsonb_build_array(
    'Dashboard',
    'Agenda online',
    'Clientes',
    'Serviços',
    'Profissionais ilimitados',
    'Equipe ilimitada',
    'Disponibilidade',
    'Lista de espera',
    'Financeiro',
    'Relatórios',
    'Configurações',
    'Página pública de agendamento',
    'PWA',
    'Modo offline',
    'Upload de logo',
    'Upload de banner',
    'Suporte'
  )),
  true,
  2,
  'https://mpago.la/2tn4qBx'
)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  price_monthly = excluded.price_monthly,
  max_professionals = excluded.max_professionals,
  max_team_members = excluded.max_team_members,
  features = excluded.features,
  active = excluded.active,
  sort_order = excluded.sort_order,
  payment_url = excluded.payment_url,
  updated_at = now();

-- A assinatura continua sendo vinculada à empresa pelo Admin Dev.
-- O pagamento por link não confirma automaticamente o Mercado Pago.
-- Após confirmar o pagamento, marque a assinatura como active e informe current_period_ends_at.
