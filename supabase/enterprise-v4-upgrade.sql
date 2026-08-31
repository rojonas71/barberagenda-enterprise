-- ============================================================
-- BARBERAGENDA ENTERPRISE 4.0
-- Lista de espera + estoque + politicas de agenda + diagnostico
-- Idempotente. Nao remove clientes, agendamentos ou empresas.
-- ============================================================
create extension if not exists pgcrypto;

-- Helpers mínimos para permitir aplicar este módulo mesmo em uma base parcialmente migrada.
do $$ begin
 if to_regprocedure('public.is_business_member(uuid)') is null then
  execute $f$create function public.is_business_member(p_business_id uuid) returns boolean language sql stable security definer set search_path=public as 'select exists(select 1 from public.business_members bm where bm.business_id=p_business_id and bm.user_id=auth.uid())'$f$;
 end if;
 if to_regprocedure('public.is_business_admin(uuid)') is null then
  execute $f$create function public.is_business_admin(p_business_id uuid) returns boolean language sql stable security definer set search_path=public as 'select exists(select 1 from public.business_members bm where bm.business_id=p_business_id and bm.user_id=auth.uid() and bm.role in (''owner'',''manager''))'$f$;
 end if;
 if to_regprocedure('public.is_developer_admin()') is null then
  execute $f$create function public.is_developer_admin() returns boolean language sql stable security definer set search_path=public as 'select false'$f$;
 end if;
end $$;
revoke all on function public.is_business_member(uuid) from public;
grant execute on function public.is_business_member(uuid) to authenticated;
revoke all on function public.is_business_admin(uuid) from public;
grant execute on function public.is_business_admin(uuid) to authenticated;
revoke all on function public.is_developer_admin() from public;
grant execute on function public.is_developer_admin() to authenticated;

-- Compatibilidade mínima de equipe para bases antigas.
alter table public.business_members add column if not exists active boolean not null default true;

-- Configuracoes publicas/operacionais da agenda.
alter table public.businesses add column if not exists timezone text not null default 'America/Sao_Paulo';
alter table public.businesses add column if not exists booking_advance_days integer not null default 60;
alter table public.businesses add column if not exists min_booking_notice_minutes integer not null default 60;
alter table public.businesses add column if not exists cancellation_notice_hours integer not null default 2;
alter table public.businesses add column if not exists booking_enabled boolean not null default true;
alter table public.businesses add column if not exists auto_confirm_bookings boolean not null default true;
alter table public.businesses add column if not exists allow_waitlist boolean not null default true;
alter table public.businesses add column if not exists public_booking_message text;
alter table public.businesses add column if not exists platform_status text not null default 'active';

-- Normaliza dados legados antes das constraints.
update public.businesses set booking_advance_days=60 where booking_advance_days is null or booking_advance_days<1 or booking_advance_days>365;
update public.businesses set min_booking_notice_minutes=60 where min_booking_notice_minutes is null or min_booking_notice_minutes<0 or min_booking_notice_minutes>10080;
update public.businesses set cancellation_notice_hours=2 where cancellation_notice_hours is null or cancellation_notice_hours<0 or cancellation_notice_hours>168;
update public.businesses set platform_status='active' where platform_status is null or platform_status not in ('active','suspended','archived');

do $$ begin
 if not exists(select 1 from pg_constraint where conname='businesses_booking_advance_days_v4') then alter table public.businesses add constraint businesses_booking_advance_days_v4 check(booking_advance_days between 1 and 365) not valid; end if;
 if not exists(select 1 from pg_constraint where conname='businesses_booking_notice_v4') then alter table public.businesses add constraint businesses_booking_notice_v4 check(min_booking_notice_minutes between 0 and 10080) not valid; end if;
 if not exists(select 1 from pg_constraint where conname='businesses_cancellation_notice_v4') then alter table public.businesses add constraint businesses_cancellation_notice_v4 check(cancellation_notice_hours between 0 and 168) not valid; end if;
 if not exists(select 1 from pg_constraint where conname='businesses_platform_status_v4') then alter table public.businesses add constraint businesses_platform_status_v4 check(platform_status in ('active','suspended','archived')) not valid; end if;
end $$;

