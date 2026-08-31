-- BARBERAGENDA - UPGRADE TEMPO REAL
-- Rode este arquivo no Supabase SQL Editor se você já executou schema.sql anteriormente.

create table if not exists public.availability_slots (
  appointment_id uuid primary key references public.appointments(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  professional_id uuid not null references public.professionals(id) on delete cascade,
  appointment_date date not null,
  start_time time not null,
  end_time time not null,
  status text not null check (status in ('pending','confirmed','completed')),
  updated_at timestamptz not null default now()
);

create index if not exists idx_availability_slots_lookup
on public.availability_slots (business_id, professional_id, appointment_date, start_time);

alter table public.availability_slots enable row level security;

drop policy if exists "public_read_availability" on public.availability_slots;
create policy "public_read_availability"
on public.availability_slots
for select
using (true);

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

  if new.status = 'cancelled' then
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

drop trigger if exists trg_sync_availability_slot on public.appointments;
create trigger trg_sync_availability_slot
after insert or update or delete on public.appointments
for each row execute function public.sync_availability_slot();

insert into public.availability_slots (
  appointment_id, business_id, professional_id, appointment_date,
  start_time, end_time, status
)
select
  id, business_id, professional_id, appointment_date,
  start_time, end_time, status
from public.appointments
where status <> 'cancelled'
on conflict (appointment_id) do update set
  business_id = excluded.business_id,
  professional_id = excluded.professional_id,
  appointment_date = excluded.appointment_date,
  start_time = excluded.start_time,
  end_time = excluded.end_time,
  status = excluded.status,
  updated_at = now();

create or replace function public.get_busy_ranges(
  p_business_id uuid,
  p_professional_id uuid,
  p_date date
)
returns table(start_time time, end_time time)
language sql
security definer
set search_path = public
as $$
  select s.start_time, s.end_time
  from public.availability_slots s
  where s.business_id = p_business_id
    and s.professional_id = p_professional_id
    and s.appointment_date = p_date
  order by s.start_time;
$$;

grant execute on function public.get_busy_ranges(uuid, uuid, date) to anon, authenticated;

alter table public.appointments replica identity full;
alter table public.availability_slots replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'appointments'
    ) then
      alter publication supabase_realtime add table public.appointments;
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'availability_slots'
    ) then
      alter publication supabase_realtime add table public.availability_slots;
    end if;
  end if;
end
$$;
