-- ============================================================
-- BARBERAGENDA PRO ADVANCED — HOTFIX system_settings
-- Corrige: Could not find the table 'public.system_settings' in the schema cache
-- Seguro para reexecução. Não apaga dados.
-- ============================================================

begin;

-- Garante a tabela global usada por MaintenanceGate, Login e DevSettings.
create table if not exists public.system_settings (
  id smallint primary key default 1 check (id = 1),
  app_name text not null default 'BarberAgenda',
  current_version text not null default '3.0.0',
  maintenance_mode boolean not null default false,
  allow_new_signups boolean not null default true,
  support_email text,
  announcement text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Compatibilidade com bancos onde a tabela possa existir incompleta.
alter table public.system_settings add column if not exists app_name text not null default 'BarberAgenda';
alter table public.system_settings add column if not exists current_version text not null default '3.0.0';
alter table public.system_settings add column if not exists maintenance_mode boolean not null default false;
alter table public.system_settings add column if not exists allow_new_signups boolean not null default true;
alter table public.system_settings add column if not exists support_email text;
alter table public.system_settings add column if not exists announcement text;
alter table public.system_settings add column if not exists updated_by uuid references auth.users(id) on delete set null;
alter table public.system_settings add column if not exists updated_at timestamptz not null default now();

-- Garante a única linha de configuração global.
insert into public.system_settings (
  id,
  app_name,
  current_version,
  maintenance_mode,
  allow_new_signups
)
values (1, 'BarberAgenda', '3.0.0', false, true)
on conflict (id) do nothing;

-- Garante helper mínimo de função do Admin Dev caso o script completo ainda não tenha sido aplicado.
create table if not exists public.developer_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'read_only'
    check (role in ('super_admin','support','billing','ops','read_only')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.dev_current_role()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select da.role
  from public.developer_admins da
  where da.user_id = auth.uid()
    and da.active = true
  limit 1;
$$;

grant execute on function public.dev_current_role() to authenticated;

-- Segurança: leitura pública somente das flags necessárias ao app.
alter table public.system_settings enable row level security;

drop policy if exists "public_read_system_settings" on public.system_settings;
create policy "public_read_system_settings"
on public.system_settings
for select
to anon, authenticated
using (true);

-- Somente Super Admin ou Ops podem alterar configurações globais.
drop policy if exists "dev_manage_system_settings" on public.system_settings;
create policy "dev_manage_system_settings"
on public.system_settings
for update
to authenticated
using (public.dev_current_role() in ('super_admin','ops'))
with check (public.dev_current_role() in ('super_admin','ops'));

-- Grants necessários para PostgREST.
grant select on table public.system_settings to anon, authenticated;
grant update on table public.system_settings to authenticated;

-- Mantém updated_at e updated_by coerentes em updates do painel Dev.
create or replace function public.touch_system_settings()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_touch_system_settings on public.system_settings;
create trigger trg_touch_system_settings
before update on public.system_settings
for each row execute function public.touch_system_settings();

commit;

-- Força o PostgREST a recarregar tabelas/funções/policies no schema cache.
notify pgrst, 'reload schema';

-- Verificação final. Deve retornar exatamente uma linha com id = 1.
select
  id,
  app_name,
  current_version,
  maintenance_mode,
  allow_new_signups,
  support_email,
  announcement,
  updated_at
from public.system_settings
where id = 1;
