-- BARBERAGENDA - CRUD COMPLETO
-- Execute no SQL Editor do Supabase sobre a base já existente.

-- Somente proprietário pode atualizar/excluir a empresa.
drop policy if exists "owners_update_business" on public.businesses;
create policy "owners_update_business"
on public.businesses for update
using (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = businesses.id
      and bm.user_id = auth.uid()
      and bm.role = 'owner'
  )
)
with check (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = businesses.id
      and bm.user_id = auth.uid()
      and bm.role = 'owner'
  )
);

drop policy if exists "owners_delete_business" on public.businesses;
create policy "owners_delete_business"
on public.businesses for delete
using (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = businesses.id
      and bm.user_id = auth.uid()
      and bm.role = 'owner'
  )
);

-- Membros podem excluir agendamentos da própria empresa.
drop policy if exists "members_delete_appointments" on public.appointments;
create policy "members_delete_appointments"
on public.appointments for delete
using (
  exists (
    select 1 from public.business_members bm
    where bm.business_id = appointments.business_id
      and bm.user_id = auth.uid()
  )
);

-- Realtime também nos cadastros CRUD.
alter table public.services replica identity full;
alter table public.professionals replica identity full;
alter table public.businesses replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='services') then
      alter publication supabase_realtime add table public.services;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='professionals') then
      alter publication supabase_realtime add table public.professionals;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='businesses') then
      alter publication supabase_realtime add table public.businesses;
    end if;
  end if;
end $$;
