-- BARBERAGENDA - AGENDADOR DO WORKER WHATSAPP
-- Execute depois de publicar whatsapp-worker.
-- IMPORTANTE: substitua os 3 valores CHANGE_ME antes de executar.

create extension if not exists pg_cron;
create extension if not exists pg_net;
create extension if not exists supabase_vault with schema vault;

-- Atualiza/cria um secret no Vault pelo nome.
create or replace function public._ba_put_vault_secret(p_name text,p_value text,p_description text)
returns void language plpgsql security definer set search_path=vault,public as $$
declare v_id uuid;
begin
  select id into v_id from vault.decrypted_secrets where name=p_name limit 1;
  if v_id is null then
    perform vault.create_secret(p_value,p_name,p_description);
  else
    perform vault.update_secret(v_id,p_value,p_name,p_description);
  end if;
end;$$;

select public._ba_put_vault_secret('barberagenda_project_url','https://CHANGE_ME.supabase.co','URL do projeto para Cron WhatsApp');
select public._ba_put_vault_secret('barberagenda_publishable_key','CHANGE_ME_PUBLISHABLE_KEY','Publishable key para chamar Edge Function');
select public._ba_put_vault_secret('barberagenda_whatsapp_worker_secret','CHANGE_ME_LONG_RANDOM_SECRET','Worker secret do WhatsApp');

-- Remove job anterior, se existir.
do $$ declare v_job bigint; begin
  select jobid into v_job from cron.job where jobname='barberagenda-whatsapp-worker' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
end $$;

-- A cada minuto: gera lembretes vencendo e processa até 30 mensagens.
select cron.schedule(
  'barberagenda-whatsapp-worker',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='barberagenda_project_url' limit 1) || '/functions/v1/whatsapp-worker',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'apikey',(select decrypted_secret from vault.decrypted_secrets where name='barberagenda_publishable_key' limit 1),
      'x-worker-secret',(select decrypted_secret from vault.decrypted_secrets where name='barberagenda_whatsapp_worker_secret' limit 1)
    ),
    body := jsonb_build_object('source','supabase-cron','at',now()),
    timeout_milliseconds := 15000
  );
  $$
);

-- O helper não precisa continuar exposto.
revoke all on function public._ba_put_vault_secret(text,text,text) from public,anon,authenticated;
notify pgrst,'reload schema';

select jobid,jobname,schedule,active from cron.job where jobname='barberagenda-whatsapp-worker';
