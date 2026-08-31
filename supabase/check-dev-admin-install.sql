-- BARBERAGENDA — diagnóstico da instalação Admin Dev
-- Retorna OK/MISSING para os objetos principais.

select 'developer_admins' as object_name,
       case when to_regclass('public.developer_admins') is null then 'MISSING' else 'OK' end as status
union all
select 'system_settings', case when to_regclass('public.system_settings') is null then 'MISSING' else 'OK' end
union all
select 'subscription_plans', case when to_regclass('public.subscription_plans') is null then 'MISSING' else 'OK' end
union all
select 'business_subscriptions', case when to_regclass('public.business_subscriptions') is null then 'MISSING' else 'OK' end
union all
select 'support_tickets', case when to_regclass('public.support_tickets') is null then 'MISSING' else 'OK' end
union all
select 'app_error_logs', case when to_regclass('public.app_error_logs') is null then 'MISSING' else 'OK' end
union all
select 'system_incidents', case when to_regclass('public.system_incidents') is null then 'MISSING' else 'OK' end
union all
select 'developer_audit_logs', case when to_regclass('public.developer_audit_logs') is null then 'MISSING' else 'OK' end
union all
select 'audit_logs', case when to_regclass('public.audit_logs') is null then 'MISSING' else 'OK' end
union all
select 'is_developer_admin()', case when to_regprocedure('public.is_developer_admin()') is null then 'MISSING' else 'OK' end
union all
select 'dev_current_role()', case when to_regprocedure('public.dev_current_role()') is null then 'MISSING' else 'OK' end
union all
select 'dev_can(text)', case when to_regprocedure('public.dev_can(text)') is null then 'MISSING' else 'OK' end
order by object_name;
