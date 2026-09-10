-- BarberAgenda 4.4.0 — Agenda Offline First + Realtime
-- Execute no SQL Editor do Supabase. A aplicação continua usando publishable/anon key no frontend.

alter table public.appointments
  add column if not exists updated_at timestamptz not null default now();

alter table public.appointments drop constraint if exists appointments_status_check;
alter table public.appointments
  add constraint appointments_status_check
  check (status in ('pending','confirmed','completed','cancelled','no_show'));

create or replace function public.set_appointments_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_appointments_updated_at on public.appointments;
create trigger trg_appointments_updated_at
before insert or update on public.appointments
for each row execute function public.set_appointments_updated_at();

-- Proteção autoritativa contra conflito. Cancelados/no_show não ocupam o horário.
create or replace function public.prevent_appointment_overlap()
returns trigger
language plpgsql
as $$
begin
  if new.status in ('cancelled','no_show') then
    return new;
  end if;

  if exists (
    select 1
    from public.appointments a
    where a.business_id = new.business_id
      and a.professional_id = new.professional_id
      and a.appointment_date = new.appointment_date
      and a.status not in ('cancelled','no_show')
      and a.id <> new.id
      and new.start_time < a.end_time
      and new.end_time > a.start_time
  ) then
    raise exception 'appointments_no_overlap';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_appointment_overlap on public.appointments;
create trigger trg_prevent_appointment_overlap
before insert or update on public.appointments
for each row execute function public.prevent_appointment_overlap();

-- Realtime: não altera a schema protegida `realtime`; apenas garante publicação da tabela pública.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'appointments'
  ) then
    alter publication supabase_realtime add table public.appointments;
  end if;
end $$;

create index if not exists idx_appointments_agenda_day
  on public.appointments (business_id, appointment_date, professional_id, start_time);

create index if not exists idx_appointments_updated_at
  on public.appointments (business_id, updated_at desc);

-- Segurança: mantenha RLS habilitado e as policies existentes da instalação.
alter table public.appointments enable row level security;
