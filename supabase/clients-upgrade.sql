-- BARBERAGENDA - MODULO CLIENTES
-- Pode ser executado sobre o banco existente sem apagar agendamentos.

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text not null,
  phone_normalized text not null,
  email text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, phone_normalized)
);

create index if not exists idx_clients_business_name
on public.clients (business_id, name);

create index if not exists idx_clients_business_phone
on public.clients (business_id, phone_normalized);

alter table public.appointments
add column if not exists client_id uuid references public.clients(id) on delete set null;

create index if not exists idx_appointments_client_id
on public.appointments (client_id);

-- Cria/atualiza o cliente automaticamente antes de salvar o agendamento.
create or replace function public.ensure_appointment_client()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
  v_client_id uuid;
begin
  v_phone := regexp_replace(coalesce(new.client_phone, ''), '[^0-9]', '', 'g');

  if v_phone = '' then
    v_phone := lower(trim(new.client_phone));
  end if;

  insert into public.clients (
    business_id,
    name,
    phone,
    phone_normalized,
    updated_at
  ) values (
    new.business_id,
    trim(new.client_name),
    trim(new.client_phone),
    v_phone,
    now()
  )
  on conflict (business_id, phone_normalized)
  do update set
    name = excluded.name,
    phone = excluded.phone,
    updated_at = now()
  returning id into v_client_id;

  new.client_id := v_client_id;
  return new;
end;
$$;

drop trigger if exists trg_ensure_appointment_client on public.appointments;
create trigger trg_ensure_appointment_client
before insert or update of client_name, client_phone, business_id
on public.appointments
for each row execute function public.ensure_appointment_client();

-- Converte clientes dos agendamentos antigos.
insert into public.clients (
  business_id,
  name,
  phone,
  phone_normalized,
  created_at,
  updated_at
)
select distinct on (
  a.business_id,
  regexp_replace(a.client_phone, '[^0-9]', '', 'g')
)
  a.business_id,
  a.client_name,
  a.client_phone,
  regexp_replace(a.client_phone, '[^0-9]', '', 'g'),
  a.created_at,
  now()
from public.appointments a
where trim(a.client_phone) <> ''
order by
  a.business_id,
  regexp_replace(a.client_phone, '[^0-9]', '', 'g'),
  a.created_at desc
on conflict (business_id, phone_normalized)
do update set
  name = excluded.name,
  phone = excluded.phone,
  updated_at = now();

update public.appointments a
set client_id = c.id
from public.clients c
where a.client_id is null
  and c.business_id = a.business_id
  and c.phone_normalized = regexp_replace(a.client_phone, '[^0-9]', '', 'g');

alter table public.clients enable row level security;

drop policy if exists "members_read_clients" on public.clients;
create policy "members_read_clients"
on public.clients
for select
using (
  exists (
    select 1
    from public.business_members bm
    where bm.business_id = clients.business_id
      and bm.user_id = auth.uid()
  )
);

drop policy if exists "members_manage_clients" on public.clients;
create policy "members_manage_clients"
on public.clients
for all
using (
  exists (
    select 1
    from public.business_members bm
    where bm.business_id = clients.business_id
      and bm.user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.business_members bm
    where bm.business_id = clients.business_id
      and bm.user_id = auth.uid()
  )
);

-- Resumo do CRM. A função só retorna dados da empresa do usuário autenticado.
create or replace function public.get_clients_with_stats(p_business_id uuid)
returns table (
  id uuid,
  name text,
  phone text,
  email text,
  notes text,
  total_appointments bigint,
  completed_appointments bigint,
  cancelled_appointments bigint,
  total_spent numeric,
  last_appointment_date date,
  next_appointment_date date,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = auth.uid()
  ) then
    raise exception 'not_authorized';
  end if;

  return query
  select
    c.id,
    c.name,
    c.phone,
    c.email,
    c.notes,
    count(a.id) filter (where a.status <> 'cancelled')::bigint as total_appointments,
    count(a.id) filter (where a.status = 'completed')::bigint as completed_appointments,
    count(a.id) filter (where a.status = 'cancelled')::bigint as cancelled_appointments,
    coalesce(sum(s.price) filter (where a.status = 'completed'), 0)::numeric as total_spent,
    max(a.appointment_date) filter (
      where a.status <> 'cancelled' and a.appointment_date <= current_date
    ) as last_appointment_date,
    min(a.appointment_date) filter (
      where a.status in ('pending', 'confirmed') and a.appointment_date >= current_date
    ) as next_appointment_date,
    c.updated_at
  from public.clients c
  left join public.appointments a on a.client_id = c.id
  left join public.services s on s.id = a.service_id
  where c.business_id = p_business_id
  group by c.id
  order by c.updated_at desc, c.name asc;
end;
$$;

revoke all on function public.get_clients_with_stats(uuid) from public;
grant execute on function public.get_clients_with_stats(uuid) to authenticated;

-- Histórico individual do cliente.
create or replace function public.get_client_history(p_client_id uuid)
returns table (
  appointment_id uuid,
  appointment_date date,
  start_time time,
  status text,
  service_name text,
  service_price numeric,
  professional_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_business_id uuid;
begin
  select c.business_id into v_business_id
  from public.clients c
  where c.id = p_client_id;

  if auth.uid() is null or v_business_id is null or not exists (
    select 1
    from public.business_members bm
    where bm.business_id = v_business_id
      and bm.user_id = auth.uid()
  ) then
    raise exception 'not_authorized';
  end if;

  return query
  select
    a.id,
    a.appointment_date,
    a.start_time,
    a.status,
    s.name,
    s.price,
    p.name
  from public.appointments a
  join public.services s on s.id = a.service_id
  join public.professionals p on p.id = a.professional_id
  where a.client_id = p_client_id
  order by a.appointment_date desc, a.start_time desc;
end;
$$;

revoke all on function public.get_client_history(uuid) from public;
grant execute on function public.get_client_history(uuid) to authenticated;

-- Habilita atualização da lista de clientes via Supabase Realtime.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'clients'
     ) then
    alter publication supabase_realtime add table public.clients;
  end if;
end $$;
