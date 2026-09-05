-- BarberAgenda 4.3.0 — CRM Offline First
-- Execute no Supabase SQL Editor.

alter table public.clients
  add column if not exists last_contact_at timestamptz;

drop function if exists public.get_clients_with_stats(uuid);

create function public.get_clients_with_stats(p_business_id uuid)
returns table (
  id uuid,
  name text,
  phone text,
  email text,
  notes text,
  birthday date,
  tags text[],
  source text,
  marketing_opt_in boolean,
  blocked boolean,
  total_appointments bigint,
  completed_appointments bigint,
  cancelled_appointments bigint,
  no_show_appointments bigint,
  total_spent numeric,
  average_ticket numeric,
  first_appointment_date date,
  last_appointment_date date,
  next_appointment_date date,
  days_since_last integer,
  favorite_service_name text,
  favorite_professional_name text,
  last_contact_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = auth.uid()
      and coalesce(bm.active, true) = true
  ) then
    raise exception 'not_authorized';
  end if;

  return query
  with base as (
    select
      c.id,
      c.name,
      c.phone,
      c.email,
      c.notes,
      c.birthday,
      c.tags,
      c.source,
      c.marketing_opt_in,
      c.blocked,
      count(a.id) filter (where a.status <> 'cancelled')::bigint as total_appointments,
      count(a.id) filter (where a.status = 'completed')::bigint as completed_appointments,
      count(a.id) filter (where a.status = 'cancelled')::bigint as cancelled_appointments,
      count(a.id) filter (where a.status = 'no_show')::bigint as no_show_appointments,
      coalesce(sum(s.price) filter (where a.status = 'completed'), 0)::numeric as total_spent,
      coalesce(avg(s.price) filter (where a.status = 'completed'), 0)::numeric as average_ticket,
      min(a.appointment_date) filter (where a.status <> 'cancelled') as first_appointment_date,
      max(a.appointment_date) filter (
        where a.status in ('completed','confirmed','no_show')
          and a.appointment_date <= current_date
      ) as last_appointment_date,
      min(a.appointment_date) filter (
        where a.status in ('pending','confirmed')
          and a.appointment_date >= current_date
      ) as next_appointment_date,
      c.last_contact_at,
      c.updated_at
    from public.clients c
    left join public.appointments a on a.client_id = c.id
    left join public.services s on s.id = a.service_id
    where c.business_id = p_business_id
    group by c.id
  )
  select
    b.id,
    b.name,
    b.phone,
    b.email,
    b.notes,
    b.birthday,
    b.tags,
    b.source,
    b.marketing_opt_in,
    b.blocked,
    b.total_appointments,
    b.completed_appointments,
    b.cancelled_appointments,
    b.no_show_appointments,
    b.total_spent,
    b.average_ticket,
    b.first_appointment_date,
    b.last_appointment_date,
    b.next_appointment_date,
    case
      when b.last_appointment_date is null then null
      else (current_date - b.last_appointment_date)::integer
    end as days_since_last,
    (
      select s2.name
      from public.appointments a2
      join public.services s2 on s2.id = a2.service_id
      where a2.client_id = b.id and a2.status = 'completed'
      group by s2.id, s2.name
      order by count(*) desc, max(a2.appointment_date) desc
      limit 1
    ) as favorite_service_name,
    (
      select p2.name
      from public.appointments a3
      join public.professionals p2 on p2.id = a3.professional_id
      where a3.client_id = b.id and a3.status = 'completed'
      group by p2.id, p2.name
      order by count(*) desc, max(a3.appointment_date) desc
      limit 1
    ) as favorite_professional_name,
    b.last_contact_at,
    b.updated_at
  from base b
  order by b.updated_at desc, b.name asc;
end;
$$;

revoke all on function public.get_clients_with_stats(uuid) from public;
grant execute on function public.get_clients_with_stats(uuid) to authenticated;

-- A tabela clients já usa RLS no BarberAgenda. Reforça acesso apenas autenticado.
revoke all on table public.clients from anon;
grant select, insert, update, delete on table public.clients to authenticated;
