-- BARBERAGENDA - VINCULAR O ADMINISTRADOR À EMPRESA
-- 1) Primeiro crie o usuário em Supabase > Authentication > Users.
-- 2) Troque o e-mail abaixo pelo MESMO e-mail criado no Authentication.
-- 3) Execute este arquivo no SQL Editor.

insert into public.business_members (business_id, user_id, role)
select
  b.id,
  u.id,
  'owner'
from public.businesses b
join auth.users u
  on lower(u.email) = lower('SEU_EMAIL_AQUI@EXEMPLO.COM')
where b.slug = 'barbearia-modelo'
on conflict (business_id, user_id)
do update set role = excluded.role;

-- Confere se o vínculo foi criado.
select
  b.name as empresa,
  b.slug,
  u.email,
  bm.role
from public.business_members bm
join public.businesses b on b.id = bm.business_id
join auth.users u on u.id = bm.user_id
where b.slug = 'barbearia-modelo';
