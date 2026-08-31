select 'whatsapp_settings' item, case when to_regclass('public.whatsapp_settings') is not null then 'OK' else 'MISSING' end status
union all select 'whatsapp_message_queue',case when to_regclass('public.whatsapp_message_queue') is not null then 'OK' else 'MISSING' end
union all select 'whatsapp_inbound_messages',case when to_regclass('public.whatsapp_inbound_messages') is not null then 'OK' else 'MISSING' end
union all select 'whatsapp_webhook_events',case when to_regclass('public.whatsapp_webhook_events') is not null then 'OK' else 'MISSING' end
union all select 'whatsapp_set_access_token(uuid,text)',case when to_regprocedure('public.whatsapp_set_access_token(uuid,text)') is not null then 'OK' else 'MISSING' end
union all select 'whatsapp_get_access_token(uuid)',case when to_regprocedure('public.whatsapp_get_access_token(uuid)') is not null then 'OK' else 'MISSING' end
union all select 'queue_due_whatsapp_reminders()',case when to_regprocedure('public.queue_due_whatsapp_reminders()') is not null then 'OK' else 'MISSING' end
union all select 'claim_whatsapp_messages(integer)',case when to_regprocedure('public.claim_whatsapp_messages(integer)') is not null then 'OK' else 'MISSING' end;
