-- BARBERAGENDA — primeiro Super Admin
-- Execute depois de dev-admin-upgrade.sql.

insert into public.developer_admins(user_id,email,role,active)
select id,lower(email),'super_admin',true
from auth.users
where lower(email)=lower('rjonashenrique32@gmail.com')
on conflict(user_id) do update
set email=excluded.email,role='super_admin',active=true,updated_at=now();

notify pgrst, 'reload schema';

select user_id,email,role,active
from public.developer_admins
where lower(email)=lower('rjonashenrique32@gmail.com');
