-- BARBERAGENDA 4.0 - diagnostico executavel diretamente no SQL Editor.
select * from (values
 ('table','businesses',to_regclass('public.businesses') is not null),
 ('column','businesses.booking_advance_days',exists(select 1 from information_schema.columns where table_schema='public' and table_name='businesses' and column_name='booking_advance_days')),
 ('column','businesses.booking_enabled',exists(select 1 from information_schema.columns where table_schema='public' and table_name='businesses' and column_name='booking_enabled')),
 ('table','appointments',to_regclass('public.appointments') is not null),
 ('table','clients',to_regclass('public.clients') is not null),
 ('table','audit_logs',to_regclass('public.audit_logs') is not null),
 ('table','system_settings',to_regclass('public.system_settings') is not null),
 ('table','waitlist_entries',to_regclass('public.waitlist_entries') is not null),
 ('table','inventory_products',to_regclass('public.inventory_products') is not null),
 ('function','create_business_for_current_user',to_regprocedure('public.create_business_for_current_user(text,text,text,text,time,time,integer,text,numeric,integer,text)') is not null),
 ('function','get_busy_ranges',to_regprocedure('public.get_busy_ranges(uuid,uuid,date)') is not null),
 ('function','get_booking_day_rules',to_regprocedure('public.get_booking_day_rules(uuid,uuid,date)') is not null),
 ('function','dev_list_businesses',to_regprocedure('public.dev_list_businesses(text,integer,integer)') is not null),
 ('function','app_schema_health',to_regprocedure('public.app_schema_health()') is not null)
) as checks(kind,object_name,is_ok)
order by is_ok asc,kind,object_name;
