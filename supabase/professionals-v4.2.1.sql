-- BarberAgenda 4.2.1 — Profissionais PRO
-- Execute no Supabase SQL Editor.

alter table public.professionals
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists specialty text;

create index if not exists professionals_business_active_name_idx
  on public.professionals (business_id, active, name);

create index if not exists professionals_business_email_idx
  on public.professionals (business_id, lower(email))
  where email is not null;

-- O upload de foto usa o bucket business-assets criado na v4.2.0.
-- As políticas existentes desse bucket já autorizam objetos sob <business_id>/...

do $$ begin
  if to_regclass('public.system_settings') is not null then
    update public.system_settings set current_version='4.2.1', updated_at=now() where id=1;
  end if;
end $$;
