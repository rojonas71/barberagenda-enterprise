-- BARBERAGENDA MASTER PRODUCTION UPGRADE 4.0
-- Banco existente: execute inteiro no Supabase SQL Editor.

-- === 1. Advanced base ===
-- BARBERAGENDA PRO ADVANCED
-- Atualização idempotente para Dashboard, Financeiro, Agenda Avançada, Equipe, Convites e Auditoria.

create extension if not exists pgcrypto;

-- Configurações avançadas da empresa.
alter table public.businesses add column if not exists timezone text not null default 'America/Sao_Paulo';
alter table public.businesses add column if not exists booking_advance_days integer not null default 60 check (booking_advance_days between 1 and 365);
alter table public.businesses add column if not exists min_booking_notice_minutes integer not null default 60 check (min_booking_notice_minutes between 0 and 10080);
alter table public.businesses add column if not exists cancellation_notice_hours integer not null default 2 check (cancellation_notice_hours between 0 and 168);

-- Comissão padrão por profissional.
alter table public.professionals add column if not exists commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100);

-- Informações financeiras do atendimento.
alter table public.appointments add column if not exists discount_amount numeric(10,2) not null default 0 check (discount_amount >= 0);
alter table public.appointments add column if not exists final_amount numeric(10,2);
alter table public.appointments add column if not exists payment_status text not null default 'unpaid' check (payment_status in ('unpaid','paid','refunded'));
alter table public.appointments add column if not exists payment_method text;

-- Metadados dos membros para exibição e controle.
alter table public.business_members add column if not exists display_name text;
alter table public.business_members add column if not exists phone text;
alter table public.business_members add column if not exists active boolean not null default true;
alter table public.business_members add column if not exists professional_id uuid references public.professionals(id) on delete set null;
alter table public.business_members add column if not exists created_at timestamptz not null default now();

-- Helpers de RLS sem recursão.
create or replace function public.is_business_member(p_business_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.business_members bm where bm.business_id=p_business_id and bm.user_id=auth.uid() and bm.active);
$$;
create or replace function public.is_business_admin(p_business_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.business_members bm where bm.business_id=p_business_id and bm.user_id=auth.uid() and bm.active and bm.role in ('owner','manager'));
$$;
grant execute on function public.is_business_member(uuid) to authenticated;
grant execute on function public.is_business_admin(uuid) to authenticated;

