-- BARBERAGENDA - REMOCAO OPCIONAL DA INTEGRACAO WHATSAPP
-- Execute somente se voce ja instalou a versao WhatsApp Advanced.
-- Nao altera clientes, empresas, agendamentos, financeiro ou Admin Dev.

begin;

-- Remove automacoes ligadas a agendamentos.
drop trigger if exists trg_whatsapp_appointment_events on public.appointments;

drop function if exists public.whatsapp_appointment_events() cascade;
drop function if exists public.enqueue_whatsapp_for_appointment(uuid,text,timestamptz) cascade;
drop function if exists public.queue_due_whatsapp_reminders() cascade;
drop function if exists public.claim_whatsapp_messages(integer) cascade;
drop function if exists public.whatsapp_body_components(text[]) cascade;
drop function if exists public.whatsapp_get_access_token(uuid) cascade;
drop function if exists public.whatsapp_set_access_token(uuid,text) cascade;
drop function if exists public.whatsapp_normalize_phone(text) cascade;

-- Remove tabelas exclusivas da integracao.
drop table if exists public.whatsapp_webhook_events cascade;
drop table if exists public.whatsapp_inbound_messages cascade;
drop table if exists public.whatsapp_message_queue cascade;
drop table if exists public.whatsapp_settings cascade;

-- Remove job do Cron quando pg_cron estiver instalado.
do $$
declare v_job bigint;
begin
  if to_regclass('cron.job') is not null then
    select jobid into v_job from cron.job where jobname='barberagenda-whatsapp-worker' limit 1;
    if v_job is not null then
      perform cron.unschedule(v_job);
    end if;
  end if;
exception when others then
  raise notice 'Cron nao removido automaticamente: %', sqlerrm;
end $$;

-- Remove secrets exclusivos da integracao quando Vault estiver disponivel.
do $$
begin
  if to_regclass('vault.secrets') is not null then
    delete from vault.secrets
    where name like 'barberagenda_whatsapp_%'
       or name in ('barberagenda_whatsapp_worker_secret');
  end if;
exception when others then
  raise notice 'Secrets do Vault nao removidos automaticamente: %', sqlerrm;
end $$;

notify pgrst, 'reload schema';
commit;

select
  case when to_regclass('public.whatsapp_settings') is null then 'OK' else 'PRESENTE' end as whatsapp_settings,
  case when to_regclass('public.whatsapp_message_queue') is null then 'OK' else 'PRESENTE' end as whatsapp_message_queue,
  case when to_regprocedure('public.queue_due_whatsapp_reminders()') is null then 'OK' else 'PRESENTE' end as whatsapp_functions;
