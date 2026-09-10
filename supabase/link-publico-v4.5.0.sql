-- BarberAgenda 4.5.0 — Link exclusivo por empresa + QR Code + página pública
-- Execute após as migrações anteriores no SQL Editor do Supabase.
-- Não altera a schema interna `realtime`.

-- O slug é o identificador público da empresa:
-- /b/<slug>
-- Garanta unicidade para que cada empresa tenha um único endereço público.
create unique index if not exists ux_businesses_slug_public
  on public.businesses (lower(slug));

-- A página pública já consulta a empresa por slug e respeita RLS.
-- O índice acima melhora lookup por URL e impede dois slugs equivalentes
-- por diferença de maiúsculas/minúsculas.

-- Atualização automática do updated_at da empresa, caso a instalação ainda
-- não possua o trigger correspondente.
alter table public.businesses
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.set_businesses_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_businesses_updated_at on public.businesses;
create trigger trg_businesses_updated_at
before update on public.businesses
for each row execute function public.set_businesses_updated_at();

-- IMPORTANTE:
-- Se o índice falhar por slugs duplicados, corrija os duplicados antes de
-- executar novamente. Não remova o índice para permitir links ambíguos.