create or replace function public.can_access_appointment(p_business_id uuid,p_professional_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(
   select 1 from public.business_members bm
   where bm.business_id=p_business_id and bm.user_id=auth.uid() and bm.active
     and (bm.role in ('owner','manager','receptionist') or (bm.role='professional' and bm.professional_id=p_professional_id))
 );
$$;
grant execute on function public.can_access_appointment(uuid,uuid) to authenticated;

create or replace function public.can_manage_schedule_block(p_business_id uuid,p_professional_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(
  select 1 from public.business_members bm
  where bm.business_id=p_business_id and bm.user_id=auth.uid() and bm.active
    and (bm.role in ('owner','manager','receptionist') or (bm.role='professional' and p_professional_id is not null and bm.professional_id=p_professional_id))
 );
$$;
grant execute on function public.can_manage_schedule_block(uuid,uuid) to authenticated;

-- Horário semanal da empresa.
create table if not exists public.business_hours(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  day_of_week integer not null check(day_of_week between 0 and 6),
  is_open boolean not null default true,
  open_time time not null default '08:00',
  close_time time not null default '19:00',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(business_id,day_of_week),
  check(close_time>open_time)
);

-- Jornada semanal específica do profissional.
create table if not exists public.professional_hours(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  professional_id uuid not null references public.professionals(id) on delete cascade,
  day_of_week integer not null check(day_of_week between 0 and 6),
  is_open boolean not null default true,
  open_time time not null default '08:00',
  close_time time not null default '19:00',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(professional_id,day_of_week),
  check(close_time>open_time)
);

-- Onboarding avançado: cria também a grade semanal e identifica o proprietário.
create or replace function public.create_business_for_current_user(
  p_name text,p_slug text,p_phone text default null,p_address text default null,
  p_opening_time time default '08:00',p_closing_time time default '19:00',p_slot_interval integer default 30,
  p_service_name text default null,p_service_price numeric default 0,p_service_duration integer default 30,p_professional_name text default null
) returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_user_id uuid:=auth.uid();v_business_id uuid;v_slug text:=lower(trim(p_slug));v_email text;v_professional uuid;
begin
 if v_user_id is null then raise exception 'authentication_required';end if;
 if exists(select 1 from public.business_members where user_id=v_user_id) then raise exception 'user_already_has_business';end if;
 if length(trim(coalesce(p_name,'')))<2 then raise exception 'business_name_required';end if;
 if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(v_slug)<3 or length(v_slug)>60 then raise exception 'invalid_business_slug';end if;
 if exists(select 1 from public.businesses where slug=v_slug) then raise exception 'business_slug_taken';end if;
 if p_opening_time>=p_closing_time then raise exception 'invalid_business_hours';end if;
 if p_slot_interval not in(15,20,30,45,60) then raise exception 'invalid_slot_interval';end if;
 if length(trim(coalesce(p_service_name,'')))<1 then raise exception 'service_name_required';end if;
 if coalesce(p_service_price,-1)<0 or coalesce(p_service_duration,0)<=0 then raise exception 'invalid_service';end if;
 if length(trim(coalesce(p_professional_name,'')))<1 then raise exception 'professional_name_required';end if;
 select email into v_email from auth.users where id=v_user_id;
 insert into public.businesses(name,slug,phone,address,opening_time,closing_time,slot_interval) values(trim(p_name),v_slug,nullif(trim(coalesce(p_phone,'')),''),nullif(trim(coalesce(p_address,'')),''),p_opening_time,p_closing_time,p_slot_interval) returning id into v_business_id;
 insert into public.services(business_id,name,price,duration_minutes,active) values(v_business_id,trim(p_service_name),p_service_price,p_service_duration,true);
 insert into public.professionals(business_id,name,active) values(v_business_id,trim(p_professional_name),true) returning id into v_professional;
 insert into public.business_members(business_id,user_id,role,display_name,active) values(v_business_id,v_user_id,'owner',coalesce(nullif(split_part(coalesce(v_email,''),'@',1),''),trim(p_name)),true);
 insert into public.business_hours(business_id,day_of_week,is_open,open_time,close_time) select v_business_id,d,true,p_opening_time,p_closing_time from generate_series(0,6)d;
 return v_business_id;
exception when unique_violation then raise exception 'business_slug_taken';end;$$;
revoke all on function public.create_business_for_current_user(text,text,text,text,time,time,integer,text,numeric,integer,text) from public;
grant execute on function public.create_business_for_current_user(text,text,text,text,time,time,integer,text,numeric,integer,text) to authenticated;

-- Bloqueios por empresa ou profissional: feriados, férias, almoço, compromisso etc.
create table if not exists public.schedule_blocks(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  professional_id uuid references public.professionals(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  start_time time,
  end_time time,
  reason text not null,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  check(end_date>=start_date),
  check((start_time is null and end_time is null) or (start_time is not null and end_time is not null and end_time>start_time))
);
create index if not exists idx_schedule_blocks_lookup on public.schedule_blocks(business_id,professional_id,start_date,end_date);

-- Espelho público seguro dos bloqueios: sem motivo ou dados internos.
create table if not exists public.availability_blocks(
 id uuid primary key references public.schedule_blocks(id) on delete cascade,
 business_id uuid not null references public.businesses(id) on delete cascade,
 professional_id uuid references public.professionals(id) on delete cascade,
 start_date date not null,end_date date not null,start_time time,end_time time,updated_at timestamptz not null default now()
);
create index if not exists idx_availability_blocks_lookup on public.availability_blocks(business_id,professional_id,start_date,end_date);
alter table public.availability_blocks enable row level security;
drop policy if exists "public_read_availability_blocks" on public.availability_blocks;
create policy "public_read_availability_blocks" on public.availability_blocks for select using(true);
create or replace function public.sync_availability_block() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='DELETE' then delete from public.availability_blocks where id=old.id;return old;end if;
 insert into public.availability_blocks(id,business_id,professional_id,start_date,end_date,start_time,end_time,updated_at) values(new.id,new.business_id,new.professional_id,new.start_date,new.end_date,new.start_time,new.end_time,now())
 on conflict(id) do update set business_id=excluded.business_id,professional_id=excluded.professional_id,start_date=excluded.start_date,end_date=excluded.end_date,start_time=excluded.start_time,end_time=excluded.end_time,updated_at=now();return new;
end;$$;
drop trigger if exists trg_sync_availability_block on public.schedule_blocks;
create trigger trg_sync_availability_block after insert or update or delete on public.schedule_blocks for each row execute function public.sync_availability_block();
insert into public.availability_blocks(id,business_id,professional_id,start_date,end_date,start_time,end_time) select id,business_id,professional_id,start_date,end_date,start_time,end_time from public.schedule_blocks on conflict(id) do update set business_id=excluded.business_id,professional_id=excluded.professional_id,start_date=excluded.start_date,end_date=excluded.end_date,start_time=excluded.start_time,end_time=excluded.end_time,updated_at=now();

-- Fluxo financeiro manual.
create table if not exists public.financial_transactions(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  type text not null check(type in ('income','expense')),
  category text not null default 'Operacional',
  description text not null,
  amount numeric(12,2) not null check(amount>0),
  payment_method text,
  status text not null default 'paid' check(status in ('pending','paid','cancelled')),
  transaction_date date not null default current_date,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists idx_financial_transactions_period on public.financial_transactions(business_id,transaction_date,type,status);

-- Convites para equipe por link seguro.
create table if not exists public.business_invites(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  email text not null,
  role text not null check(role in ('manager','receptionist','professional')),
  token text not null unique,
  status text not null default 'pending' check(status in ('pending','accepted','cancelled','expired')),
  expires_at timestamptz not null default (now()+interval '7 days'),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists uq_pending_invite_email_business on public.business_invites(business_id,lower(email)) where status='pending';

-- Auditoria imutável para operações importantes.
create table if not exists public.audit_logs(
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  table_name text not null,
  record_id uuid,
  action text not null check(action in ('INSERT','UPDATE','DELETE')),
  old_data jsonb,
  new_data jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_audit_logs_business_created on public.audit_logs(business_id,created_at desc);

-- RLS.
alter table public.business_hours enable row level security;
alter table public.professional_hours enable row level security;
alter table public.schedule_blocks enable row level security;
alter table public.financial_transactions enable row level security;
alter table public.business_invites enable row level security;
alter table public.audit_logs enable row level security;

-- Atualiza a leitura de membros: o próprio usuário ou administradores da empresa.
drop policy if exists "members_read_members" on public.business_members;
create policy "members_read_members" on public.business_members for select using(user_id=auth.uid() or public.is_business_admin(business_id));
drop policy if exists "admins_update_members" on public.business_members;
create policy "admins_update_members" on public.business_members for update using(public.is_business_admin(business_id)) with check(public.is_business_admin(business_id));
drop policy if exists "admins_delete_members" on public.business_members;
create policy "admins_delete_members" on public.business_members for delete using(public.is_business_admin(business_id) and role<>'owner');

-- RBAC dos cadastros: somente proprietário/gerente alteram catálogo e profissionais.
drop policy if exists "members_manage_services" on public.services;
drop policy if exists "admins_insert_services" on public.services;
drop policy if exists "admins_update_services" on public.services;
drop policy if exists "admins_delete_services" on public.services;
create policy "admins_insert_services" on public.services for insert with check(public.is_business_admin(business_id));
create policy "admins_update_services" on public.services for update using(public.is_business_admin(business_id)) with check(public.is_business_admin(business_id));
create policy "admins_delete_services" on public.services for delete using(public.is_business_admin(business_id));

drop policy if exists "members_manage_professionals" on public.professionals;
drop policy if exists "admins_insert_professionals" on public.professionals;
drop policy if exists "admins_update_professionals" on public.professionals;
drop policy if exists "admins_delete_professionals" on public.professionals;
create policy "admins_insert_professionals" on public.professionals for insert with check(public.is_business_admin(business_id));
create policy "admins_update_professionals" on public.professionals for update using(public.is_business_admin(business_id)) with check(public.is_business_admin(business_id));
create policy "admins_delete_professionals" on public.professionals for delete using(public.is_business_admin(business_id));

-- RBAC da agenda: profissional vinculado vê/edita apenas a própria agenda.
drop policy if exists "members_read_appointments" on public.appointments;
drop policy if exists "members_update_appointments" on public.appointments;
drop policy if exists "members_delete_appointments" on public.appointments;
create policy "members_read_appointments" on public.appointments for select using(public.can_access_appointment(business_id,professional_id));
create policy "members_update_appointments" on public.appointments for update using(public.can_access_appointment(business_id,professional_id)) with check(public.can_access_appointment(business_id,professional_id));
create policy "members_delete_appointments" on public.appointments for delete using(public.can_access_appointment(business_id,professional_id));

drop policy if exists "members_manage_business_hours" on public.business_hours;
drop policy if exists "members_read_business_hours" on public.business_hours;
create policy "members_manage_business_hours" on public.business_hours for all using(public.is_business_admin(business_id)) with check(public.is_business_admin(business_id));
create policy "members_read_business_hours" on public.business_hours for select using(public.is_business_member(business_id));
drop policy if exists "members_manage_professional_hours" on public.professional_hours;
drop policy if exists "members_read_professional_hours" on public.professional_hours;
create policy "members_manage_professional_hours" on public.professional_hours for all using(public.is_business_admin(business_id)) with check(public.is_business_admin(business_id));
create policy "members_read_professional_hours" on public.professional_hours for select using(public.is_business_member(business_id));
drop policy if exists "members_manage_schedule_blocks" on public.schedule_blocks;
create policy "members_manage_schedule_blocks" on public.schedule_blocks for all using(public.can_manage_schedule_block(business_id,professional_id)) with check(public.can_manage_schedule_block(business_id,professional_id));
drop policy if exists "admins_manage_finance" on public.financial_transactions;
create policy "admins_manage_finance" on public.financial_transactions for all using(public.is_business_admin(business_id)) with check(public.is_business_admin(business_id));
drop policy if exists "admins_manage_invites" on public.business_invites;
create policy "admins_manage_invites" on public.business_invites for all using(public.is_business_admin(business_id)) with check(public.is_business_admin(business_id));
drop policy if exists "admins_read_audit" on public.audit_logs;
create policy "admins_read_audit" on public.audit_logs for select using(public.is_business_admin(business_id));

-- Protege preço no agendamento público e aplica limites de antecedência.
drop policy if exists "public_insert_appointments" on public.appointments;
create policy "public_insert_appointments" on public.appointments for insert with check(
 status in ('pending','confirmed')
 and exists(
   select 1 from public.businesses b
   where b.id=appointments.business_id
     and appointment_date>=current_date
     and appointment_date<=current_date+b.booking_advance_days
     and (appointment_date+start_time)>=((now() at time zone b.timezone)+make_interval(mins=>b.min_booking_notice_minutes))
 )
 and exists(select 1 from public.services s where s.id=service_id and s.business_id=business_id and s.active)
 and exists(select 1 from public.professionals p where p.id=professional_id and p.business_id=business_id and p.active)
);

create or replace function public.secure_appointment_pricing()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_price numeric;v_is_member boolean;
begin
 select price into v_price from public.services where id=new.service_id and business_id=new.business_id;
 v_is_member:=public.is_business_member(new.business_id);
 if not coalesce(v_is_member,false) then
   new.discount_amount:=0;new.final_amount:=v_price;new.payment_status:='unpaid';new.payment_method:=null;
 else
   new.discount_amount:=greatest(0,coalesce(new.discount_amount,0));new.final_amount:=coalesce(new.final_amount,greatest(0,v_price-new.discount_amount));
 end if;
 return new;
end;$$;
drop trigger if exists trg_secure_appointment_pricing on public.appointments;
create trigger trg_secure_appointment_pricing before insert or update on public.appointments for each row execute function public.secure_appointment_pricing();

-- Protege o papel owner contra remoção/demissão acidental ou promoção indevida.
create or replace function public.protect_owner_membership()
returns trigger language plpgsql as $$
begin
 if tg_op='DELETE' and old.role='owner' then raise exception 'owner_membership_protected';end if;
 if tg_op='UPDATE' then
   if old.role='owner' and (new.role<>'owner' or new.active=false) then raise exception 'owner_membership_protected';end if;
   if old.role<>'owner' and new.role='owner' then raise exception 'owner_role_protected';end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end;$$;
drop trigger if exists trg_protect_owner_membership on public.business_members;
create trigger trg_protect_owner_membership before update or delete on public.business_members for each row execute function public.protect_owner_membership();

-- Aceite de convite: exige sessão e o mesmo e-mail do convite.
create or replace function public.accept_business_invite(p_token text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid:=auth.uid();v_email text;v_inv public.business_invites%rowtype;
begin
 if v_user is null then raise exception 'authentication_required'; end if;
 select email into v_email from auth.users where id=v_user;
 select * into v_inv from public.business_invites where token=p_token and status='pending' and expires_at>now() for update;
 if v_inv.id is null then raise exception 'invite_invalid'; end if;
 if lower(coalesce(v_email,''))<>lower(v_inv.email) then raise exception 'invite_email_mismatch'; end if;
 if exists(select 1 from public.business_members bm where bm.user_id=v_user and bm.business_id<>v_inv.business_id) then raise exception 'user_already_has_business'; end if;
 insert into public.business_members(business_id,user_id,role,display_name,active)
 values(v_inv.business_id,v_user,v_inv.role,split_part(v_email,'@',1),true)
 on conflict(business_id,user_id) do update set role=excluded.role,active=true;
 update public.business_invites set status='accepted',accepted_by=v_user,accepted_at=now() where id=v_inv.id;
 return v_inv.business_id;
end;$$;
revoke all on function public.accept_business_invite(text) from public;
grant execute on function public.accept_business_invite(text) to authenticated;

-- Regra pública de horário para o dia selecionado. Não expõe dados privados.
create or replace function public.get_booking_day_rules(p_business_id uuid,p_professional_id uuid,p_date date)
returns table(is_open boolean,open_time time,close_time time,timezone text,booking_advance_days integer,min_booking_notice_minutes integer)
language plpgsql security definer set search_path=public as $$
declare v_day integer:=extract(dow from p_date)::integer;v_b public.businesses%rowtype;v_ph public.professional_hours%rowtype;v_bh public.business_hours%rowtype;
begin
 select * into v_b from public.businesses where id=p_business_id;
 if v_b.id is null then return; end if;
 select * into v_ph from public.professional_hours where business_id=p_business_id and professional_id=p_professional_id and day_of_week=v_day limit 1;
 if v_ph.id is not null then return query select v_ph.is_open,v_ph.open_time,v_ph.close_time,v_b.timezone,v_b.booking_advance_days,v_b.min_booking_notice_minutes;return;end if;
 select * into v_bh from public.business_hours where business_id=p_business_id and day_of_week=v_day limit 1;
 if v_bh.id is not null then return query select v_bh.is_open,v_bh.open_time,v_bh.close_time,v_b.timezone,v_b.booking_advance_days,v_b.min_booking_notice_minutes;return;end if;
 return query select true,v_b.opening_time,v_b.closing_time,v_b.timezone,v_b.booking_advance_days,v_b.min_booking_notice_minutes;
end;$$;
grant execute on function public.get_booking_day_rules(uuid,uuid,date) to anon,authenticated;

create or replace function public.get_public_schedule_blocks(p_business_id uuid,p_professional_id uuid,p_date date)
returns table(start_time time,end_time time)
language sql security definer set search_path=public as $$
 select coalesce(sb.start_time,'00:00'::time),coalesce(sb.end_time,'23:59:59'::time)
 from public.availability_blocks sb
 where sb.business_id=p_business_id and p_date between sb.start_date and sb.end_date
   and (sb.professional_id is null or sb.professional_id=p_professional_id)
 order by coalesce(sb.start_time,'00:00'::time);
$$;
grant execute on function public.get_public_schedule_blocks(uuid,uuid,date) to anon,authenticated;

-- Reforça a validação do agendamento: conflito, jornada e bloqueios.
create or replace function public.prevent_appointment_overlap()
returns trigger language plpgsql as $$
declare v_open boolean;v_start time;v_end time;v_day integer:=extract(dow from new.appointment_date)::integer;
begin
 if new.status in ('cancelled','no_show') then return new; end if;
 if exists(select 1 from public.professional_hours ph where ph.business_id=new.business_id and ph.professional_id=new.professional_id and ph.day_of_week=v_day) then
   select is_open,open_time,close_time into v_open,v_start,v_end from public.professional_hours where business_id=new.business_id and professional_id=new.professional_id and day_of_week=v_day limit 1;
 elsif exists(select 1 from public.business_hours bh where bh.business_id=new.business_id and bh.day_of_week=v_day) then
   select is_open,open_time,close_time into v_open,v_start,v_end from public.business_hours where business_id=new.business_id and day_of_week=v_day limit 1;
 else
   select true,opening_time,closing_time into v_open,v_start,v_end from public.businesses where id=new.business_id;
 end if;
 if not coalesce(v_open,false) or new.start_time<v_start or new.end_time>v_end then raise exception 'appointment_outside_working_hours'; end if;
 if exists(select 1 from public.schedule_blocks sb where sb.business_id=new.business_id and new.appointment_date between sb.start_date and sb.end_date and (sb.professional_id is null or sb.professional_id=new.professional_id) and new.start_time<coalesce(sb.end_time,'23:59:59'::time) and new.end_time>coalesce(sb.start_time,'00:00'::time)) then raise exception 'appointment_schedule_blocked'; end if;
 if exists(select 1 from public.appointments a where a.professional_id=new.professional_id and a.appointment_date=new.appointment_date and a.status not in ('cancelled','no_show') and a.id<>coalesce(new.id,gen_random_uuid()) and new.start_time<a.end_time and new.end_time>a.start_time) then raise exception 'appointments_no_overlap';end if;
 return new;
end;$$;

-- Auditoria genérica.
create or replace function public.write_audit_log()
returns trigger language plpgsql security definer set search_path=public as $$
declare payload jsonb;bid uuid;rid uuid;
begin
 payload:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 bid:=nullif(payload->>'business_id','')::uuid;rid:=nullif(payload->>'id','')::uuid;
 if bid is not null then insert into public.audit_logs(business_id,actor_user_id,table_name,record_id,action,old_data,new_data) values(bid,auth.uid(),tg_table_name,rid,tg_op,case when tg_op in('UPDATE','DELETE') then to_jsonb(old) end,case when tg_op in('INSERT','UPDATE') then to_jsonb(new) end);end if;
 return case when tg_op='DELETE' then old else new end;
end;$$;

-- Cria triggers somente se ainda não existirem com os nomes abaixo.
drop trigger if exists audit_appointments on public.appointments;create trigger audit_appointments after insert or update or delete on public.appointments for each row execute function public.write_audit_log();
drop trigger if exists audit_clients on public.clients;create trigger audit_clients after insert or update or delete on public.clients for each row execute function public.write_audit_log();
drop trigger if exists audit_services on public.services;create trigger audit_services after insert or update or delete on public.services for each row execute function public.write_audit_log();
drop trigger if exists audit_professionals on public.professionals;create trigger audit_professionals after insert or update or delete on public.professionals for each row execute function public.write_audit_log();
drop trigger if exists audit_finance on public.financial_transactions;create trigger audit_finance after insert or update or delete on public.financial_transactions for each row execute function public.write_audit_log();
drop trigger if exists audit_blocks on public.schedule_blocks;create trigger audit_blocks after insert or update or delete on public.schedule_blocks for each row execute function public.write_audit_log();
drop trigger if exists audit_members on public.business_members;create trigger audit_members after insert or update or delete on public.business_members for each row execute function public.write_audit_log();

-- Melhora a identificação visual de membros já existentes.
update public.business_members bm set display_name=split_part(u.email,'@',1) from auth.users u where bm.user_id=u.id and (bm.display_name is null or trim(bm.display_name)='');

-- Backfill dos horários semanais usando configuração atual, apenas para dias ainda sem linha.
insert into public.business_hours(business_id,day_of_week,is_open,open_time,close_time)
select b.id,d,true,b.opening_time,b.closing_time from public.businesses b cross join generate_series(0,6) d
on conflict(business_id,day_of_week) do nothing;

-- Realtime.
alter table public.business_hours replica identity full;alter table public.professional_hours replica identity full;alter table public.schedule_blocks replica identity full;alter table public.availability_blocks replica identity full;alter table public.financial_transactions replica identity full;alter table public.business_invites replica identity full;
do $$ begin if exists(select 1 from pg_publication where pubname='supabase_realtime') then
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='business_hours') then alter publication supabase_realtime add table public.business_hours;end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='professional_hours') then alter publication supabase_realtime add table public.professional_hours;end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='schedule_blocks') then alter publication supabase_realtime add table public.schedule_blocks;end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='availability_blocks') then alter publication supabase_realtime add table public.availability_blocks;end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='financial_transactions') then alter publication supabase_realtime add table public.financial_transactions;end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='business_invites') then alter publication supabase_realtime add table public.business_invites;end if;
 end if;end $$;

-- === 2. Admin Dev ===
-- ============================================================
-- BARBERAGENDA PRO ADVANCED — ADMIN DEV / SUPER ADMIN
-- Execute após advanced-professional-upgrade.sql em bancos existentes.
-- Seguro para reexecução (idempotente sempre que possível).
-- ============================================================

create extension if not exists pgcrypto;

-- Estado global das empresas.
alter table public.businesses add column if not exists platform_status text not null default 'active';
alter table public.businesses add column if not exists suspended_at timestamptz;
alter table public.businesses add column if not exists suspended_reason text;
alter table public.businesses add column if not exists updated_at timestamptz not null default now();

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname='businesses_platform_status_check'
  ) then
    alter table public.businesses add constraint businesses_platform_status_check
      check (platform_status in ('active','suspended','archived'));
  end if;