-- Garante os status modernos de agendamento.
do $$ declare c record; begin
 for c in select conname from pg_constraint where conrelid='public.appointments'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%status%' loop
   execute format('alter table public.appointments drop constraint if exists %I',c.conname);
 end loop;
 if not exists(select 1 from pg_constraint where conname='appointments_status_v4') then
   alter table public.appointments add constraint appointments_status_v4 check(status in ('pending','confirmed','completed','cancelled','no_show'));
 end if;
end $$;

-- Data API: grants explícitos + leitura pública separada por papel.
-- Isso evita depender dos privilégios padrão do projeto Supabase.
grant select on table public.businesses,public.services,public.professionals to anon,authenticated;
grant insert on table public.appointments to anon,authenticated;
grant select,insert,update,delete on table public.appointments to authenticated;
grant select,insert,update,delete on table public.clients,public.client_notes to authenticated;
grant select,insert,update,delete on table public.business_members,public.services,public.professionals to authenticated;

drop policy if exists "public_read_businesses" on public.businesses;
drop policy if exists "public_read_active_businesses_v4" on public.businesses;
create policy "public_read_active_businesses_v4" on public.businesses for select to anon using(platform_status='active');
drop policy if exists "authenticated_read_businesses_v4" on public.businesses;
create policy "authenticated_read_businesses_v4" on public.businesses for select to authenticated using(platform_status='active' or public.is_business_member(id) or public.is_developer_admin());

