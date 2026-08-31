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
