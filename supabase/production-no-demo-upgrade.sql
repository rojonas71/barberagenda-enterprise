-- BARBERAGENDA — PRODUÇÃO SEM DEMO
-- Execute no Supabase SQL Editor sobre uma instalação existente.
-- Remove apenas a empresa de demonstração quando ela NÃO possui dados reais.
-- Cria o onboarding seguro para cada proprietário cadastrar a própria empresa.

-- 1) Remove o fluxo antigo que dependia de "barbearia-modelo".
drop function if exists public.claim_business_if_unowned(text);

-- 2) Limpeza segura da antiga empresa demo.
do $$
declare
  v_business_id uuid;
  v_appointments bigint := 0;
  v_clients bigint := 0;
begin
  select id into v_business_id
  from public.businesses
  where slug = 'barbearia-modelo'
  limit 1;

  if v_business_id is null then
    return;
  end if;

  select count(*) into v_appointments
  from public.appointments
  where business_id = v_business_id;

  if to_regclass('public.clients') is not null then
    execute 'select count(*) from public.clients where business_id = $1'
      into v_clients
      using v_business_id;
  end if;

  if v_appointments = 0 and v_clients = 0 then
    delete from public.businesses where id = v_business_id;
    raise notice 'Empresa de demonstração removida. A conta será direcionada ao onboarding.';
  else
    raise notice 'A empresa barbearia-modelo possui dados reais e NÃO foi removida para evitar perda de dados.';
  end if;
end
$$;

-- 3) Criação atômica da empresa real + primeiro serviço + primeiro profissional.
create or replace function public.create_business_for_current_user(
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
  v_slug text := lower(trim(p_slug));
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;

  if exists (
    select 1 from public.business_members bm
    where bm.user_id = v_user_id
  ) then
    raise exception 'user_already_has_business';
  end if;

  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'business_name_required';
  end if;

  if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(v_slug) < 3 or length(v_slug) > 60 then
    raise exception 'invalid_business_slug';
  end if;

  if exists (select 1 from public.businesses b where b.slug = v_slug) then
    raise exception 'business_slug_taken';
  end if;

  if p_opening_time >= p_closing_time then
    raise exception 'invalid_business_hours';
  end if;

  if p_slot_interval not in (15,20,30,45,60) then
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
    trim(p_name), v_slug, nullif(trim(coalesce(p_phone, '')), ''),
    nullif(trim(coalesce(p_address, '')), ''), p_opening_time, p_closing_time, p_slot_interval
  ) returning id into v_business_id;

  insert into public.business_members (business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.services (business_id, name, price, duration_minutes, active)
  values (v_business_id, trim(p_service_name), p_service_price, p_service_duration, true);

  insert into public.professionals (business_id, name, active)
  values (v_business_id, trim(p_professional_name), true);

  return v_business_id;
exception
  when unique_violation then
    raise exception 'business_slug_taken';
end;
$$;

revoke all on function public.create_business_for_current_user(text,text,text,text,time,time,integer,text,numeric,integer,text) from public;
grant execute on function public.create_business_for_current_user(text,text,text,text,time,time,integer,text,numeric,integer,text) to authenticated;
