-- BARBERAGENDA - HOTFIX RPC DE ONBOARDING
-- Corrige PGRST202 / "Could not find the function public.create_business_for_current_user(...) in the schema cache".
-- Idempotente e seguro para bancos existentes: NAO apaga empresas, clientes ou agendamentos.

create extension if not exists pgcrypto;

-- Garante apenas as estruturas essenciais esperadas pelo onboarding.
alter table public.businesses add column if not exists opening_time time not null default '08:00';
alter table public.businesses add column if not exists closing_time time not null default '19:00';
alter table public.businesses add column if not exists slot_interval integer not null default 30;

-- Remove somente a assinatura exata usada pelo frontend para evitar uma versao quebrada/antiga.
drop function if exists public.create_business_for_current_user(
  text, text, text, text, time, time, integer, text, numeric, integer, text
);

create function public.create_business_for_current_user(
  p_name text,
  p_slug text,
  p_phone text default null,
  p_address text default null,
  p_opening_time time default '08:00',
  p_closing_time time default '19:00',
  p_slot_interval integer default 30,
  p_service_name text default null,
  p_service_price numeric default 0,
  p_service_duration integer default 30,
  p_professional_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
  v_slug text := lower(trim(coalesce(p_slug, '')));
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;

  if exists (
    select 1
    from public.business_members bm
    where bm.user_id = v_user_id
  ) then
    raise exception 'user_already_has_business';
  end if;

  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'business_name_required';
  end if;

  if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or length(v_slug) < 3
     or length(v_slug) > 60 then
    raise exception 'invalid_business_slug';
  end if;

  if exists (select 1 from public.businesses b where b.slug = v_slug) then
    raise exception 'business_slug_taken';
  end if;

  if p_opening_time is null or p_closing_time is null or p_opening_time >= p_closing_time then
    raise exception 'invalid_business_hours';
  end if;

  if p_slot_interval not in (15, 20, 30, 45, 60) then
    raise exception 'invalid_slot_interval';
  end if;

  if length(trim(coalesce(p_service_name, ''))) < 1 then
    raise exception 'service_name_required';
  end if;

  if coalesce(p_service_price, -1) < 0 or coalesce(p_service_duration, 0) <= 0 then
    raise exception 'invalid_service';
  end if;

  if length(trim(coalesce(p_professional_name, ''))) < 1 then
    raise exception 'professional_name_required';
  end if;

  insert into public.businesses (
    name, slug, phone, address, opening_time, closing_time, slot_interval
  ) values (
    trim(p_name),
    v_slug,
    nullif(trim(coalesce(p_phone, '')), ''),
    nullif(trim(coalesce(p_address, '')), ''),
    p_opening_time,
    p_closing_time,
    p_slot_interval
  )
  returning id into v_business_id;

  insert into public.business_members (business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.services (
    business_id, name, price, duration_minutes, active
  ) values (
    v_business_id, trim(p_service_name), p_service_price, p_service_duration, true
  );

  insert into public.professionals (business_id, name, active)
  values (v_business_id, trim(p_professional_name), true);

  -- Em versoes Advanced, popula a grade semanal sem tornar a tabela obrigatoria.
  if to_regclass('public.business_hours') is not null then
    execute $q$
      insert into public.business_hours (
        business_id, day_of_week, is_open, open_time, close_time
      )
      select $1, d, true, $2, $3
      from generate_series(0, 6) as d
      on conflict (business_id, day_of_week) do nothing
    $q$ using v_business_id, p_opening_time, p_closing_time;
  end if;

  return v_business_id;
exception
  when unique_violation then
    raise exception 'business_slug_taken';
end;
$$;

revoke all on function public.create_business_for_current_user(
  text, text, text, text, time, time, integer, text, numeric, integer, text
) from public;

grant execute on function public.create_business_for_current_user(
  text, text, text, text, time, time, integer, text, numeric, integer, text
) to authenticated;

-- Forca o PostgREST/Supabase API a recarregar as funcoes sem esperar o cache expirar.
notify pgrst, 'reload schema';

-- Verificacao: deve retornar uma linha com os 11 argumentos da RPC.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as returns
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_business_for_current_user';