-- LISTA DE ESPERA ------------------------------------------------------------
create table if not exists public.waitlist_entries(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  service_id uuid not null references public.services(id) on delete restrict,
  professional_id uuid references public.professionals(id) on delete set null,
  client_name text not null,
  client_phone text not null,
  desired_date date not null,
  preferred_period text not null default 'any' check(preferred_period in ('any','morning','afternoon','evening')),
  status text not null default 'waiting' check(status in ('waiting','contacted','booked','cancelled','expired')),
  notes text,
  source text not null default 'public' check(source in ('public','staff')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_waitlist_business_date on public.waitlist_entries(business_id,desired_date,status);
create index if not exists idx_waitlist_phone on public.waitlist_entries(business_id,client_phone);
alter table public.waitlist_entries enable row level security;
revoke all on table public.waitlist_entries from anon;
grant insert on table public.waitlist_entries to anon;
grant select,insert,update,delete on table public.waitlist_entries to authenticated;

drop policy if exists "public_insert_waitlist" on public.waitlist_entries;
create policy "public_insert_waitlist" on public.waitlist_entries for insert to anon,authenticated with check(
  desired_date>=current_date
  and status='waiting'
  and source='public'
  and exists(select 1 from public.businesses b where b.id=waitlist_entries.business_id and b.booking_enabled and b.allow_waitlist and b.platform_status='active')
  and exists(select 1 from public.services s where s.id=waitlist_entries.service_id and s.business_id=waitlist_entries.business_id and s.active)
  and (professional_id is null or exists(select 1 from public.professionals p where p.id=waitlist_entries.professional_id and p.business_id=waitlist_entries.business_id and p.active))
);
drop policy if exists "members_read_waitlist" on public.waitlist_entries;
create policy "members_read_waitlist" on public.waitlist_entries for select to authenticated using(public.is_business_member(business_id) or public.is_developer_admin());
drop policy if exists "members_insert_waitlist" on public.waitlist_entries;
create policy "members_insert_waitlist" on public.waitlist_entries for insert to authenticated with check(public.is_business_member(business_id));
drop policy if exists "members_update_waitlist" on public.waitlist_entries;
create policy "members_update_waitlist" on public.waitlist_entries for update to authenticated using(public.is_business_member(business_id)) with check(public.is_business_member(business_id));
drop policy if exists "admins_delete_waitlist" on public.waitlist_entries;
create policy "admins_delete_waitlist" on public.waitlist_entries for delete to authenticated using(public.is_business_admin(business_id));

-- ESTOQUE -------------------------------------------------------------------
create table if not exists public.inventory_products(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  sku text,
  unit text not null default 'un',
  stock_quantity numeric(12,2) not null default 0 check(stock_quantity>=0),
  min_stock numeric(12,2) not null default 0 check(min_stock>=0),
  cost_price numeric(12,2) not null default 0 check(cost_price>=0),
  sale_price numeric(12,2) not null default 0 check(sale_price>=0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists uq_inventory_sku_business on public.inventory_products(business_id,lower(sku)) where sku is not null and trim(sku)<>'';
create index if not exists idx_inventory_business_active on public.inventory_products(business_id,active,name);

create table if not exists public.inventory_movements(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null references public.inventory_products(id) on delete cascade,
  movement_type text not null check(movement_type in ('in','out','adjustment')),
  quantity numeric(12,2) not null check(quantity<>0),
  balance_after numeric(12,2) not null,
  reason text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists idx_inventory_movements_product on public.inventory_movements(product_id,created_at desc);

alter table public.inventory_products enable row level security;
alter table public.inventory_movements enable row level security;
revoke all on table public.inventory_products from anon;
revoke all on table public.inventory_movements from anon;
grant select,insert,update,delete on table public.inventory_products to authenticated;
grant select on table public.inventory_movements to authenticated;
drop policy if exists "members_read_inventory" on public.inventory_products;
create policy "members_read_inventory" on public.inventory_products for select to authenticated using(public.is_business_member(business_id) or public.is_developer_admin());
drop policy if exists "staff_insert_inventory" on public.inventory_products;
create policy "staff_insert_inventory" on public.inventory_products for insert to authenticated with check(public.is_business_admin(business_id) or exists(select 1 from public.business_members bm where bm.business_id=inventory_products.business_id and bm.user_id=auth.uid() and bm.active and bm.role='receptionist'));
drop policy if exists "staff_update_inventory" on public.inventory_products;
create policy "staff_update_inventory" on public.inventory_products for update to authenticated using(public.is_business_admin(business_id) or exists(select 1 from public.business_members bm where bm.business_id=inventory_products.business_id and bm.user_id=auth.uid() and bm.active and bm.role='receptionist')) with check(public.is_business_admin(business_id) or exists(select 1 from public.business_members bm where bm.business_id=inventory_products.business_id and bm.user_id=auth.uid() and bm.active and bm.role='receptionist'));
drop policy if exists "admins_delete_inventory" on public.inventory_products;
create policy "admins_delete_inventory" on public.inventory_products for delete to authenticated using(public.is_business_admin(business_id));
drop policy if exists "members_read_inventory_movements" on public.inventory_movements;
create policy "members_read_inventory_movements" on public.inventory_movements for select to authenticated using(public.is_business_member(business_id) or public.is_developer_admin());

create or replace function public.adjust_inventory_stock(p_product_id uuid,p_delta numeric,p_reason text default null)
returns numeric language plpgsql security definer set search_path=public as $$
declare v public.inventory_products%rowtype;v_new numeric;v_type text;
begin
 if p_delta=0 then raise exception 'inventory_delta_zero'; end if;
 select * into v from public.inventory_products where id=p_product_id for update;
 if v.id is null then raise exception 'inventory_product_not_found'; end if;
 if not (public.is_business_admin(v.business_id) or exists(select 1 from public.business_members bm where bm.business_id=v.business_id and bm.user_id=auth.uid() and bm.active and bm.role='receptionist')) then raise exception 'inventory_permission_denied';end if;
 v_new:=v.stock_quantity+p_delta;if v_new<0 then raise exception 'inventory_negative_stock';end if;
 update public.inventory_products set stock_quantity=v_new,updated_at=now() where id=v.id;
 v_type:=case when p_delta>0 then 'in' else 'out' end;
 insert into public.inventory_movements(business_id,product_id,movement_type,quantity,balance_after,reason) values(v.business_id,v.id,v_type,p_delta,v_new,nullif(trim(coalesce(p_reason,'')),''));
 return v_new;
end;$$;
revoke all on function public.adjust_inventory_stock(uuid,numeric,text) from public;
grant execute on function public.adjust_inventory_stock(uuid,numeric,text) to authenticated;

-- Atualizacao generica de updated_at.
create or replace function public.v4_set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now();return new;end;$$;
drop trigger if exists v4_waitlist_updated on public.waitlist_entries;create trigger v4_waitlist_updated before update on public.waitlist_entries for each row execute function public.v4_set_updated_at();
drop trigger if exists v4_inventory_updated on public.inventory_products;create trigger v4_inventory_updated before update on public.inventory_products for each row execute function public.v4_set_updated_at();

-- Auditoria dos novos modulos quando a infraestrutura estiver instalada.
do $$ begin
 if to_regprocedure('public.write_audit_log()') is not null then
   execute 'drop trigger if exists audit_waitlist on public.waitlist_entries';
   execute 'create trigger audit_waitlist after insert or update or delete on public.waitlist_entries for each row execute function public.write_audit_log()';
   execute 'drop trigger if exists audit_inventory on public.inventory_products';
   execute 'create trigger audit_inventory after insert or update or delete on public.inventory_products for each row execute function public.write_audit_log()';
 end if;
end $$;

-- DIAGNOSTICO DO SCHEMA ------------------------------------------------------
create or replace function public.app_schema_health()
returns table(category text,check_name text,status text,detail text)
language plpgsql security definer set search_path=public,pg_catalog as $$
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if not exists(select 1 from public.business_members bm where bm.user_id=auth.uid() and bm.active and bm.role in ('owner','manager')) and not public.is_developer_admin() then raise exception 'permission_denied';end if;
 return query
 with checks(category,check_name,is_ok,detail) as (values
  ('Tabela','businesses',to_regclass('public.businesses') is not null,'Cadastro de empresas'),
  ('Coluna','businesses.booking_advance_days',exists(select 1 from information_schema.columns where table_schema='public' and table_name='businesses' and column_name='booking_advance_days'),'Janela futura de agendamento'),
  ('Coluna','businesses.booking_enabled',exists(select 1 from information_schema.columns where table_schema='public' and table_name='businesses' and column_name='booking_enabled'),'Liga/desliga agenda publica'),
  ('Tabela','appointments',to_regclass('public.appointments') is not null,'Agenda'),
  ('Tabela','clients',to_regclass('public.clients') is not null,'CRM'),
  ('Tabela','business_hours',to_regclass('public.business_hours') is not null,'Horario semanal'),
  ('Tabela','professional_hours',to_regclass('public.professional_hours') is not null,'Jornada de profissionais'),
  ('Tabela','financial_transactions',to_regclass('public.financial_transactions') is not null,'Financeiro'),
  ('Tabela','audit_logs',to_regclass('public.audit_logs') is not null,'Auditoria'),
  ('Tabela','waitlist_entries',to_regclass('public.waitlist_entries') is not null,'Lista de espera'),
  ('Tabela','inventory_products',to_regclass('public.inventory_products') is not null,'Estoque'),
  ('Tabela','system_settings',to_regclass('public.system_settings') is not null,'Configuracoes globais'),
  ('Funcao','create_business_for_current_user',to_regprocedure('public.create_business_for_current_user(text,text,text,text,time,time,integer,text,numeric,integer,text)') is not null,'Onboarding'),
  ('Funcao','get_busy_ranges',to_regprocedure('public.get_busy_ranges(uuid,uuid,date)') is not null,'Disponibilidade publica'),
  ('Funcao','get_booking_day_rules',to_regprocedure('public.get_booking_day_rules(uuid,uuid,date)') is not null,'Regras da agenda'),
  ('Funcao','dev_list_businesses',to_regprocedure('public.dev_list_businesses(text,integer,integer)') is not null,'Admin Dev'),
  ('Funcao','adjust_inventory_stock',to_regprocedure('public.adjust_inventory_stock(uuid,numeric,text)') is not null,'Movimentacao de estoque')
 ) select c.category,c.check_name,case when c.is_ok then 'OK' else 'MISSING' end,c.detail from checks c order by c.category,c.check_name;
end;$$;
revoke all on function public.app_schema_health() from public;
grant execute on function public.app_schema_health() to authenticated;

-- Marca a versão global quando o Admin Dev estiver instalado.
do $$ begin
 if to_regclass('public.system_settings') is not null then
  update public.system_settings set current_version='4.0.0',updated_at=now() where id=1;
 end if;
end $$;

-- Realtime dos novos modulos.
alter table public.waitlist_entries replica identity full;
alter table public.inventory_products replica identity full;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='waitlist_entries') then alter publication supabase_realtime add table public.waitlist_entries;end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='inventory_products') then alter publication supabase_realtime add table public.inventory_products;end if;
 end if;
end $$;

notify pgrst,'reload schema';

-- Verificacao final.
select 'BarberAgenda Enterprise 4.0' as upgrade,now() as applied_at,
       to_regclass('public.waitlist_entries') is not null as waitlist_ok,
       to_regclass('public.inventory_products') is not null as inventory_ok,
       to_regprocedure('public.app_schema_health()') is not null as diagnostics_ok;
