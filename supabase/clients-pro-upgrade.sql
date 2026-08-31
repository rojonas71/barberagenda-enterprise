-- BARBERAGENDA - CRM DE CLIENTES PRO
-- Atualização incremental: preserva clientes e agendamentos existentes.
-- Execute depois do schema atual / clients-upgrade.sql.

create extension if not exists pgcrypto;

-- Campos profissionais de CRM.
alter table public.clients add column if not exists birthday date;
alter table public.clients add column if not exists tags text[] not null default '{}'::text[];
alter table public.clients add column if not exists source text not null default 'agendamento_online';
alter table public.clients add column if not exists marketing_opt_in boolean not null default false;
alter table public.clients add column if not exists blocked boolean not null default false;

create index if not exists idx_clients_business_birthday
on public.clients (business_id, birthday);

create index if not exists idx_clients_business_blocked
on public.clients (business_id, blocked);

create index if not exists idx_clients_tags_gin
on public.clients using gin (tags);

-- Normaliza o telefone também para clientes cadastrados manualmente.
create or replace function public.normalize_client_record()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.name := trim(new.name);
  new.phone := trim(new.phone);
  new.phone_normalized := regexp_replace(coalesce(new.phone, ''), '[^0-9]', '', 'g');
  if new.phone_normalized = '' then
    new.phone_normalized := lower(new.phone);
  end if;
  new.email := nullif(lower(trim(coalesce(new.email, ''))), '');
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_normalize_client_record on public.clients;
create trigger trg_normalize_client_record
before insert or update of name, phone, email, birthday, tags, source, marketing_opt_in, blocked, notes
on public.clients
for each row execute function public.normalize_client_record();

-- Status "não compareceu" para alimentar o CRM.
alter table public.appointments drop constraint if exists appointments_status_check;
alter table public.appointments
  add constraint appointments_status_check
  check (status in ('pending','confirmed','completed','cancelled','no_show'));

-- No-show deixa de ocupar disponibilidade futura, assim como cancelamento.
create or replace function public.prevent_appointment_overlap()
returns trigger
language plpgsql
as $$
begin
  if new.status not in ('cancelled','no_show') and exists (
    select 1
    from public.appointments a
    where a.professional_id = new.professional_id
      and a.appointment_date = new.appointment_date
      and a.status not in ('cancelled','no_show')
      and a.id <> coalesce(new.id, gen_random_uuid())
      and new.start_time < a.end_time
      and new.end_time > a.start_time
  ) then
    raise exception 'appointments_no_overlap';
  end if;
  return new;
end;
$$;

create or replace function public.get_busy_times(
  p_business_id uuid,
  p_professional_id uuid,
  p_date date
)
returns table(start_time time)
language sql
security definer
set search_path = public
as $$
  select a.start_time
  from public.appointments a
  where a.business_id = p_business_id
    and a.professional_id = p_professional_id
    and a.appointment_date = p_date
    and a.status not in ('cancelled','no_show')
  order by a.start_time;
$$;

grant execute on function public.get_busy_times(uuid, uuid, date) to anon, authenticated;

-- O espelho público só contém horários realmente ocupados.
create or replace function public.sync_availability_slot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.availability_slots where appointment_id = old.id;
    return old;
  end if;

  if new.status in ('cancelled','no_show') then
    delete from public.availability_slots where appointment_id = new.id;
  else
    insert into public.availability_slots (
      appointment_id, business_id, professional_id, appointment_date,
      start_time, end_time, status, updated_at
    ) values (
      new.id, new.business_id, new.professional_id, new.appointment_date,
      new.start_time, new.end_time, new.status, now()
    )
    on conflict (appointment_id) do update set
      business_id = excluded.business_id,
      professional_id = excluded.professional_id,
      appointment_date = excluded.appointment_date,
      start_time = excluded.start_time,
      end_time = excluded.end_time,
      status = excluded.status,
      updated_at = now();
  end if;

  return new;
end;
$$;

delete from public.availability_slots s
using public.appointments a
where s.appointment_id = a.id
  and a.status in ('cancelled','no_show');

-- Notas internas com histórico, sem sobrescrever observações antigas.
create table if not exists public.client_notes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade,
  content text not null check (char_length(trim(content)) between 1 and 2000),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_client_notes_client_created
on public.client_notes (client_id, created_at desc);

alter table public.client_notes enable row level security;

drop policy if exists "members_read_client_notes" on public.client_notes;
create policy "members_read_client_notes"
on public.client_notes for select
using (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = client_notes.business_id
      and bm.user_id = auth.uid()
  )
);

drop policy if exists "members_insert_client_notes" on public.client_notes;
create policy "members_insert_client_notes"
on public.client_notes for insert
with check (
  created_by = auth.uid()
  and exists (
    select 1 from public.business_members bm
    where bm.business_id = client_notes.business_id
      and bm.user_id = auth.uid()
  )
  and exists (
    select 1 from public.clients c
    where c.id = client_notes.client_id
      and c.business_id = client_notes.business_id
  )
);

