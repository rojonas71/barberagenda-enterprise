-- ============================================================
-- BARBERAGENDA PRO ADVANCED — ADMIN DEV / SUPER ADMIN
-- Execute após advanced-professional-upgrade.sql em bancos existentes.
-- Seguro para reexecução (idempotente sempre que possível).
-- ============================================================

create extension if not exists pgcrypto;

-- Estado global das empresas.
alter table public.businesses add column if not exists platform_status text not null default 'active';
alter table public.businesses add column if not exists suspended_at timestamptz;
alter table public.businesses add column if not exists suspended_reason text;
alter table public.businesses add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname='businesses_platform_status_check'
  ) then
    alter table public.businesses add constraint businesses_platform_status_check
      check (platform_status in ('active','suspended','archived'));
  end if;
end $$;

-- Administradores globais da plataforma.
create table if not exists public.developer_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'read_only' check (role in ('super_admin','support','billing','ops','read_only')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.is_developer_admin()
returns boolean
language sql stable security definer set search_path=public,auth as $$
  select exists(
    select 1 from public.developer_admins da
    where da.user_id=auth.uid() and da.active
  );
$$;

create or replace function public.dev_current_role()
returns text
language sql stable security definer set search_path=public,auth as $$
  select da.role from public.developer_admins da
  where da.user_id=auth.uid() and da.active
  limit 1;
$$;

grant execute on function public.is_developer_admin() to authenticated;
grant execute on function public.dev_current_role() to authenticated;

-- Catálogo de planos (não cria preços fictícios automaticamente).
create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  description text,
  price_monthly numeric(10,2) not null default 0 check(price_monthly>=0),
  max_professionals integer,
  max_team_members integer,
  features jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_subscriptions (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  plan_id uuid references public.subscription_plans(id) on delete set null,
  status text not null default 'trialing' check(status in ('trialing','active','past_due','paused','canceled')),
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  external_customer_id text,
  external_subscription_id text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Suporte global.
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  subject text not null,
  message text not null,
  category text not null default 'general',
  priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
  status text not null default 'open' check(status in ('open','in_progress','waiting_customer','resolved','closed')),
  assigned_to uuid references public.developer_admins(user_id) on delete set null,
  internal_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Configuração global da plataforma. Não armazene segredos aqui.
create table if not exists public.system_settings (
  id smallint primary key default 1 check(id=1),
  app_name text not null default 'BarberAgenda',
  current_version text not null default '3.0.0',
  maintenance_mode boolean not null default false,
  allow_new_signups boolean not null default true,
  support_email text,
  announcement text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.system_settings(id) values(1) on conflict(id) do nothing;

-- Observabilidade.
create table if not exists public.app_error_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  level text not null default 'error' check(level in ('info','warning','error','fatal')),
  source text not null default 'web',
  message text not null,
  stack text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.system_incidents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  severity text not null default 'minor' check(severity in ('minor','major','critical')),
  status text not null default 'investigating' check(status in ('investigating','identified','monitoring','resolved')),
  started_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.developer_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Helpers de permissão do Admin Dev.
create or replace function public.dev_can(p_permission text)
returns boolean
language plpgsql stable security definer set search_path=public,auth as $$
declare r text;
begin
  select role into r from public.developer_admins where user_id=auth.uid() and active limit 1;
  if r is null then return false; end if;
  if r='super_admin' then return true; end if;
  if p_permission='global.read' then return true; end if;
  if r='support' and p_permission in ('support.manage','users.manage') then return true; end if;
  if r='billing' and p_permission='billing.manage' then return true; end if;
  if r='ops' and p_permission in ('businesses.manage','health.manage') then return true; end if;
  return false;
end;$$;
grant execute on function public.dev_can(text) to authenticated;

create or replace function public.dev_write_audit(p_action text,p_target_type text default null,p_target_id text default null,p_metadata jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
  insert into public.developer_audit_logs(actor_user_id,action,target_type,target_id,metadata)
  values(auth.uid(),p_action,p_target_type,p_target_id,coalesce(p_metadata,'{}'::jsonb));
end;$$;
grant execute on function public.dev_write_audit(text,text,text,jsonb) to authenticated;

-- Protege colunas exclusivas da plataforma contra owners/gerentes comuns.
create or replace function public.protect_business_platform_fields()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
  if (new.platform_status is distinct from old.platform_status
      or new.suspended_at is distinct from old.suspended_at
      or new.suspended_reason is distinct from old.suspended_reason)
     and not public.is_developer_admin() then
    raise exception 'developer_admin_required_for_platform_fields';
  end if;
  new.updated_at:=now();
  return new;
end;$$;
drop trigger if exists trg_protect_business_platform_fields on public.businesses;
create trigger trg_protect_business_platform_fields before update on public.businesses
for each row execute function public.protect_business_platform_fields();

create or replace function public.set_generic_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;

do $$ declare t text; begin
  foreach t in array array['developer_admins','subscription_plans','business_subscriptions','support_tickets','system_incidents'] loop
    execute format('drop trigger if exists trg_updated_at on public.%I',t);
    execute format('create trigger trg_updated_at before update on public.%I for each row execute function public.set_generic_updated_at()',t);
  end loop;
end $$;

-- RLS.
alter table public.developer_admins enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.business_subscriptions enable row level security;
alter table public.support_tickets enable row level security;
alter table public.system_settings enable row level security;
alter table public.app_error_logs enable row level security;
alter table public.system_incidents enable row level security;
alter table public.developer_audit_logs enable row level security;

drop policy if exists "dev_read_developer_admins" on public.developer_admins;
create policy "dev_read_developer_admins" on public.developer_admins for select using(public.is_developer_admin());
drop policy if exists "super_manage_developer_admins" on public.developer_admins;
create policy "super_manage_developer_admins" on public.developer_admins for all using(public.dev_current_role()='super_admin') with check(public.dev_current_role()='super_admin');

drop policy if exists "public_read_active_plans" on public.subscription_plans;
create policy "public_read_active_plans" on public.subscription_plans for select using(active or public.is_developer_admin());
drop policy if exists "dev_manage_plans" on public.subscription_plans;
create policy "dev_manage_plans" on public.subscription_plans for all using(public.dev_can('billing.manage')) with check(public.dev_can('billing.manage'));

drop policy if exists "members_read_subscription" on public.business_subscriptions;
create policy "members_read_subscription" on public.business_subscriptions for select using(public.is_developer_admin() or public.is_business_member(business_id));
drop policy if exists "dev_manage_subscriptions" on public.business_subscriptions;
create policy "dev_manage_subscriptions" on public.business_subscriptions for all using(public.dev_can('billing.manage')) with check(public.dev_can('billing.manage'));

drop policy if exists "ticket_members_read" on public.support_tickets;
create policy "ticket_members_read" on public.support_tickets for select using(public.is_developer_admin() or (business_id is not null and public.is_business_member(business_id)));
drop policy if exists "ticket_members_insert" on public.support_tickets;
create policy "ticket_members_insert" on public.support_tickets for insert with check(auth.uid()=created_by and business_id is not null and public.is_business_member(business_id));
drop policy if exists "dev_manage_tickets" on public.support_tickets;
create policy "dev_manage_tickets" on public.support_tickets for all using(public.dev_can('support.manage')) with check(public.dev_can('support.manage'));

drop policy if exists "public_read_system_settings" on public.system_settings;
create policy "public_read_system_settings" on public.system_settings for select using(true);
drop policy if exists "dev_manage_system_settings" on public.system_settings;
create policy "dev_manage_system_settings" on public.system_settings for update using(public.dev_can('health.manage') or public.dev_current_role()='super_admin') with check(public.dev_can('health.manage') or public.dev_current_role()='super_admin');

drop policy if exists "users_insert_error_logs" on public.app_error_logs;
create policy "users_insert_error_logs" on public.app_error_logs for insert with check(
  auth.uid() is not null and (user_id is null or user_id=auth.uid()) and (business_id is null or public.is_business_member(business_id) or public.is_developer_admin())
);
drop policy if exists "dev_read_error_logs" on public.app_error_logs;
create policy "dev_read_error_logs" on public.app_error_logs for select using(public.is_developer_admin());

drop policy if exists "public_read_incidents" on public.system_incidents;
create policy "public_read_incidents" on public.system_incidents for select using(true);
drop policy if exists "dev_manage_incidents" on public.system_incidents;
create policy "dev_manage_incidents" on public.system_incidents for all using(public.dev_can('health.manage')) with check(public.dev_can('health.manage'));

drop policy if exists "dev_read_dev_audit" on public.developer_audit_logs;
create policy "dev_read_dev_audit" on public.developer_audit_logs for select using(public.is_developer_admin());

-- Admin Dev pode ler/operar empresas/membros globalmente conforme permissão.
drop policy if exists "dev_read_all_businesses" on public.businesses;
create policy "dev_read_all_businesses" on public.businesses for select using(public.is_developer_admin());
drop policy if exists "dev_update_businesses" on public.businesses;
create policy "dev_update_businesses" on public.businesses for update using(public.dev_can('businesses.manage')) with check(public.dev_can('businesses.manage'));

drop policy if exists "dev_read_business_members" on public.business_members;
create policy "dev_read_business_members" on public.business_members for select using(public.is_developer_admin());
drop policy if exists "dev_update_business_members" on public.business_members;
create policy "dev_update_business_members" on public.business_members for update using(public.dev_can('users.manage') or public.dev_can('businesses.manage')) with check(public.dev_can('users.manage') or public.dev_can('businesses.manage'));

-- Empresas suspensas/arquivadas deixam de aparecer no agendamento público.
drop policy if exists "public_read_businesses" on public.businesses;
create policy "public_read_businesses" on public.businesses for select using(
  platform_status='active' or public.is_business_member(id) or public.is_developer_admin()
);

-- Dashboard global.
create or replace function public.dev_admin_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare result jsonb;
begin
  if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
  select jsonb_build_object(
    'businesses_total',(select count(*) from public.businesses),
    'businesses_active',(select count(*) from public.businesses where platform_status='active'),
    'businesses_suspended',(select count(*) from public.businesses where platform_status='suspended'),
    'users_total',(select count(*) from auth.users),
    'appointments_today',(select count(*) from public.appointments where appointment_date=current_date and status not in ('cancelled','no_show')),
    'appointments_month',(select count(*) from public.appointments where appointment_date>=date_trunc('month',current_date)::date and appointment_date<(date_trunc('month',current_date)+interval '1 month')::date),
    'gmv_month',(select coalesce(sum(coalesce(final_amount,0)),0) from public.appointments where status='completed' and appointment_date>=date_trunc('month',current_date)::date and appointment_date<(date_trunc('month',current_date)+interval '1 month')::date),
    'open_tickets',(select count(*) from public.support_tickets where status not in ('resolved','closed')),
    'errors_24h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '24 hours'),
    'active_incidents',(select count(*) from public.system_incidents where status<>'resolved')
  ) into result;
  return result;
end;$$;
grant execute on function public.dev_admin_dashboard() to authenticated;

-- Visão global das empresas.
create or replace function public.dev_list_businesses(p_search text default null,p_limit integer default 100,p_offset integer default 0)
returns table(
  id uuid,name text,slug text,platform_status text,created_at timestamptz,updated_at timestamptz,
  owner_email text,member_count bigint,client_count bigint,appointment_count bigint,completed_revenue numeric,
  plan_id uuid,plan_name text,subscription_status text,current_period_ends_at timestamptz,last_appointment_at timestamptz
)
language sql security definer set search_path=public,auth as $$
  select b.id,b.name,b.slug,b.platform_status,b.created_at,b.updated_at,
    (select u.email from public.business_members bm join auth.users u on u.id=bm.user_id where bm.business_id=b.id and bm.role='owner' order by bm.created_at limit 1),
    (select count(*) from public.business_members bm where bm.business_id=b.id),
    (select count(*) from public.clients c where c.business_id=b.id),
    (select count(*) from public.appointments a where a.business_id=b.id),
    (select coalesce(sum(coalesce(a.final_amount,0)),0) from public.appointments a where a.business_id=b.id and a.status='completed'),
    bs.plan_id,sp.name,bs.status,bs.current_period_ends_at,
    (select max(a.created_at) from public.appointments a where a.business_id=b.id)
  from public.businesses b
  left join public.business_subscriptions bs on bs.business_id=b.id
  left join public.subscription_plans sp on sp.id=bs.plan_id
  where public.is_developer_admin()
    and (p_search is null or trim(p_search)='' or lower(b.name) like '%'||lower(trim(p_search))||'%' or lower(b.slug) like '%'||lower(trim(p_search))||'%')
  order by b.created_at desc
  limit greatest(1,least(p_limit,500)) offset greatest(0,p_offset);
$$;
grant execute on function public.dev_list_businesses(text,integer,integer) to authenticated;

-- Usuários do Supabase Auth sem expor metadados sensíveis.
create or replace function public.dev_list_users(p_search text default null,p_limit integer default 100,p_offset integer default 0)
returns table(
  user_id uuid,email text,created_at timestamptz,last_sign_in_at timestamptz,email_confirmed_at timestamptz,banned_until timestamptz,
  business_id uuid,business_name text,business_role text,membership_active boolean
)
language sql security definer set search_path=public,auth as $$
  select u.id,u.email,u.created_at,u.last_sign_in_at,u.email_confirmed_at,u.banned_until,
    bm.business_id,b.name,bm.role,bm.active
  from auth.users u
  left join lateral (select * from public.business_members x where x.user_id=u.id order by x.created_at limit 1) bm on true
  left join public.businesses b on b.id=bm.business_id
  where public.is_developer_admin()
    and (p_search is null or trim(p_search)='' or lower(coalesce(u.email,'')) like '%'||lower(trim(p_search))||'%' or lower(coalesce(b.name,'')) like '%'||lower(trim(p_search))||'%')
  order by u.created_at desc
  limit greatest(1,least(p_limit,500)) offset greatest(0,p_offset);
$$;
grant execute on function public.dev_list_users(text,integer,integer) to authenticated;

-- Ações auditadas em empresas.
create or replace function public.dev_set_business_status(p_business_id uuid,p_status text,p_reason text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.dev_can('businesses.manage') then raise exception 'developer_permission_denied'; end if;
  if p_status not in ('active','suspended','archived') then raise exception 'invalid_business_status'; end if;
  update public.businesses set platform_status=p_status,
    suspended_at=case when p_status='suspended' then now() else null end,
    suspended_reason=case when p_status='suspended' then nullif(trim(coalesce(p_reason,'')),'') else null end
  where id=p_business_id;
  perform public.dev_write_audit('business.status_changed','business',p_business_id::text,jsonb_build_object('status',p_status,'reason',p_reason));
end;$$;
grant execute on function public.dev_set_business_status(uuid,text,text) to authenticated;

create or replace function public.dev_upsert_subscription(p_business_id uuid,p_plan_id uuid,p_status text,p_period_end timestamptz default null,p_notes text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.dev_can('billing.manage') then raise exception 'developer_permission_denied'; end if;
  if p_status not in ('trialing','active','past_due','paused','canceled') then raise exception 'invalid_subscription_status'; end if;
  insert into public.business_subscriptions(business_id,plan_id,status,current_period_ends_at,notes)
  values(p_business_id,p_plan_id,p_status,p_period_end,p_notes)
  on conflict(business_id) do update set plan_id=excluded.plan_id,status=excluded.status,current_period_ends_at=excluded.current_period_ends_at,notes=excluded.notes,updated_at=now();
  perform public.dev_write_audit('subscription.updated','business',p_business_id::text,jsonb_build_object('plan_id',p_plan_id,'status',p_status));
end;$$;
grant execute on function public.dev_upsert_subscription(uuid,uuid,text,timestamptz,text) to authenticated;

create or replace function public.dev_add_developer_admin(p_email text,p_role text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare uid uuid;
begin
  if public.dev_current_role()<>'super_admin' then raise exception 'super_admin_required'; end if;
  if p_role not in ('super_admin','support','billing','ops','read_only') then raise exception 'invalid_dev_role'; end if;
  select id into uid from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if uid is null then raise exception 'auth_user_not_found'; end if;
  insert into public.developer_admins(user_id,email,role,active) values(uid,lower(trim(p_email)),p_role,true)
  on conflict(user_id) do update set email=excluded.email,role=excluded.role,active=true,updated_at=now();
  perform public.dev_write_audit('developer_admin.added','user',uid::text,jsonb_build_object('role',p_role));
  return uid;
end;$$;
grant execute on function public.dev_add_developer_admin(text,text) to authenticated;

create or replace function public.dev_remove_developer_admin(p_user_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if public.dev_current_role()<>'super_admin' then raise exception 'super_admin_required'; end if;
  if p_user_id=auth.uid() then raise exception 'cannot_remove_yourself'; end if;
  update public.developer_admins set active=false,updated_at=now() where user_id=p_user_id;
  perform public.dev_write_audit('developer_admin.disabled','user',p_user_id::text,'{}'::jsonb);
end;$$;
grant execute on function public.dev_remove_developer_admin(uuid) to authenticated;

create or replace function public.dev_health_summary()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare result jsonb;
begin
 if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
 select jsonb_build_object(
  'errors_1h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '1 hour'),
  'errors_24h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '24 hours'),
  'warnings_24h',(select count(*) from public.app_error_logs where level='warning' and created_at>=now()-interval '24 hours'),
  'open_incidents',(select count(*) from public.system_incidents where status<>'resolved'),
  'appointments_24h',(select count(*) from public.appointments where created_at>=now()-interval '24 hours'),
  'new_users_24h',(select count(*) from auth.users where created_at>=now()-interval '24 hours'),
  'new_businesses_24h',(select count(*) from public.businesses where created_at>=now()-interval '24 hours')
 ) into result;
 return result;
end;$$;
grant execute on function public.dev_health_summary() to authenticated;

-- Realtime para operações globais.
alter table public.support_tickets replica identity full;
alter table public.app_error_logs replica identity full;
alter table public.system_incidents replica identity full;
alter table public.business_subscriptions replica identity full;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='support_tickets') then alter publication supabase_realtime add table public.support_tickets; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='app_error_logs') then alter publication supabase_realtime add table public.app_error_logs; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='system_incidents') then alter publication supabase_realtime add table public.system_incidents; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='business_subscriptions') then alter publication supabase_realtime add table public.business_subscriptions; end if;
 end if;
end $$;

-- Índices.
create index if not exists idx_support_tickets_status on public.support_tickets(status,priority,created_at desc);
create index if not exists idx_error_logs_created on public.app_error_logs(created_at desc,level);
create index if not exists idx_businesses_platform_status on public.businesses(platform_status,created_at desc);
create index if not exists idx_dev_audit_created on public.developer_audit_logs(created_at desc);

-- Compatibilidade das policies públicas que consultam helpers com auth.uid() nulo.
grant execute on function public.is_developer_admin() to anon;
grant execute on function public.is_business_member(uuid) to anon;

-- Auditoria das empresas também é legível pelo Dev Console.
drop policy if exists "dev_read_all_business_audit" on public.audit_logs;
create policy "dev_read_all_business_audit" on public.audit_logs for select using(public.is_developer_admin());