end $$;

-- Administradores globais da plataforma.
create table if not exists public.developer_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'read_only' check (role in ('super_admin','support','billing','ops','read_only')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.is_developer_admin()
returns boolean
language sql stable security definer set search_path=public,auth as $$
  select exists(
    select 1 from public.developer_admins da
    where da.user_id=auth.uid() and da.active
  );
$$;

create or replace function public.dev_current_role()
returns text
language sql stable security definer set search_path=public,auth as $$
  select da.role from public.developer_admins da
  where da.user_id=auth.uid() and da.active
  limit 1;
$$;

grant execute on function public.is_developer_admin() to authenticated;
grant execute on function public.dev_current_role() to authenticated;

-- Catálogo de planos (não cria preços fictícios automaticamente).
create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  description text,
  price_monthly numeric(10,2) not null default 0 check(price_monthly>=0),
  max_professionals integer,
  max_team_members integer,
  features jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_subscriptions (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  plan_id uuid references public.subscription_plans(id) on delete set null,
  status text not null default 'trialing' check(status in ('trialing','active','past_due','paused','canceled')),
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  external_customer_id text,
  external_subscription_id text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Suporte global.
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  subject text not null,
  message text not null,
  category text not null default 'general',
  priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
  status text not null default 'open' check(status in ('open','in_progress','waiting_customer','resolved','closed')),
  assigned_to uuid references public.developer_admins(user_id) on delete set null,
  internal_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Configuração global da plataforma. Não armazene segredos aqui.
create table if not exists public.system_settings (
  id smallint primary key default 1 check(id=1),
  app_name text not null default 'BarberAgenda',
  current_version text not null default '3.0.0',
  maintenance_mode boolean not null default false,
  allow_new_signups boolean not null default true,
  support_email text,
  announcement text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.system_settings(id) values(1) on conflict(id) do nothing;

-- Observabilidade.
create table if not exists public.app_error_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  level text not null default 'error' check(level in ('info','warning','error','fatal')),
  source text not null default 'web',
  message text not null,
  stack text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.system_incidents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  severity text not null default 'minor' check(severity in ('minor','major','critical')),
  status text not null default 'investigating' check(status in ('investigating','identified','monitoring','resolved')),
  started_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.developer_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Helpers de permissão do Admin Dev.
create or replace function public.dev_can(p_permission text)
returns boolean
language plpgsql stable security definer set search_path=public,auth as $$
declare r text;
begin
  select role into r from public.developer_admins where user_id=auth.uid() and active limit 1;
  if r is null then return false; end if;
  if r='super_admin' then return true; end if;
  if p_permission='global.read' then return true; end if;
  if r='support' and p_permission in ('support.manage','users.manage') then return true; end if;
  if r='billing' and p_permission='billing.manage' then return true; end if;
  if r='ops' and p_permission in ('businesses.manage','health.manage') then return true; end if;
  return false;
end;$$;
grant execute on function public.dev_can(text) to authenticated;

create or replace function public.dev_write_audit(p_action text,p_target_type text default null,p_target_id text default null,p_metadata jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
  insert into public.developer_audit_logs(actor_user_id,action,target_type,target_id,metadata)
  values(auth.uid(),p_action,p_target_type,p_target_id,coalesce(p_metadata,'{}'::jsonb));
end;$$;
grant execute on function public.dev_write_audit(text,text,text,jsonb) to authenticated;

-- Protege colunas exclusivas da plataforma contra owners/gerentes comuns.
create or replace function public.protect_business_platform_fields()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
  if (new.platform_status is distinct from old.platform_status
      or new.suspended_at is distinct from old.suspended_at
      or new.suspended_reason is distinct from old.suspended_reason)
     and not public.is_developer_admin() then
    raise exception 'developer_admin_required_for_platform_fields';
  end if;
  new.updated_at:=now();
  return new;
end;$$;
drop trigger if exists trg_protect_business_platform_fields on public.businesses;
create trigger trg_protect_business_platform_fields before update on public.businesses
for each row execute function public.protect_business_platform_fields();

create or replace function public.set_generic_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;

do $$ declare t text; begin
  foreach t in array array['developer_admins','subscription_plans','business_subscriptions','support_tickets','system_incidents'] loop
    execute format('drop trigger if exists trg_updated_at on public.%I',t);
    execute format('create trigger trg_updated_at before update on public.%I for each row execute function public.set_generic_updated_at()',t);
  end loop;
end $$;

-- RLS.
alter table public.developer_admins enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.business_subscriptions enable row level security;
alter table public.support_tickets enable row level security;
alter table public.system_settings enable row level security;
alter table public.app_error_logs enable row level security;
alter table public.system_incidents enable row level security;
alter table public.developer_audit_logs enable row level security;

drop policy if exists "dev_read_developer_admins" on public.developer_admins;
create policy "dev_read_developer_admins" on public.developer_admins for select using(public.is_developer_admin());
drop policy if exists "super_manage_developer_admins" on public.developer_admins;
create policy "super_manage_developer_admins" on public.developer_admins for all using(public.dev_current_role()='super_admin') with check(public.dev_current_role()='super_admin');

drop policy if exists "public_read_active_plans" on public.subscription_plans;
create policy "public_read_active_plans" on public.subscription_plans for select using(active or public.is_developer_admin());
drop policy if exists "dev_manage_plans" on public.subscription_plans;
create policy "dev_manage_plans" on public.subscription_plans for all using(public.dev_can('billing.manage')) with check(public.dev_can('billing.manage'));

drop policy if exists "members_read_subscription" on public.business_subscriptions;
create policy "members_read_subscription" on public.business_subscriptions for select using(public.is_developer_admin() or public.is_business_member(business_id));
drop policy if exists "dev_manage_subscriptions" on public.business_subscriptions;
create policy "dev_manage_subscriptions" on public.business_subscriptions for all using(public.dev_can('billing.manage')) with check(public.dev_can('billing.manage'));

drop policy if exists "ticket_members_read" on public.support_tickets;
create policy "ticket_members_read" on public.support_tickets for select using(public.is_developer_admin() or (business_id is not null and public.is_business_member(business_id)));
drop policy if exists "ticket_members_insert" on public.support_tickets;
create policy "ticket_members_insert" on public.support_tickets for insert with check(auth.uid()=created_by and business_id is not null and public.is_business_member(business_id));
drop policy if exists "dev_manage_tickets" on public.support_tickets;
create policy "dev_manage_tickets" on public.support_tickets for all using(public.dev_can('support.manage')) with check(public.dev_can('support.manage'));

drop policy if exists "public_read_system_settings" on public.system_settings;
create policy "public_read_system_settings" on public.system_settings for select using(true);
drop policy if exists "dev_manage_system_settings" on public.system_settings;
create policy "dev_manage_system_settings" on public.system_settings for update using(public.dev_can('health.manage') or public.dev_current_role()='super_admin') with check(public.dev_can('health.manage') or public.dev_current_role()='super_admin');

drop policy if exists "users_insert_error_logs" on public.app_error_logs;
create policy "users_insert_error_logs" on public.app_error_logs for insert with check(
  auth.uid() is not null and (user_id is null or user_id=auth.uid()) and (business_id is null or public.is_business_member(business_id) or public.is_developer_admin())
);
drop policy if exists "dev_read_error_logs" on public.app_error_logs;
create policy "dev_read_error_logs" on public.app_error_logs for select using(public.is_developer_admin());

drop policy if exists "public_read_incidents" on public.system_incidents;
create policy "public_read_incidents" on public.system_incidents for select using(true);
drop policy if exists "dev_manage_incidents" on public.system_incidents;
create policy "dev_manage_incidents" on public.system_incidents for all using(public.dev_can('health.manage')) with check(public.dev_can('health.manage'));

drop policy if exists "dev_read_dev_audit" on public.developer_audit_logs;
create policy "dev_read_dev_audit" on public.developer_audit_logs for select using(public.is_developer_admin());

-- Admin Dev pode ler/operar empresas/membros globalmente conforme permissão.
drop policy if exists "dev_read_all_businesses" on public.businesses;
create policy "dev_read_all_businesses" on public.businesses for select using(public.is_developer_admin());
drop policy if exists "dev_update_businesses" on public.businesses;
create policy "dev_update_businesses" on public.businesses for update using(public.dev_can('businesses.manage')) with check(public.dev_can('businesses.manage'));

drop policy if exists "dev_read_business_members" on public.business_members;
create policy "dev_read_business_members" on public.business_members for select using(public.is_developer_admin());
drop policy if exists "dev_update_business_members" on public.business_members;
create policy "dev_update_business_members" on public.business_members for update using(public.dev_can('users.manage') or public.dev_can('businesses.manage')) with check(public.dev_can('users.manage') or public.dev_can('businesses.manage'));

-- Empresas suspensas/arquivadas deixam de aparecer no agendamento público.
drop policy if exists "public_read_businesses" on public.businesses;
create policy "public_read_businesses" on public.businesses for select using(
  platform_status='active' or public.is_business_member(id) or public.is_developer_admin()
);

-- Dashboard global.
create or replace function public.dev_admin_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare result jsonb;
begin
  if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
  select jsonb_build_object(
    'businesses_total',(select count(*) from public.businesses),
    'businesses_active',(select count(*) from public.businesses where platform_status='active'),
    'businesses_suspended',(select count(*) from public.businesses where platform_status='suspended'),
    'users_total',(select count(*) from auth.users),
    'appointments_today',(select count(*) from public.appointments where appointment_date=current_date and status not in ('cancelled','no_show')),
    'appointments_month',(select count(*) from public.appointments where appointment_date>=date_trunc('month',current_date)::date and appointment_date<(date_trunc('month',current_date)+interval '1 month')::date),
    'gmv_month',(select coalesce(sum(coalesce(final_amount,0)),0) from public.appointments where status='completed' and appointment_date>=date_trunc('month',current_date)::date and appointment_date<(date_trunc('month',current_date)+interval '1 month')::date),
    'open_tickets',(select count(*) from public.support_tickets where status not in ('resolved','closed')),
    'errors_24h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '24 hours'),
    'active_incidents',(select count(*) from public.system_incidents where status<>'resolved')
  ) into result;
  return result;
end;$$;
grant execute on function public.dev_admin_dashboard() to authenticated;

-- Visão global das empresas.
create or replace function public.dev_list_businesses(p_search text default null,p_limit integer default 100,p_offset integer default 0)
returns table(
  id uuid,name text,slug text,platform_status text,created_at timestamptz,updated_at timestamptz,
  owner_email text,member_count bigint,client_count bigint,appointment_count bigint,completed_revenue numeric,
  plan_id uuid,plan_name text,subscription_status text,current_period_ends_at timestamptz,last_appointment_at timestamptz
)
language sql security definer set search_path=public,auth as $$
  select b.id,b.name,b.slug,b.platform_status,b.created_at,b.updated_at,
    (select u.email from public.business_members bm join auth.users u on u.id=bm.user_id where bm.business_id=b.id and bm.role='owner' order by bm.created_at limit 1),
    (select count(*) from public.business_members bm where bm.business_id=b.id),
    (select count(*) from public.clients c where c.business_id=b.id),
    (select count(*) from public.appointments a where a.business_id=b.id),
    (select coalesce(sum(coalesce(a.final_amount,0)),0) from public.appointments a where a.business_id=b.id and a.status='completed'),
    bs.plan_id,sp.name,bs.status,bs.current_period_ends_at,
    (select max(a.created_at) from public.appointments a where a.business_id=b.id)
  from public.businesses b
  left join public.business_subscriptions bs on bs.business_id=b.id
  left join public.subscription_plans sp on sp.id=bs.plan_id
  where public.is_developer_admin()
    and (p_search is null or trim(p_search)='' or lower(b.name) like '%'||lower(trim(p_search))||'%' or lower(b.slug) like '%'||lower(trim(p_search))||'%')
  order by b.created_at desc
  limit greatest(1,least(p_limit,500)) offset greatest(0,p_offset);
$$;
grant execute on function public.dev_list_businesses(text,integer,integer) to authenticated;

-- Usuários do Supabase Auth sem expor metadados sensíveis.
create or replace function public.dev_list_users(p_search text default null,p_limit integer default 100,p_offset integer default 0)
returns table(
  user_id uuid,email text,created_at timestamptz,last_sign_in_at timestamptz,email_confirmed_at timestamptz,banned_until timestamptz,
  business_id uuid,business_name text,business_role text,membership_active boolean
)
language sql security definer set search_path=public,auth as $$
  select u.id,u.email,u.created_at,u.last_sign_in_at,u.email_confirmed_at,u.banned_until,
    bm.business_id,b.name,bm.role,bm.active
  from auth.users u
  left join lateral (select * from public.business_members x where x.user_id=u.id order by x.created_at limit 1) bm on true
  left join public.businesses b on b.id=bm.business_id
  where public.is_developer_admin()
    and (p_search is null or trim(p_search)='' or lower(coalesce(u.email,'')) like '%'||lower(trim(p_search))||'%' or lower(coalesce(b.name,'')) like '%'||lower(trim(p_search))||'%')
  order by u.created_at desc
  limit greatest(1,least(p_limit,500)) offset greatest(0,p_offset);
$$;
grant execute on function public.dev_list_users(text,integer,integer) to authenticated;

-- Ações auditadas em empresas.
create or replace function public.dev_set_business_status(p_business_id uuid,p_status text,p_reason text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.dev_can('businesses.manage') then raise exception 'developer_permission_denied'; end if;
  if p_status not in ('active','suspended','archived') then raise exception 'invalid_business_status'; end if;
  update public.businesses set platform_status=p_status,
    suspended_at=case when p_status='suspended' then now() else null end,
    suspended_reason=case when p_status='suspended' then nullif(trim(coalesce(p_reason,'')),'') else null end
  where id=p_business_id;
  perform public.dev_write_audit('business.status_changed','business',p_business_id::text,jsonb_build_object('status',p_status,'reason',p_reason));
end;$$;
grant execute on function public.dev_set_business_status(uuid,text,text) to authenticated;

create or replace function public.dev_upsert_subscription(p_business_id uuid,p_plan_id uuid,p_status text,p_period_end timestamptz default null,p_notes text default null)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.dev_can('billing.manage') then raise exception 'developer_permission_denied'; end if;
  if p_status not in ('trialing','active','past_due','paused','canceled') then raise exception 'invalid_subscription_status'; end if;
  insert into public.business_subscriptions(business_id,plan_id,status,current_period_ends_at,notes)
  values(p_business_id,p_plan_id,p_status,p_period_end,p_notes)
  on conflict(business_id) do update set plan_id=excluded.plan_id,status=excluded.status,current_period_ends_at=excluded.current_period_ends_at,notes=excluded.notes,updated_at=now();
  perform public.dev_write_audit('subscription.updated','business',p_business_id::text,jsonb_build_object('plan_id',p_plan_id,'status',p_status));
end;$$;
grant execute on function public.dev_upsert_subscription(uuid,uuid,text,timestamptz,text) to authenticated;

create or replace function public.dev_add_developer_admin(p_email text,p_role text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare uid uuid;
begin
  if public.dev_current_role()<>'super_admin' then raise exception 'super_admin_required'; end if;
  if p_role not in ('super_admin','support','billing','ops','read_only') then raise exception 'invalid_dev_role'; end if;
  select id into uid from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if uid is null then raise exception 'auth_user_not_found'; end if;
  insert into public.developer_admins(user_id,email,role,active) values(uid,lower(trim(p_email)),p_role,true)
  on conflict(user_id) do update set email=excluded.email,role=excluded.role,active=true,updated_at=now();
  perform public.dev_write_audit('developer_admin.added','user',uid::text,jsonb_build_object('role',p_role));
  return uid;
end;$$;
grant execute on function public.dev_add_developer_admin(text,text) to authenticated;

create or replace function public.dev_remove_developer_admin(p_user_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if public.dev_current_role()<>'super_admin' then raise exception 'super_admin_required'; end if;
  if p_user_id=auth.uid() then raise exception 'cannot_remove_yourself'; end if;
  update public.developer_admins set active=false,updated_at=now() where user_id=p_user_id;
  perform public.dev_write_audit('developer_admin.disabled','user',p_user_id::text,'{}'::jsonb);
end;$$;
grant execute on function public.dev_remove_developer_admin(uuid) to authenticated;

create or replace function public.dev_health_summary()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare result jsonb;
begin
 if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
 select jsonb_build_object(
  'errors_1h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '1 hour'),
  'errors_24h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '24 hours'),
  'warnings_24h',(select count(*) from public.app_error_logs where level='warning' and created_at>=now()-interval '24 hours'),
  'open_incidents',(select count(*) from public.system_incidents where status<>'resolved'),
  'appointments_24h',(select count(*) from public.appointments where created_at>=now()-interval '24 hours'),
  'new_users_24h',(select count(*) from auth.users where created_at>=now()-interval '24 hours'),
  'new_businesses_24h',(select count(*) from public.businesses where created_at>=now()-interval '24 hours')
 ) into result;
 return result;
end;$$;
grant execute on function public.dev_health_summary() to authenticated;

-- Realtime para operações globais.
alter table public.support_tickets replica identity full;
alter table public.app_error_logs replica identity full;
alter table public.system_incidents replica identity full;
alter table public.business_subscriptions replica identity full;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='support_tickets') then alter publication supabase_realtime add table public.support_tickets; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='app_error_logs') then alter publication supabase_realtime add table public.app_error_logs; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='system_incidents') then alter publication supabase_realtime add table public.system_incidents; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='business_subscriptions') then alter publication supabase_realtime add table public.business_subscriptions; end if;
 end if;
end $$;

-- Índices.
create index if not exists idx_support_tickets_status on public.support_tickets(status,priority,created_at desc);
create index if not exists idx_error_logs_created on public.app_error_logs(created_at desc,level);
create index if not exists idx_businesses_platform_status on public.businesses(platform_status,created_at desc);
create index if not exists idx_dev_audit_created on public.developer_audit_logs(created_at desc);

-- Compatibilidade das policies públicas que consultam helpers com auth.uid() nulo.
grant execute on function public.is_developer_admin() to anon;
grant execute on function public.is_business_member(uuid) to anon;

-- Auditoria das empresas também é legível pelo Dev Console.
drop policy if exists "dev_read_all_business_audit" on public.audit_logs;
create policy "dev_read_all_business_audit" on public.audit_logs for select using(public.is_developer_admin());

-- === 3. Onboarding RPC repair ===
-- BARBERAGENDA - HOTFIX RPC DE ONBOARDING
-- Corrige PGRST202 / "Could not find the function public.create_business_for_current_user(...) in the schema cache".
-- Idempotente e seguro para bancos existentes: NAO apaga empresas, clientes ou agendamentos.

create extension if not exists pgcrypto;

-- Garante apenas as estruturas essenciais esperadas pelo onboarding.
alter table public.businesses add column if not exists opening_time time not null default '08:00';
alter table public.businesses add column if not exists closing_time time not null default '19:00';
alter table public.businesses add column if not exists slot_interval integer not null default 30;

-- Remove somente a assinatura exata usada pelo frontend para evitar uma versao quebrada/antiga.
drop function if exists public.create_business_for_current_user(
  text, text, text, text, time, time, integer, text, numeric, integer, text
);

create function public.create_business_for_current_user(
  p_name text,
  p_slug text,
  p_phone text default null,
  p_address text default null,
  p_opening_time time default '08:00',
  p_closing_time time default '19:00',
  p_slot_interval integer default 30,
  p_service_name text default null,
  p_service_price numeric default 0,
  p_service_duration integer default 30,
  p_professional_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user_id uuid := auth.uid();
  v_business_id uuid;
  v_slug text := lower(trim(coalesce(p_slug, '')));
begin
  if v_user_id is null then
    raise exception 'authentication_required';
  end if;

  if exists (
    select 1
    from public.business_members bm
    where bm.user_id = v_user_id
  ) then
    raise exception 'user_already_has_business';
  end if;

  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'business_name_required';
  end if;

  if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or length(v_slug) < 3
     or length(v_slug) > 60 then
    raise exception 'invalid_business_slug';
  end if;

  if exists (select 1 from public.businesses b where b.slug = v_slug) then
    raise exception 'business_slug_taken';
  end if;

  if p_opening_time is null or p_closing_time is null or p_opening_time >= p_closing_time then
    raise exception 'invalid_business_hours';
  end if;

  if p_slot_interval not in (15, 20, 30, 45, 60) then
    raise exception 'invalid_slot_interval';
  end if;

  if length(trim(coalesce(p_service_name, ''))) < 1 then
    raise exception 'service_name_required';
  end if;

  if coalesce(p_service_price, -1) < 0 or coalesce(p_service_duration, 0) <= 0 then
    raise exception 'invalid_service';
  end if;

  if length(trim(coalesce(p_professional_name, ''))) < 1 then
    raise exception 'professional_name_required';
  end if;

  insert into public.businesses (
    name, slug, phone, address, opening_time, closing_time, slot_interval
  ) values (
    trim(p_name),
    v_slug,
    nullif(trim(coalesce(p_phone, '')), ''),
    nullif(trim(coalesce(p_address, '')), ''),
    p_opening_time,
    p_closing_time,
    p_slot_interval
  )
  returning id into v_business_id;

  insert into public.business_members (business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.services (
    business_id, name, price, duration_minutes, active
  ) values (
    v_business_id, trim(p_service_name), p_service_price, p_service_duration, true
  );

  insert into public.professionals (business_id, name, active)
  values (v_business_id, trim(p_professional_name), true);

  -- Em versoes Advanced, popula a grade semanal sem tornar a tabela obrigatoria.
  if to_regclass('public.business_hours') is not null then
    execute $q$
      insert into public.business_hours (
        business_id, day_of_week, is_open, open_time, close_time
      )
      select $1, d, true, $2, $3
      from generate_series(0, 6) as d
      on conflict (business_id, day_of_week) do nothing
    $q$ using v_business_id, p_opening_time, p_closing_time;
  end if;

  return v_business_id;
exception
  when unique_violation then
    raise exception 'business_slug_taken';
end;
$$;

revoke all on function public.create_business_for_current_user(
  text, text, text, text, time, time, integer, text, numeric, integer, text
) from public;

grant execute on function public.create_business_for_current_user(
  text, text, text, text, time, time, integer, text, numeric, integer, text
) to authenticated;

-- Forca o PostgREST/Supabase API a recarregar as funcoes sem esperar o cache expirar.
notify pgrst, 'reload schema';

-- Verificacao: deve retornar uma linha com os 11 argumentos da RPC.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as returns
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_business_for_current_user';

-- === 4. System settings repair ===
-- ============================================================
-- BARBERAGENDA PRO ADVANCED — HOTFIX system_settings
-- Corrige: Could not find the table 'public.system_settings' in the schema cache
-- Seguro para reexecução. Não apaga dados.
-- ============================================================

begin;

-- Garante a tabela global usada por MaintenanceGate, Login e DevSettings.
create table if not exists public.system_settings (
  id smallint primary key default 1 check (id = 1),
  app_name text not null default 'BarberAgenda',
  current_version text not null default '3.0.0',
  maintenance_mode boolean not null default false,
  allow_new_signups boolean not null default true,
  support_email text,
  announcement text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Compatibilidade com bancos onde a tabela possa existir incompleta.
alter table public.system_settings add column if not exists app_name text not null default 'BarberAgenda';
alter table public.system_settings add column if not exists current_version text not null default '3.0.0';
alter table public.system_settings add column if not exists maintenance_mode boolean not null default false;
alter table public.system_settings add column if not exists allow_new_signups boolean not null default true;
alter table public.system_settings add column if not exists support_email text;
alter table public.system_settings add column if not exists announcement text;
alter table public.system_settings add column if not exists updated_by uuid references auth.users(id) on delete set null;
alter table public.system_settings add column if not exists updated_at timestamptz not null default now();

-- Garante a única linha de configuração global.
insert into public.system_settings (
  id,
  app_name,
  current_version,
  maintenance_mode,
  allow_new_signups
)
values (1, 'BarberAgenda', '3.0.0', false, true)
on conflict (id) do nothing;

-- Garante helper mínimo de função do Admin Dev caso o script completo ainda não tenha sido aplicado.
create table if not exists public.developer_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'read_only'
    check (role in ('super_admin','support','billing','ops','read_only')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.dev_current_role()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select da.role
  from public.developer_admins da
  where da.user_id = auth.uid()
    and da.active = true
  limit 1;
$$;

grant execute on function public.dev_current_role() to authenticated;

-- Segurança: leitura pública somente das flags necessárias ao app.
alter table public.system_settings enable row level security;

drop policy if exists "public_read_system_settings" on public.system_settings;
create policy "public_read_system_settings"
on public.system_settings
for select
to anon, authenticated
using (true);

-- Somente Super Admin ou Ops podem alterar configurações globais.
drop policy if exists "dev_manage_system_settings" on public.system_settings;
create policy "dev_manage_system_settings"
on public.system_settings
for update
to authenticated
using (public.dev_current_role() in ('super_admin','ops'))
with check (public.dev_current_role() in ('super_admin','ops'));

-- Grants necessários para PostgREST.
grant select on table public.system_settings to anon, authenticated;
grant update on table public.system_settings to authenticated;

-- Mantém updated_at e updated_by coerentes em updates do painel Dev.
create or replace function public.touch_system_settings()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at := now();
  if auth.uid() is not null then
    new.updated_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_touch_system_settings on public.system_settings;
create trigger trg_touch_system_settings
before update on public.system_settings
for each row execute function public.touch_system_settings();

commit;

-- Força o PostgREST a recarregar tabelas/funções/policies no schema cache.
notify pgrst, 'reload schema';

-- Verificação final. Deve retornar exatamente uma linha com id = 1.
select
  id,
  app_name,
  current_version,
  maintenance_mode,
  allow_new_signups,
  support_email,
  announcement,
  updated_at
from public.system_settings
where id = 1;

-- === 5. Audit repair ===
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

-- === 6. Admin Dev RPC repair ===
-- ============================================================
-- BARBERAGENDA — HOTFIX COMPLETO DAS RPCs DO ADMIN DEV
-- Seguro para reexecução. Não apaga empresas, clientes ou agendamentos.
-- Corrige PGRST202 / "Could not find the function ... in schema cache".
-- ============================================================

create extension if not exists pgcrypto;

-- Pré-requisitos mínimos da base.
do $$
begin
  if to_regclass('public.businesses') is null then
    raise exception 'Tabela public.businesses não existe. Execute primeiro o schema/upgrade base do BarberAgenda.';
  end if;
  if to_regclass('public.business_members') is null then
    raise exception 'Tabela public.business_members não existe. Execute primeiro o schema/upgrade base do BarberAgenda.';
  end if;
  if to_regclass('public.appointments') is null then
    raise exception 'Tabela public.appointments não existe. Execute primeiro o schema/upgrade base do BarberAgenda.';
  end if;
end $$;

-- Colunas usadas pelo Dev Console.
alter table public.businesses add column if not exists platform_status text not null default 'active';
alter table public.businesses add column if not exists suspended_at timestamptz;
alter table public.businesses add column if not exists suspended_reason text;
alter table public.businesses add column if not exists updated_at timestamptz not null default now();

alter table public.business_members add column if not exists active boolean not null default true;
alter table public.business_members add column if not exists created_at timestamptz not null default now();

alter table public.appointments add column if not exists final_amount numeric(10,2);

-- Tabelas globais do Admin Dev.
create table if not exists public.developer_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'read_only' check (role in ('super_admin','support','billing','ops','read_only')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  description text,
  price_monthly numeric(10,2) not null default 0 check(price_monthly>=0),
  max_professionals integer,
  max_team_members integer,
  features jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.business_subscriptions (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  plan_id uuid references public.subscription_plans(id) on delete set null,
  status text not null default 'trialing' check(status in ('trialing','active','past_due','paused','canceled')),
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  external_customer_id text,
  external_subscription_id text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  subject text not null,
  message text not null,
  category text not null default 'general',
  priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
  status text not null default 'open' check(status in ('open','in_progress','waiting_customer','resolved','closed')),
  assigned_to uuid references public.developer_admins(user_id) on delete set null,
  internal_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.system_settings (
  id smallint primary key default 1 check(id=1),
  app_name text not null default 'BarberAgenda',
  current_version text not null default '3.0.0',
  maintenance_mode boolean not null default false,
  allow_new_signups boolean not null default true,
  support_email text,
  announcement text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.system_settings(id) values(1) on conflict(id) do nothing;

create table if not exists public.app_error_logs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  level text not null default 'error' check(level in ('info','warning','error','fatal')),
  source text not null default 'web',
  message text not null,
  stack text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.system_incidents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  severity text not null default 'minor' check(severity in ('minor','major','critical')),
  status text not null default 'investigating' check(status in ('investigating','identified','monitoring','resolved')),
  started_at timestamptz not null default now(),
  resolved_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.developer_audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Helpers de autenticação/permissão Dev
-- ============================================================
create or replace function public.is_developer_admin()
returns boolean
language sql stable security definer set search_path=public,auth as $$
  select exists(
    select 1 from public.developer_admins da
    where da.user_id=auth.uid() and da.active
  );
$$;

create or replace function public.dev_current_role()
returns text
language sql stable security definer set search_path=public,auth as $$
  select da.role from public.developer_admins da
  where da.user_id=auth.uid() and da.active
  limit 1;
$$;

create or replace function public.dev_can(p_permission text)
returns boolean
language plpgsql stable security definer set search_path=public,auth as $$
declare r text;
begin
  select role into r from public.developer_admins where user_id=auth.uid() and active limit 1;
  if r is null then return false; end if;
  if r='super_admin' then return true; end if;
  if p_permission='global.read' then return true; end if;
  if r='support' and p_permission in ('support.manage','users.manage') then return true; end if;
  if r='billing' and p_permission='billing.manage' then return true; end if;
  if r='ops' and p_permission in ('businesses.manage','health.manage') then return true; end if;
  return false;
end;$$;

create or replace function public.dev_write_audit(
  p_action text,
  p_target_type text default null,
  p_target_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
  insert into public.developer_audit_logs(actor_user_id,action,target_type,target_id,metadata)
  values(auth.uid(),p_action,p_target_type,p_target_id,coalesce(p_metadata,'{}'::jsonb));
end;$$;

-- ============================================================
-- RPCs consumidas pelo frontend Dev Admin
-- ============================================================
create or replace function public.dev_admin_dashboard()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare result jsonb;
begin
  if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
  select jsonb_build_object(
    'businesses_total',(select count(*) from public.businesses),
    'businesses_active',(select count(*) from public.businesses where platform_status='active'),
    'businesses_suspended',(select count(*) from public.businesses where platform_status='suspended'),
    'users_total',(select count(*) from auth.users),
    'appointments_today',(select count(*) from public.appointments where appointment_date=current_date and status not in ('cancelled','no_show')),
    'appointments_month',(select count(*) from public.appointments where appointment_date>=date_trunc('month',current_date)::date and appointment_date<(date_trunc('month',current_date)+interval '1 month')::date),
    'gmv_month',(select coalesce(sum(coalesce(final_amount,0)),0) from public.appointments where status='completed' and appointment_date>=date_trunc('month',current_date)::date and appointment_date<(date_trunc('month',current_date)+interval '1 month')::date),
    'open_tickets',(select count(*) from public.support_tickets where status not in ('resolved','closed')),
    'errors_24h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '24 hours'),
    'active_incidents',(select count(*) from public.system_incidents where status<>'resolved')
  ) into result;
  return result;
end;$$;

create or replace function public.dev_list_businesses(
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table(
  id uuid,name text,slug text,platform_status text,created_at timestamptz,updated_at timestamptz,
  owner_email text,member_count bigint,client_count bigint,appointment_count bigint,completed_revenue numeric,
  plan_id uuid,plan_name text,subscription_status text,current_period_ends_at timestamptz,last_appointment_at timestamptz
)
language sql security definer set search_path=public,auth as $$
  select b.id,b.name,b.slug,b.platform_status,b.created_at,b.updated_at,
    (select u.email from public.business_members bm join auth.users u on u.id=bm.user_id where bm.business_id=b.id and bm.role='owner' order by bm.created_at limit 1),
    (select count(*) from public.business_members bm where bm.business_id=b.id),
    (select count(*) from public.clients c where c.business_id=b.id),
    (select count(*) from public.appointments a where a.business_id=b.id),
    (select coalesce(sum(coalesce(a.final_amount,0)),0) from public.appointments a where a.business_id=b.id and a.status='completed'),
    bs.plan_id,sp.name,bs.status,bs.current_period_ends_at,
    (select max(a.created_at) from public.appointments a where a.business_id=b.id)
  from public.businesses b
  left join public.business_subscriptions bs on bs.business_id=b.id
  left join public.subscription_plans sp on sp.id=bs.plan_id
  where public.is_developer_admin()
    and (p_search is null or trim(p_search)='' or lower(b.name) like '%'||lower(trim(p_search))||'%' or lower(b.slug) like '%'||lower(trim(p_search))||'%')
  order by b.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),500)) offset greatest(0,coalesce(p_offset,0));
$$;

create or replace function public.dev_list_users(
  p_search text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table(
  user_id uuid,email text,created_at timestamptz,last_sign_in_at timestamptz,email_confirmed_at timestamptz,banned_until timestamptz,
  business_id uuid,business_name text,business_role text,membership_active boolean
)
language sql security definer set search_path=public,auth as $$
  select u.id,u.email,u.created_at,u.last_sign_in_at,u.email_confirmed_at,u.banned_until,
    bm.business_id,b.name,bm.role,bm.active
  from auth.users u
  left join lateral (
    select x.* from public.business_members x where x.user_id=u.id order by x.created_at limit 1
  ) bm on true
  left join public.businesses b on b.id=bm.business_id
  where public.is_developer_admin()
    and (p_search is null or trim(p_search)='' or lower(coalesce(u.email,'')) like '%'||lower(trim(p_search))||'%' or lower(coalesce(b.name,'')) like '%'||lower(trim(p_search))||'%')
  order by u.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),500)) offset greatest(0,coalesce(p_offset,0));
$$;

create or replace function public.dev_set_business_status(
  p_business_id uuid,
  p_status text,
  p_reason text default null
)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.dev_can('businesses.manage') then raise exception 'developer_permission_denied'; end if;
  if p_status not in ('active','suspended','archived') then raise exception 'invalid_business_status'; end if;
  update public.businesses set
    platform_status=p_status,
    suspended_at=case when p_status='suspended' then now() else null end,
    suspended_reason=case when p_status='suspended' then nullif(trim(coalesce(p_reason,'')),'') else null end,
    updated_at=now()
  where id=p_business_id;
  perform public.dev_write_audit('business.status_changed','business',p_business_id::text,jsonb_build_object('status',p_status,'reason',p_reason));
end;$$;

create or replace function public.dev_upsert_subscription(
  p_business_id uuid,
  p_plan_id uuid,
  p_status text,
  p_period_end timestamptz default null,
  p_notes text default null
)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.dev_can('billing.manage') then raise exception 'developer_permission_denied'; end if;
  if p_status not in ('trialing','active','past_due','paused','canceled') then raise exception 'invalid_subscription_status'; end if;
  insert into public.business_subscriptions(business_id,plan_id,status,current_period_ends_at,notes)
  values(p_business_id,p_plan_id,p_status,p_period_end,p_notes)
  on conflict(business_id) do update set
    plan_id=excluded.plan_id,
    status=excluded.status,
    current_period_ends_at=excluded.current_period_ends_at,
    notes=excluded.notes,
    updated_at=now();
  perform public.dev_write_audit('subscription.updated','business',p_business_id::text,jsonb_build_object('plan_id',p_plan_id,'status',p_status));
end;$$;

create or replace function public.dev_add_developer_admin(p_email text,p_role text)
returns uuid language plpgsql security definer set search_path=public,auth as $$
declare uid uuid;
begin
  if public.dev_current_role()<>'super_admin' then raise exception 'super_admin_required'; end if;
  if p_role not in ('super_admin','support','billing','ops','read_only') then raise exception 'invalid_dev_role'; end if;
  select id into uid from auth.users where lower(email)=lower(trim(p_email)) limit 1;
  if uid is null then raise exception 'auth_user_not_found'; end if;
  insert into public.developer_admins(user_id,email,role,active)
  values(uid,lower(trim(p_email)),p_role,true)
  on conflict(user_id) do update set email=excluded.email,role=excluded.role,active=true,updated_at=now();
  perform public.dev_write_audit('developer_admin.added','user',uid::text,jsonb_build_object('role',p_role));
  return uid;
end;$$;

create or replace function public.dev_remove_developer_admin(p_user_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if public.dev_current_role()<>'super_admin' then raise exception 'super_admin_required'; end if;
  if p_user_id=auth.uid() then raise exception 'cannot_remove_yourself'; end if;
  update public.developer_admins set active=false,updated_at=now() where user_id=p_user_id;
  perform public.dev_write_audit('developer_admin.disabled','user',p_user_id::text,'{}'::jsonb);
end;$$;

create or replace function public.dev_health_summary()
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare result jsonb;
begin
  if not public.is_developer_admin() then raise exception 'developer_admin_required'; end if;
  select jsonb_build_object(
    'errors_1h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '1 hour'),
    'errors_24h',(select count(*) from public.app_error_logs where level in ('error','fatal') and created_at>=now()-interval '24 hours'),
    'warnings_24h',(select count(*) from public.app_error_logs where level='warning' and created_at>=now()-interval '24 hours'),
    'open_incidents',(select count(*) from public.system_incidents where status<>'resolved'),
    'appointments_24h',(select count(*) from public.appointments where created_at>=now()-interval '24 hours'),
    'new_users_24h',(select count(*) from auth.users where created_at>=now()-interval '24 hours'),
    'new_businesses_24h',(select count(*) from public.businesses where created_at>=now()-interval '24 hours')
  ) into result;
  return result;
end;$$;

-- Permissões de execução das RPCs.
grant execute on function public.is_developer_admin() to authenticated;
grant execute on function public.dev_current_role() to authenticated;
grant execute on function public.dev_can(text) to authenticated;
grant execute on function public.dev_write_audit(text,text,text,jsonb) to authenticated;
grant execute on function public.dev_admin_dashboard() to authenticated;
grant execute on function public.dev_list_businesses(text,integer,integer) to authenticated;
grant execute on function public.dev_list_users(text,integer,integer) to authenticated;
grant execute on function public.dev_set_business_status(uuid,text,text) to authenticated;
grant execute on function public.dev_upsert_subscription(uuid,uuid,text,timestamptz,text) to authenticated;
grant execute on function public.dev_add_developer_admin(text,text) to authenticated;
grant execute on function public.dev_remove_developer_admin(uuid) to authenticated;
grant execute on function public.dev_health_summary() to authenticated;

-- Grants das tabelas que o frontend consulta diretamente; RLS continua controlando o acesso.
grant select on public.developer_admins to authenticated;
grant select,insert,update,delete on public.subscription_plans to authenticated;
grant select,insert,update,delete on public.business_subscriptions to authenticated;
grant select,insert,update,delete on public.support_tickets to authenticated;
grant select,update on public.system_settings to authenticated;
grant select,insert on public.app_error_logs to authenticated;
grant select,insert,update,delete on public.system_incidents to authenticated;
grant select on public.developer_audit_logs to authenticated;

-- RLS mínimo para o Dev Console.
alter table public.developer_admins enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.business_subscriptions enable row level security;
alter table public.support_tickets enable row level security;
alter table public.system_settings enable row level security;
alter table public.app_error_logs enable row level security;
alter table public.system_incidents enable row level security;
alter table public.developer_audit_logs enable row level security;

-- Policies idempotentes.
drop policy if exists "dev_read_developer_admins" on public.developer_admins;
create policy "dev_read_developer_admins" on public.developer_admins for select using(public.is_developer_admin());

drop policy if exists "super_manage_developer_admins" on public.developer_admins;
create policy "super_manage_developer_admins" on public.developer_admins for all using(public.dev_current_role()='super_admin') with check(public.dev_current_role()='super_admin');

drop policy if exists "public_read_active_plans" on public.subscription_plans;
create policy "public_read_active_plans" on public.subscription_plans for select using(active or public.is_developer_admin());

drop policy if exists "dev_manage_plans" on public.subscription_plans;
create policy "dev_manage_plans" on public.subscription_plans for all using(public.dev_can('billing.manage')) with check(public.dev_can('billing.manage'));

drop policy if exists "dev_read_subscriptions" on public.business_subscriptions;
create policy "dev_read_subscriptions" on public.business_subscriptions for select using(public.is_developer_admin());

drop policy if exists "dev_manage_subscriptions" on public.business_subscriptions;
create policy "dev_manage_subscriptions" on public.business_subscriptions for all using(public.dev_can('billing.manage')) with check(public.dev_can('billing.manage'));

drop policy if exists "dev_read_tickets" on public.support_tickets;
create policy "dev_read_tickets" on public.support_tickets for select using(public.is_developer_admin());

drop policy if exists "dev_manage_tickets" on public.support_tickets;
create policy "dev_manage_tickets" on public.support_tickets for all using(public.dev_can('support.manage')) with check(public.dev_can('support.manage'));

drop policy if exists "public_read_system_settings" on public.system_settings;
create policy "public_read_system_settings" on public.system_settings for select using(true);

drop policy if exists "dev_manage_system_settings" on public.system_settings;
create policy "dev_manage_system_settings" on public.system_settings for update using(public.dev_can('health.manage') or public.dev_current_role()='super_admin') with check(public.dev_can('health.manage') or public.dev_current_role()='super_admin');

drop policy if exists "dev_read_error_logs" on public.app_error_logs;
create policy "dev_read_error_logs" on public.app_error_logs for select using(public.is_developer_admin());

drop policy if exists "users_insert_error_logs" on public.app_error_logs;
create policy "users_insert_error_logs" on public.app_error_logs for insert with check(auth.uid() is not null and (user_id is null or user_id=auth.uid()));

drop policy if exists "public_read_incidents" on public.system_incidents;
create policy "public_read_incidents" on public.system_incidents for select using(true);

drop policy if exists "dev_manage_incidents" on public.system_incidents;
create policy "dev_manage_incidents" on public.system_incidents for all using(public.dev_can('health.manage')) with check(public.dev_can('health.manage'));

drop policy if exists "dev_read_dev_audit" on public.developer_audit_logs;
create policy "dev_read_dev_audit" on public.developer_audit_logs for select using(public.is_developer_admin());

-- Dev Admin precisa enxergar empresas e vínculos.
drop policy if exists "dev_read_all_businesses" on public.businesses;
create policy "dev_read_all_businesses" on public.businesses for select using(public.is_developer_admin());

drop policy if exists "dev_update_businesses" on public.businesses;
create policy "dev_update_businesses" on public.businesses for update using(public.dev_can('businesses.manage')) with check(public.dev_can('businesses.manage'));

drop policy if exists "dev_read_business_members" on public.business_members;
create policy "dev_read_business_members" on public.business_members for select using(public.is_developer_admin());

drop policy if exists "dev_update_business_members" on public.business_members;
create policy "dev_update_business_members" on public.business_members for update using(public.dev_can('users.manage') or public.dev_can('businesses.manage')) with check(public.dev_can('users.manage') or public.dev_can('businesses.manage'));

-- Recarrega o cache do PostgREST para as RPCs aparecerem imediatamente.
notify pgrst, 'reload schema';

-- Diagnóstico final: todas estas linhas devem retornar OK.
select object_name, status
from (
  values
    ('is_developer_admin()', case when to_regprocedure('public.is_developer_admin()') is not null then 'OK' else 'MISSING' end),
    ('dev_current_role()', case when to_regprocedure('public.dev_current_role()') is not null then 'OK' else 'MISSING' end),
    ('dev_can(text)', case when to_regprocedure('public.dev_can(text)') is not null then 'OK' else 'MISSING' end),
    ('dev_admin_dashboard()', case when to_regprocedure('public.dev_admin_dashboard()') is not null then 'OK' else 'MISSING' end),
    ('dev_list_businesses(text,integer,integer)', case when to_regprocedure('public.dev_list_businesses(text,integer,integer)') is not null then 'OK' else 'MISSING' end),
    ('dev_list_users(text,integer,integer)', case when to_regprocedure('public.dev_list_users(text,integer,integer)') is not null then 'OK' else 'MISSING' end),
    ('dev_set_business_status(uuid,text,text)', case when to_regprocedure('public.dev_set_business_status(uuid,text,text)') is not null then 'OK' else 'MISSING' end),
    ('dev_upsert_subscription(uuid,uuid,text,timestamptz,text)', case when to_regprocedure('public.dev_upsert_subscription(uuid,uuid,text,timestamptz,text)') is not null then 'OK' else 'MISSING' end),
    ('dev_add_developer_admin(text,text)', case when to_regprocedure('public.dev_add_developer_admin(text,text)') is not null then 'OK' else 'MISSING' end),
    ('dev_remove_developer_admin(uuid)', case when to_regprocedure('public.dev_remove_developer_admin(uuid)') is not null then 'OK' else 'MISSING' end),
    ('dev_health_summary()', case when to_regprocedure('public.dev_health_summary()') is not null then 'OK' else 'MISSING' end)
) as x(object_name,status)
order by object_name;

-- === 7. Booking columns repair ===
-- BARBERAGENDA PRO ADVANCED
-- Hotfix seguro para colunas avançadas da tabela public.businesses.
-- Pode ser executado mais de uma vez. Não apaga empresas nem dados existentes.

begin;

alter table public.businesses
  add column if not exists timezone text default 'America/Sao_Paulo',
  add column if not exists booking_advance_days integer default 60,
  add column if not exists min_booking_notice_minutes integer default 60,
  add column if not exists cancellation_notice_hours integer default 2,
  add column if not exists platform_status text default 'active';

-- Corrige possíveis NULLs de instalações antigas antes de aplicar NOT NULL.
update public.businesses set timezone = 'America/Sao_Paulo' where timezone is null or btrim(timezone) = '';
update public.businesses set booking_advance_days = 60 where booking_advance_days is null;
update public.businesses set min_booking_notice_minutes = 60 where min_booking_notice_minutes is null;
update public.businesses set cancellation_notice_hours = 2 where cancellation_notice_hours is null;
update public.businesses set platform_status = 'active' where platform_status is null or btrim(platform_status) = '';

alter table public.businesses alter column timezone set default 'America/Sao_Paulo';
alter table public.businesses alter column timezone set not null;
alter table public.businesses alter column booking_advance_days set default 60;
alter table public.businesses alter column booking_advance_days set not null;
alter table public.businesses alter column min_booking_notice_minutes set default 60;
alter table public.businesses alter column min_booking_notice_minutes set not null;
alter table public.businesses alter column cancellation_notice_hours set default 2;
alter table public.businesses alter column cancellation_notice_hours set not null;
alter table public.businesses alter column platform_status set default 'active';
alter table public.businesses alter column platform_status set not null;

-- Constraints nomeadas e idempotentes.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_booking_advance_days_check'
  ) then
    alter table public.businesses
      add constraint businesses_booking_advance_days_check
      check (booking_advance_days between 1 and 365) not valid;
    alter table public.businesses validate constraint businesses_booking_advance_days_check;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_min_booking_notice_minutes_check'
  ) then
    alter table public.businesses
      add constraint businesses_min_booking_notice_minutes_check
      check (min_booking_notice_minutes between 0 and 10080) not valid;
    alter table public.businesses validate constraint businesses_min_booking_notice_minutes_check;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_cancellation_notice_hours_check'
  ) then
    alter table public.businesses
      add constraint businesses_cancellation_notice_hours_check
      check (cancellation_notice_hours between 0 and 168) not valid;
    alter table public.businesses validate constraint businesses_cancellation_notice_hours_check;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.businesses'::regclass
      and conname = 'businesses_platform_status_check'
  ) then
    alter table public.businesses
      add constraint businesses_platform_status_check
      check (platform_status in ('active','suspended','archived')) not valid;
    alter table public.businesses validate constraint businesses_platform_status_check;
  end if;
end $$;

commit;

-- Força o PostgREST/Supabase a reler colunas e funções do schema public.
notify pgrst, 'reload schema';

-- Diagnóstico: as cinco linhas abaixo devem aparecer como OK.
select
  c.column_name,
  c.data_type,
  c.is_nullable,
  c.column_default,
  'OK'::text as status
from information_schema.columns c
where c.table_schema = 'public'
  and c.table_name = 'businesses'
  and c.column_name in (
    'timezone',
    'booking_advance_days',
    'min_booking_notice_minutes',
    'cancellation_notice_hours',
    'platform_status'
  )
order by c.column_name;

-- Diagnóstico adicional das RPCs usadas pela agenda avançada.
select 'get_booking_day_rules(uuid,uuid,date)' as object,
       case when to_regprocedure('public.get_booking_day_rules(uuid,uuid,date)') is null then 'MISSING' else 'OK' end as status
union all
select 'get_public_schedule_blocks(uuid,uuid,date)',
       case when to_regprocedure('public.get_public_schedule_blocks(uuid,uuid,date)') is null then 'MISSING' else 'OK' end
union all
select 'get_busy_ranges(uuid,uuid,date)',
       case when to_regprocedure('public.get_busy_ranges(uuid,uuid,date)') is null then 'MISSING' else 'OK' end;

-- === 8. Enterprise V4 ===
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

notify pgrst,'reload schema';
