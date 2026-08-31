-- BARBERAGENDA PRO ADVANCED
-- Hotfix seguro para colunas avançadas da tabela public.businesses.
-- Pode ser executado mais de uma vez. Não apaga empresas nem dados existentes.

begin;

alter table public.businesses
  add column if not exists timezone text default 'America/Sao_Paulo',
  add column if not exists booking_advance_days integer default 60,
  add column if not exists min_booking_notice_minutes integer default 60,
  add column if not exists cancellation_notice_hours integer default 2,
  add column if not exists platform_status text default 'active';

-- Corrige possíveis NULLs de instalações antigas antes de aplicar NOT NULL.
update public.businesses set timezone = 'America/Sao_Paulo' where timezone is null or btrim(timezone) = '';
update public.businesses set booking_advance_days = 60 where booking_advance_days is null;
update public.businesses set min_booking_notice_minutes = 60 where min_booking_notice_minutes is null;
update public.businesses set cancellation_notice_hours = 2 where cancellation_notice_hours is null;
update public.businesses set platform_status = 'active' where platform_status is null or btrim(platform_status) = '';

alter table public.businesses alter column timezone set default 'America/Sao_Paulo';
alter table public.businesses alter column timezone set not null;
alter table public.businesses alter column booking_advance_days set default 60;
alter table public.businesses alter column booking_advance_days set not null;
alter table public.businesses alter column min_booking_notice_minutes set default 60;
alter table public.businesses alter column min_booking_notice_minutes set not null;
alter table public.businesses alter column cancellation_notice_hours set default 2;
alter table public.businesses alter column cancellation_notice_hours set not null;
alter table public.businesses alter column platform_status set default 'active';
alter table public.businesses alter column platform_status set not null;

-- Constraints nomeadas e idempotentes.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_booking_advance_days_check'
  ) then
    alter table public.businesses
      add constraint businesses_booking_advance_days_check
      check (booking_advance_days between 1 and 365) not valid;
    alter table public.businesses validate constraint businesses_booking_advance_days_check;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_min_booking_notice_minutes_check'
  ) then
    alter table public.businesses
      add constraint businesses_min_booking_notice_minutes_check
      check (min_booking_notice_minutes between 0 and 10080) not valid;
    alter table public.businesses validate constraint businesses_min_booking_notice_minutes_check;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_cancellation_notice_hours_check'
  ) then
    alter table public.businesses
      add constraint businesses_cancellation_notice_hours_check
      check (cancellation_notice_hours between 0 and 168) not valid;
    alter table public.businesses validate constraint businesses_cancellation_notice_hours_check;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_platform_status_check'
  ) then
    alter table public.businesses
      add constraint businesses_platform_status_check
      check (platform_status in ('active','suspended','archived')) not valid;
    alter table public.businesses validate constraint businesses_platform_status_check;
  end if;
end $$;

commit;

-- Força o PostgREST/Supabase a reler colunas e funções do schema public.
notify pgrst, 'reload schema';

-- Diagnóstico: as cinco linhas abaixo devem aparecer como OK.
select
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default,
  'OK'::text as status
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name = 'businesses'
  and c.column_name in (
    'timezone',
    'booking_advance_days',
    'min_booking_notice_minutes',
    'cancellation_notice_hours',
    'platform_status'
  )
order by c.column_name;

-- Diagnóstico adicional das RPCs usadas pela agenda avançada.
select 'get_booking_day_rules(uuid,uuid,date)' as object,
       case when to_regprocedure('public.get_booking_day_rules(uuid,uuid,date)') is null then 'MISSING' else 'OK' end as status
union all
select 'get_public_schedule_blocks(uuid,uuid,date)',
       case when to_regprocedure('public.get_public_schedule_blocks(uuid,uuid,date)') is null then 'MISSING' else 'OK' end
union all
select 'get_busy_ranges(uuid,uuid,date)',
       case when to_regprocedure('public.get_busy_ranges(uuid,uuid,date)') is null then 'MISSING' else 'OK' end;
