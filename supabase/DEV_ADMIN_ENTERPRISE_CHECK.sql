-- BarberAgenda — Admin Dev Enterprise Check
-- Execute no Supabase SQL Editor para verificar a estrutura global.

select * from (values
  ('Tabela','developer_admins',to_regclass('public.developer_admins') is not null),
  ('Tabela','subscription_plans',to_regclass('public.subscription_plans') is not null),
  ('Tabela','business_subscriptions',to_regclass('public.business_subscriptions') is not null),
  ('Tabela','support_tickets',to_regclass('public.support_tickets') is not null),
  ('Tabela','system_settings',to_regclass('public.system_settings') is not null),
  ('Tabela','app_error_logs',to_regclass('public.app_error_logs') is not null),
  ('Tabela','system_incidents',to_regclass('public.system_incidents') is not null),
  ('Tabela','developer_audit_logs',to_regclass('public.developer_audit_logs') is not null),
  ('Tabela','audit_logs',to_regclass('public.audit_logs') is not null),
  ('RPC','dev_current_role()',to_regprocedure('public.dev_current_role()') is not null),
  ('RPC','dev_can(text)',to_regprocedure('public.dev_can(text)') is not null),
  ('RPC','dev_admin_dashboard()',to_regprocedure('public.dev_admin_dashboard()') is not null),
  ('RPC','dev_list_businesses(text,integer,integer)',to_regprocedure('public.dev_list_businesses(text,integer,integer)') is not null),
  ('RPC','dev_list_users(text,integer,integer)',to_regprocedure('public.dev_list_users(text,integer,integer)') is not null),
  ('RPC','dev_health_summary()',to_regprocedure('public.dev_health_summary()') is not null),
  ('RPC','dev_set_business_status(uuid,text,text)',to_regprocedure('public.dev_set_business_status(uuid,text,text)') is not null),
  ('RPC','dev_upsert_subscription(uuid,uuid,text,timestamptz,text)',to_regprocedure('public.dev_upsert_subscription(uuid,uuid,text,timestamptz,text)') is not null),
  ('RPC','dev_add_developer_admin(text,text)',to_regprocedure('public.dev_add_developer_admin(text,text)') is not null),
  ('RPC','dev_remove_developer_admin(uuid)',to_regprocedure('public.dev_remove_developer_admin(uuid)') is not null),
  ('RPC','app_schema_health()',to_regprocedure('public.app_schema_health()') is not null)
) as c(category,object_name,is_ok)
order by category,object_name;

-- Usuário atual e papel Dev (quando executado via sessão autenticada/API).
select public.dev_current_role() as current_dev_role;

notify pgrst, 'reload schema';
