-- BarberAgenda 4.2.3 — Aviso de mensalidade pelo WhatsApp
-- Execute no Supabase SQL Editor.
-- Não envia mensagens automaticamente: adiciona os dados necessários para o
-- Admin Dev abrir o WhatsApp com a cobrança já preenchida.

drop function if exists public.dev_list_businesses(text,integer,integer);

create function public.dev_list_businesses(
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table(
  id uuid,
  name text,
  slug text,
  platform_status text,
  created_at timestamptz,
  updated_at timestamptz,
  owner_email text,
  member_count bigint,
  client_count bigint,
  appointment_count bigint,
  completed_revenue numeric,
  plan_id uuid,
  plan_name text,
  subscription_status text,
  current_period_ends_at timestamptz,
  last_appointment_at timestamptz,
  phone text,
  plan_price_monthly numeric,
  payment_url text
)
language sql
security definer
set search_path=public,auth
as $$
  select
    b.id,
    b.name,
    b.slug,
    b.platform_status,
    b.created_at,
    b.updated_at,
    (
      select u.email
      from public.business_members bm
      join auth.users u on u.id=bm.user_id
      where bm.business_id=b.id and bm.role='owner'
      order by bm.created_at
      limit 1
    ),
    (select count(*) from public.business_members bm where bm.business_id=b.id),
    (select count(*) from public.clients c where c.business_id=b.id),
    (select count(*) from public.appointments a where a.business_id=b.id),
    (
      select coalesce(sum(coalesce(a.final_amount,0)),0)
      from public.appointments a
      where a.business_id=b.id and a.status='completed'
    ),
    bs.plan_id,
    sp.name,
    bs.status,
    bs.current_period_ends_at,
    (select max(a.created_at) from public.appointments a where a.business_id=b.id),
    b.phone,
    sp.price_monthly,
    sp.payment_url
  from public.businesses b
  left join public.business_subscriptions bs on bs.business_id=b.id
  left join public.subscription_plans sp on sp.id=bs.plan_id
  where public.is_developer_admin()
    and (
      p_search is null
      or trim(p_search)=''
      or lower(b.name) like '%'||lower(trim(p_search))||'%'
      or lower(b.slug) like '%'||lower(trim(p_search))||'%'
    )
  order by b.created_at desc
  limit greatest(1,least(p_limit,500))
  offset greatest(0,p_offset);
$$;

revoke all on function public.dev_list_businesses(text,integer,integer) from public;
grant execute on function public.dev_list_businesses(text,integer,integer) to authenticated;
