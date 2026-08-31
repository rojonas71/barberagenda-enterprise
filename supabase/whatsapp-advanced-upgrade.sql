-- BARBERAGENDA PRO ADVANCED - WHATSAPP CLOUD API
-- Idempotente. Não apaga clientes/agendamentos existentes.
-- Tokens são armazenados criptografados no Supabase Vault.

create extension if not exists pgcrypto;
create extension if not exists supabase_vault with schema vault;

create table if not exists public.whatsapp_settings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null unique references public.businesses(id) on delete cascade,
  enabled boolean not null default false,
  meta_phone_number_id text,
  meta_waba_id text,
  graph_version text not null default 'v24.0',
  template_language text not null default 'pt_BR',
  confirmation_template text,
  reminder_template text,
  cancellation_template text,
  reschedule_template text,
  auto_confirmation boolean not null default true,
  auto_reminder boolean not null default true,
  reminder_minutes_before integer not null default 1440 check (reminder_minutes_before between 15 and 10080),
  auto_cancellation boolean not null default true,
  auto_reschedule boolean not null default true,
  inbound_enabled boolean not null default true,
  access_token_secret_name text,
  token_configured boolean not null default false,
  last_test_at timestamptz,
  last_test_ok boolean,
  last_test_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.whatsapp_settings add column if not exists token_configured boolean not null default false;

