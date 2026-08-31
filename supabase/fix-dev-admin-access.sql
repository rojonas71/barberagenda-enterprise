-- BARBERAGENDA — liberar acesso Admin Dev / Super Admin
-- Usuário: rjonashenrique32@gmail.com
-- Execute no Supabase > SQL Editor usando uma conta com acesso ao projeto.

create table if not exists public.developer_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'read_only'
    check (role in ('super_admin','support','billing','ops','read_only')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.is_developer_admin()
returns boolean
language sql
stable
security definer
set search_path=public,auth
as $$
  select exists(
    select 1
    from public.developer_admins da
    where da.user_id = auth.uid()
      and da.active = true
  );
$$;

create or replace function public.dev_current_role()
returns text
language sql
stable
security definer
set search_path=public,auth
as $$
  select da.role
  from public.developer_admins da
  where da.user_id = auth.uid()
    and da.active = true
  limit 1;
$$;

grant execute on function public.is_developer_admin() to authenticated;
grant execute on function public.dev_current_role() to authenticated;

do $$
declare
  v_user_id uuid;
  v_email text;
begin
  select id, email
    into v_user_id, v_email
  from auth.users
  where lower(email) = lower('rjonashenrique32@gmail.com')
  limit 1;

  if v_user_id is null then
    raise exception 'Usuário rjonashenrique32@gmail.com não encontrado em Authentication > Users. Crie/autentique esse usuário primeiro.';
  end if;

  insert into public.developer_admins(user_id, email, role, active)
  values(v_user_id, lower(v_email), 'super_admin', true)
  on conflict(user_id) do update
  set email = excluded.email,
      role = 'super_admin',
      active = true,
      updated_at = now();
end $$;

notify pgrst, 'reload schema';

-- Verificação final: deve retornar role = super_admin e active = true.
select
  da.user_id,
  da.email,
  da.role,
  da.active,
  da.updated_at
from public.developer_admins da
where lower(da.email) = lower('rjonashenrique32@gmail.com');
