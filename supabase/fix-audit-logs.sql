-- BARBERAGENDA - HOTFIX AUDIT_LOGS
-- Seguro para executar mais de uma vez. Não apaga dados.

create extension if not exists pgcrypto;

-- 1) Tabela principal de auditoria das empresas.
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  table_name text not null,
  record_id uuid,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_audit_logs_business_created
  on public.audit_logs (business_id, created_at desc);
create index if not exists idx_audit_logs_table_created
  on public.audit_logs (table_name, created_at desc);
create index if not exists idx_audit_logs_actor_created
  on public.audit_logs (actor_user_id, created_at desc);

alter table public.audit_logs enable row level security;

-- Usuários comuns não devem escrever ou alterar auditoria manualmente.
revoke insert, update, delete on public.audit_logs from anon, authenticated;
grant select on public.audit_logs to authenticated;

-- 2) Política da empresa: owner/manager podem consultar a própria auditoria.
drop policy if exists "admins_read_audit" on public.audit_logs;
create policy "admins_read_audit"
on public.audit_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.business_members bm
    where bm.business_id = audit_logs.business_id
      and bm.user_id = auth.uid()
      and bm.role in ('owner','manager')
  )
);

-- 3) Política global do Admin Dev, apenas se a tabela developer_admins existir.
do $$
begin
  if to_regclass('public.developer_admins') is not null then
    execute 'drop policy if exists "dev_read_all_business_audit" on public.audit_logs';
    execute $POL$
      create policy "dev_read_all_business_audit"
      on public.audit_logs
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.developer_admins da
          where da.user_id = auth.uid()
            and da.active = true
        )
      )
    $POL$;
  end if;
end $$;

-- 4) Função genérica de auditoria.
create or replace function public.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  payload jsonb;
  bid uuid;
  rid uuid;
begin
  payload := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;

  begin
    bid := nullif(payload ->> 'business_id', '')::uuid;
  exception when others then
    bid := null;
  end;

  begin
    rid := nullif(payload ->> 'id', '')::uuid;
  exception when others then
    rid := null;
  end;

  if bid is not null then
    insert into public.audit_logs (
      business_id,
      actor_user_id,
      table_name,
      record_id,
      action,
      old_data,
      new_data
    ) values (
      bid,
      auth.uid(),
      tg_table_name,
      rid,
      tg_op,
      case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
      case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
    );
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function public.write_audit_log() from public;

-- 5) Recria triggers somente nas tabelas que existem.
do $$
declare
  rec record;
  trg_name text;
begin
  for rec in
    select * from (values
      ('appointments','audit_appointments'),
      ('clients','audit_clients'),
      ('services','audit_services'),
      ('professionals','audit_professionals'),
      ('financial_transactions','audit_finance'),
      ('schedule_blocks','audit_blocks'),
      ('business_members','audit_members')
    ) as x(table_name, trigger_name)
  loop
    if to_regclass('public.' || rec.table_name) is not null then
      execute format('drop trigger if exists %I on public.%I', rec.trigger_name, rec.table_name);
      execute format(
        'create trigger %I after insert or update or delete on public.%I for each row execute function public.write_audit_log()',
        rec.trigger_name,
        rec.table_name
      );
    end if;
  end loop;
end $$;

-- 6) Recarrega o schema cache do PostgREST.
notify pgrst, 'reload schema';

-- 7) Diagnóstico final.
select
  'audit_logs' as object_name,
  case when to_regclass('public.audit_logs') is not null then 'OK' else 'MISSING' end as status
union all
select
  'write_audit_log()',
  case when to_regprocedure('public.write_audit_log()') is not null then 'OK' else 'MISSING' end
union all
select
  'developer_admins',
  case when to_regclass('public.developer_admins') is not null then 'OK' else 'OPTIONAL / MISSING' end;