create table if not exists public.whatsapp_message_queue (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  client_id uuid references public.clients(id) on delete set null,
  to_phone text not null,
  kind text not null default 'transactional' check (kind in ('transactional','manual','test')),
  message_type text not null check (message_type in ('template','text')),
  template_name text,
  template_language text,
  template_components jsonb not null default '[]'::jsonb,
  text_body text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','processing','sent','delivered','read','failed','cancelled')),
  scheduled_at timestamptz not null default now(),
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  failed_at timestamptz,
  dedupe_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_whatsapp_queue_dedupe
on public.whatsapp_message_queue (business_id, dedupe_key)
where dedupe_key is not null;
create index if not exists idx_whatsapp_queue_due
on public.whatsapp_message_queue (status, scheduled_at);
create index if not exists idx_whatsapp_queue_business_created
on public.whatsapp_message_queue (business_id, created_at desc);
create index if not exists idx_whatsapp_queue_provider_id
on public.whatsapp_message_queue (provider_message_id)
where provider_message_id is not null;

create table if not exists public.whatsapp_inbound_messages (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete cascade,
  provider_message_id text not null unique,
  from_phone text not null,
  contact_name text,
  message_type text,
  text_body text,
  raw_payload jsonb not null default '{}'::jsonb,
  status text not null default 'unread' check (status in ('unread','read','archived')),
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_whatsapp_inbound_business_received
on public.whatsapp_inbound_messages (business_id, received_at desc);

create table if not exists public.whatsapp_webhook_events (
  id uuid primary key default gen_random_uuid(),
  event_key text unique,
  event_type text,
  raw_payload jsonb not null,
  processed boolean not null default false,
  processing_error text,
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists trg_whatsapp_settings_updated_at on public.whatsapp_settings;
create trigger trg_whatsapp_settings_updated_at before update on public.whatsapp_settings
for each row execute function public.set_updated_at();

drop trigger if exists trg_whatsapp_queue_updated_at on public.whatsapp_message_queue;
create trigger trg_whatsapp_queue_updated_at before update on public.whatsapp_message_queue
for each row execute function public.set_updated_at();

create or replace function public.whatsapp_normalize_phone(p_phone text)
returns text language plpgsql immutable as $$
declare v text := regexp_replace(coalesce(p_phone,''), '[^0-9]', '', 'g');
begin
  if v = '' then return ''; end if;
  -- Conveniência Brasil: telefone local com DDD recebe DDI 55.
  if length(v) in (10,11) then v := '55' || v; end if;
  return v;
end;
$$;

-- Token por empresa no Vault. Somente owner/manager pode gravar.
create or replace function public.whatsapp_set_access_token(p_business_id uuid, p_access_token text)
returns boolean
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  v_name text := 'barberagenda_whatsapp_' || p_business_id::text;
  v_secret_id uuid;
begin
  if auth.uid() is null or not public.is_business_admin(p_business_id) then
    raise exception 'permission_denied';
  end if;
  if length(trim(coalesce(p_access_token,''))) < 20 then
    raise exception 'invalid_access_token';
  end if;

  select id into v_secret_id from vault.decrypted_secrets where name=v_name limit 1;
  if v_secret_id is null then
    v_secret_id := vault.create_secret(trim(p_access_token), v_name, 'WhatsApp Cloud API token - BarberAgenda');
  else
    perform vault.update_secret(v_secret_id, trim(p_access_token), v_name, 'WhatsApp Cloud API token - BarberAgenda');
  end if;

  insert into public.whatsapp_settings (business_id, access_token_secret_name, token_configured)
  values (p_business_id, v_name, true)
  on conflict (business_id) do update set access_token_secret_name=excluded.access_token_secret_name, token_configured=true, updated_at=now();
  return true;
end;
$$;
revoke all on function public.whatsapp_set_access_token(uuid,text) from public, anon;
grant execute on function public.whatsapp_set_access_token(uuid,text) to authenticated;

-- Somente server-side/service_role lê o token desencriptado.
create or replace function public.whatsapp_get_access_token(p_business_id uuid)
returns text
language sql
security definer
set search_path = public, vault
as $$
  select ds.decrypted_secret
  from vault.decrypted_secrets ds
  where ds.name=('barberagenda_whatsapp_' || p_business_id::text)
  limit 1;
$$;
revoke all on function public.whatsapp_get_access_token(uuid) from public, anon, authenticated;
grant execute on function public.whatsapp_get_access_token(uuid) to service_role;

-- Helper para montar parâmetros posicionais de template.
create or replace function public.whatsapp_body_components(p_values text[])
returns jsonb language sql immutable as $$
select case when coalesce(array_length(p_values,1),0)=0 then '[]'::jsonb else
  jsonb_build_array(jsonb_build_object(
    'type','body',
    'parameters',(select jsonb_agg(jsonb_build_object('type','text','text',v)) from unnest(p_values) v)
  )) end;
$$;

create or replace function public.enqueue_whatsapp_for_appointment(
  p_appointment_id uuid,
  p_event text,
  p_scheduled_at timestamptz default now()
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  a record; s record; v_template text; v_key text; v_id uuid; v_components jsonb;
begin
  select ap.*, b.name business_name, sv.name service_name, pr.name professional_name,
         ws.enabled, ws.template_language, ws.confirmation_template, ws.reminder_template,
         ws.cancellation_template, ws.reschedule_template, ws.auto_confirmation, ws.auto_reminder,
         ws.auto_cancellation, ws.auto_reschedule
  into a
  from public.appointments ap
  join public.businesses b on b.id=ap.business_id
  join public.services sv on sv.id=ap.service_id
  join public.professionals pr on pr.id=ap.professional_id
  left join public.whatsapp_settings ws on ws.business_id=ap.business_id
  where ap.id=p_appointment_id;

  if a.id is null or coalesce(a.enabled,false)=false then return null; end if;

  if p_event='confirmation' then
    if not coalesce(a.auto_confirmation,false) then return null; end if;
    v_template:=a.confirmation_template;
  elsif p_event='reminder' then
    if not coalesce(a.auto_reminder,false) then return null; end if;
    v_template:=a.reminder_template;
  elsif p_event='cancellation' then
    if not coalesce(a.auto_cancellation,false) then return null; end if;
    v_template:=a.cancellation_template;
  elsif p_event='reschedule' then
    if not coalesce(a.auto_reschedule,false) then return null; end if;
    v_template:=a.reschedule_template;
  else
    raise exception 'invalid_whatsapp_event';
  end if;

  if nullif(trim(coalesce(v_template,'')),'') is null then return null; end if;

  v_key := p_event || ':' || a.id::text || ':' || to_char(a.appointment_date,'YYYYMMDD') || ':' || replace(a.start_time::text,':','');
  v_components := public.whatsapp_body_components(array[
    coalesce(a.client_name,''),
    coalesce(a.business_name,''),
    to_char(a.appointment_date,'DD/MM/YYYY'),
    to_char(a.start_time,'HH24:MI'),
    coalesce(a.service_name,''),
    coalesce(a.professional_name,'')
  ]);

  insert into public.whatsapp_message_queue(
    business_id, appointment_id, client_id, to_phone, kind, message_type,
    template_name, template_language, template_components, scheduled_at, dedupe_key,
    payload
  ) values (
    a.business_id, a.id, a.client_id, public.whatsapp_normalize_phone(a.client_phone),
    'transactional','template',v_template,coalesce(a.template_language,'pt_BR'),v_components,
    p_scheduled_at,v_key,jsonb_build_object('event',p_event)
  ) on conflict (business_id,dedupe_key) where dedupe_key is not null do nothing
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.enqueue_whatsapp_for_appointment(uuid,text,timestamptz) from public, anon, authenticated;
grant execute on function public.enqueue_whatsapp_for_appointment(uuid,text,timestamptz) to service_role;

-- Trigger transacional: confirmações/cancelamentos/reagendamentos entram na fila.
create or replace function public.whatsapp_appointment_events()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    if new.status='confirmed' then perform public.enqueue_whatsapp_for_appointment(new.id,'confirmation',now()); end if;
    return new;
  end if;

  if new.status='cancelled' and old.status is distinct from 'cancelled' then
    perform public.enqueue_whatsapp_for_appointment(new.id,'cancellation',now());
    return new;
  end if;

  if new.status='confirmed' and old.status is distinct from 'confirmed' then
    perform public.enqueue_whatsapp_for_appointment(new.id,'confirmation',now());
  elsif new.status not in ('cancelled','no_show') and (
    new.appointment_date is distinct from old.appointment_date or
    new.start_time is distinct from old.start_time or
    new.professional_id is distinct from old.professional_id or
    new.service_id is distinct from old.service_id
  ) then
    perform public.enqueue_whatsapp_for_appointment(new.id,'reschedule',now());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_whatsapp_appointment_events on public.appointments;
create trigger trg_whatsapp_appointment_events
after insert or update on public.appointments
for each row execute function public.whatsapp_appointment_events();

-- Coloca lembretes na fila. O worker chama esta função periodicamente.
create or replace function public.queue_due_whatsapp_reminders()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare r record; v_count integer:=0; v_due timestamptz;
begin
  for r in
    select a.id, a.appointment_date, a.start_time, b.timezone, ws.reminder_minutes_before
    from public.appointments a
    join public.businesses b on b.id=a.business_id
    join public.whatsapp_settings ws on ws.business_id=a.business_id
    where a.status='confirmed' and ws.enabled and ws.auto_reminder and nullif(trim(coalesce(ws.reminder_template,'')),'') is not null
      and a.appointment_date between current_date and current_date+8
  loop
    v_due := ((r.appointment_date::text || ' ' || r.start_time::text)::timestamp at time zone coalesce(r.timezone,'America/Sao_Paulo'))
             - make_interval(mins=>r.reminder_minutes_before);
    if v_due <= now() and v_due > now()-interval '10 minutes' then
      if public.enqueue_whatsapp_for_appointment(r.id,'reminder',now()) is not null then v_count:=v_count+1; end if;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.queue_due_whatsapp_reminders() from public, anon, authenticated;
grant execute on function public.queue_due_whatsapp_reminders() to service_role;

-- Claim concorrente para worker server-side.
create or replace function public.claim_whatsapp_messages(p_limit integer default 20)
returns setof public.whatsapp_message_queue
language plpgsql
security definer
set search_path=public
as $$
begin
  return query
  with picked as (
    select q.id from public.whatsapp_message_queue q
    where q.status='queued'
      and q.scheduled_at<=now()
      and q.attempts<q.max_attempts
    order by q.scheduled_at,q.created_at
    for update skip locked
    limit greatest(1,least(coalesce(p_limit,20),100))
  )
  update public.whatsapp_message_queue q
  set status='processing',attempts=q.attempts+1,updated_at=now()
  from picked p where q.id=p.id
  returning q.*;
end;
$$;
revoke all on function public.claim_whatsapp_messages(integer) from public, anon, authenticated;
grant execute on function public.claim_whatsapp_messages(integer) to service_role;

-- RLS
alter table public.whatsapp_settings enable row level security;
alter table public.whatsapp_message_queue enable row level security;
alter table public.whatsapp_inbound_messages enable row level security;
alter table public.whatsapp_webhook_events enable row level security;

drop policy if exists whatsapp_settings_read on public.whatsapp_settings;
create policy whatsapp_settings_read on public.whatsapp_settings for select
using (public.is_business_member(business_id));
drop policy if exists whatsapp_settings_manage on public.whatsapp_settings;
create policy whatsapp_settings_manage on public.whatsapp_settings for all
using (public.is_business_admin(business_id)) with check (public.is_business_admin(business_id));

drop policy if exists whatsapp_queue_read on public.whatsapp_message_queue;
create policy whatsapp_queue_read on public.whatsapp_message_queue for select
using (public.is_business_member(business_id));
drop policy if exists whatsapp_queue_update on public.whatsapp_message_queue;
create policy whatsapp_queue_update on public.whatsapp_message_queue for update
using (public.is_business_admin(business_id)) with check (public.is_business_admin(business_id));

drop policy if exists whatsapp_inbound_read on public.whatsapp_inbound_messages;
create policy whatsapp_inbound_read on public.whatsapp_inbound_messages for select
using (business_id is not null and public.is_business_member(business_id));
drop policy if exists whatsapp_inbound_update on public.whatsapp_inbound_messages;
create policy whatsapp_inbound_update on public.whatsapp_inbound_messages for update
using (business_id is not null and public.is_business_member(business_id))
with check (business_id is not null and public.is_business_member(business_id));

-- Nunca liberar webhook_events para frontend.
revoke all on public.whatsapp_webhook_events from anon, authenticated;
grant select,insert,update,delete on public.whatsapp_webhook_events to service_role;
grant select,insert,update,delete on public.whatsapp_message_queue to service_role;
grant select,insert,update,delete on public.whatsapp_inbound_messages to service_role;
grant select,insert,update,delete on public.whatsapp_settings to service_role;

-- Realtime de fila e recebidas.
alter table public.whatsapp_message_queue replica identity full;
alter table public.whatsapp_inbound_messages replica identity full;
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='whatsapp_message_queue') then
      alter publication supabase_realtime add table public.whatsapp_message_queue;
    end if;
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='whatsapp_inbound_messages') then
      alter publication supabase_realtime add table public.whatsapp_inbound_messages;
    end if;
  end if;
end $$;

notify pgrst, 'reload schema';

select 'whatsapp_settings' item, case when to_regclass('public.whatsapp_settings') is not null then 'OK' else 'MISSING' end status
union all select 'whatsapp_message_queue',case when to_regclass('public.whatsapp_message_queue') is not null then 'OK' else 'MISSING' end
union all select 'whatsapp_inbound_messages',case when to_regclass('public.whatsapp_inbound_messages') is not null then 'OK' else 'MISSING' end
union all select 'whatsapp_set_access_token(uuid,text)',case when to_regprocedure('public.whatsapp_set_access_token(uuid,text)') is not null then 'OK' else 'MISSING' end
union all select 'claim_whatsapp_messages(integer)',case when to_regprocedure('public.claim_whatsapp_messages(integer)') is not null then 'OK' else 'MISSING' end;
