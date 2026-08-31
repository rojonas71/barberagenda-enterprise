-- BARBERAGENDA - PRIMEIRO ACESSO / VINCULO AUTOMATICO DO PRIMEIRO DONO
-- Execute no Supabase SQL Editor depois do schema antigo, caso ainda não tenha esta função.

create or replace function public.claim_business_if_unowned(p_slug text default 'barbearia-modelo')
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;

  -- Bloqueia a linha da empresa durante a reivindicação para evitar dois primeiros donos.
  select b.id
    into v_business_id
  from public.businesses b
  where b.slug = p_slug
  for update;

  if v_business_id is null then
    raise exception 'business_not_found';
  end if;

  -- Se o usuário já pertence à empresa, o fluxo é idempotente.
  if exists (
    select 1
    from public.business_members bm
    where bm.business_id = v_business_id
      and bm.user_id = v_user_id
  ) then
    return v_business_id;
  end if;

  -- Somente a primeira conta autenticada pode assumir uma empresa ainda sem membros.
  if exists (
    select 1
    from public.business_members bm
    where bm.business_id = v_business_id
  ) then
    raise exception 'business_already_claimed';
  end if;

  insert into public.business_members (business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  return v_business_id;
end;
$$;

revoke all on function public.claim_business_if_unowned(text) from public;
grant execute on function public.claim_business_if_unowned(text) to authenticated;
