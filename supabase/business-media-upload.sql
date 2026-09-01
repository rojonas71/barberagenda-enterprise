-- BarberAgenda 4.2.0 — Logo e banner por upload
-- Execute no Supabase SQL Editor em instalações existentes.

alter table public.businesses
  add column if not exists banner_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'business-assets',
  'business-assets',
  true,
  5242880,
  array['image/png','image/jpeg','image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "business_assets_owner_insert" on storage.objects;
create policy "business_assets_owner_insert"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'business-assets'
  and exists (
    select 1
    from public.business_members bm
    where bm.user_id = (select auth.uid())
      and bm.role = 'owner'
      and coalesce(bm.active, true)
      and bm.business_id::text = (storage.foldername(name))[1]
  )
);

drop policy if exists "business_assets_owner_select" on storage.objects;
create policy "business_assets_owner_select"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'business-assets'
  and exists (
    select 1
    from public.business_members bm
    where bm.user_id = (select auth.uid())
      and bm.role = 'owner'
      and coalesce(bm.active, true)
      and bm.business_id::text = (storage.foldername(name))[1]
  )
);

drop policy if exists "business_assets_owner_update" on storage.objects;
create policy "business_assets_owner_update"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'business-assets'
  and exists (
    select 1
    from public.business_members bm
    where bm.user_id = (select auth.uid())
      and bm.role = 'owner'
      and coalesce(bm.active, true)
      and bm.business_id::text = (storage.foldername(name))[1]
  )
)
with check (
  bucket_id = 'business-assets'
  and exists (
    select 1
    from public.business_members bm
    where bm.user_id = (select auth.uid())
      and bm.role = 'owner'
      and coalesce(bm.active, true)
      and bm.business_id::text = (storage.foldername(name))[1]
  )
);

drop policy if exists "business_assets_owner_delete" on storage.objects;
create policy "business_assets_owner_delete"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'business-assets'
  and exists (
    select 1
    from public.business_members bm
    where bm.user_id = (select auth.uid())
      and bm.role = 'owner'
      and coalesce(bm.active, true)
      and bm.business_id::text = (storage.foldername(name))[1]
  )
);