drop policy if exists "members_delete_client_notes" on public.client_notes;
create policy "members_delete_client_notes"
on public.client_notes for delete
using (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = client_notes.business_id
      and bm.user_id = auth.uid()
  )
);

-- A assinatura da função mudou, então removemos antes de recriar.
drop function if exists public.get_clients_with_stats(uuid);

create function public.get_clients_with_stats(p_business_id uuid)
returns table (
  id uuid,
  name text,
  phone text,
  email text,
  notes text,
  birthday date,
  tags text[],
  source text,
  marketing_opt_in boolean,
  blocked boolean,
  total_appointments bigint,
  completed_appointments bigint,
  cancelled_appointments bigint,
  no_show_appointments bigint,
  total_spent numeric,
  average_ticket numeric,
  first_appointment_date date,
  last_appointment_date date,
  next_appointment_date date,
  days_since_last integer,
  favorite_service_name text,
  favorite_professional_name text,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = auth.uid()
  ) then
    raise exception 'not_authorized';
  end if;

  return query
  with base as (
    select
      c.id,
      c.name,
      c.phone,
      c.email,
      c.notes,
      c.birthday,
      c.tags,
      c.source,
      c.marketing_opt_in,
      c.blocked,
      count(a.id) filter (where a.status <> 'cancelled')::bigint as total_appointments,
      count(a.id) filter (where a.status = 'completed')::bigint as completed_appointments,
      count(a.id) filter (where a.status = 'cancelled')::bigint as cancelled_appointments,
      count(a.id) filter (where a.status = 'no_show')::bigint as no_show_appointments,
      coalesce(sum(s.price) filter (where a.status = 'completed'), 0)::numeric as total_spent,
      coalesce(
        avg(s.price) filter (where a.status = 'completed'),
        0
      )::numeric as average_ticket,
      min(a.appointment_date) filter (where a.status <> 'cancelled') as first_appointment_date,
      max(a.appointment_date) filter (
        where a.status in ('completed','confirmed','no_show')
          and a.appointment_date <= current_date
      ) as last_appointment_date,
      min(a.appointment_date) filter (
        where a.status in ('pending','confirmed')
          and a.appointment_date >= current_date
      ) as next_appointment_date,
      c.updated_at
    from public.clients c
    left join public.appointments a on a.client_id = c.id
    left join public.services s on s.id = a.service_id
    where c.business_id = p_business_id
    group by c.id
  )
  select
    b.id,
    b.name,
    b.phone,
    b.email,
    b.notes,
    b.birthday,
    b.tags,
    b.source,
    b.marketing_opt_in,
    b.blocked,
    b.total_appointments,
    b.completed_appointments,
    b.cancelled_appointments,
    b.no_show_appointments,
    b.total_spent,
    b.average_ticket,
    b.first_appointment_date,
    b.last_appointment_date,
    b.next_appointment_date,
    case when b.last_appointment_date is null then null
      else (current_date - b.last_appointment_date)::integer
    end as days_since_last,
    (
      select s2.name
      from public.appointments a2
      join public.services s2 on s2.id = a2.service_id
      where a2.client_id = b.id and a2.status = 'completed'
      group by s2.id, s2.name
      order by count(*) desc, max(a2.appointment_date) desc
      limit 1
    ) as favorite_service_name,
    (
      select p2.name
      from public.appointments a3
      join public.professionals p2 on p2.id = a3.professional_id
      where a3.client_id = b.id and a3.status = 'completed'
      group by p2.id, p2.name
      order by count(*) desc, max(a3.appointment_date) desc
      limit 1
    ) as favorite_professional_name,
    b.updated_at
  from base b
  order by b.updated_at desc, b.name asc;
end;
$$;

revoke all on function public.get_clients_with_stats(uuid) from public;
grant execute on function public.get_clients_with_stats(uuid) to authenticated;

-- Histórico individual agora inclui observação do agendamento e fim do horário.
drop function if exists public.get_client_history(uuid);

create function public.get_client_history(p_client_id uuid)
returns table (
  appointment_id uuid,
  appointment_date date,
  start_time time,
  end_time time,
  status text,
  service_name text,
  service_price numeric,
  professional_name text,
  appointment_notes text
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
    select 1 from public.business_members bm
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
    a.end_time,
    a.status,
    s.name,
    s.price,
    p.name,
    a.notes
  from public.appointments a
  join public.services s on s.id = a.service_id
  join public.professionals p on p.id = a.professional_id
  where a.client_id = p_client_id
  order by a.appointment_date desc, a.start_time desc;
end;
$$;

revoke all on function public.get_client_history(uuid) from public;
grant execute on function public.get_client_history(uuid) to authenticated;

-- Realtime também para notas internas.
alter table public.client_notes replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'client_notes'
     ) then
    alter publication supabase_realtime add table public.client_notes;
  end if;
end $$;
