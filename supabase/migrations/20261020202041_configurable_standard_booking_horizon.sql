alter table public.app_settings add column booking_horizon_months integer not null default 6 check (booking_horizon_months between 1 and 120);
create or replace function private.booking_max_day() returns date language sql stable security definer set search_path='' as $function$
 select ((now() at time zone 'Europe/Rome')::date+make_interval(months=>(select booking_horizon_months from public.app_settings where id)))::date
$function$;
revoke all on function private.booking_max_day() from public, anon, authenticated;
create or replace function private.set_booking_horizon(p_months integer) returns void language plpgsql security definer set search_path='' as $function$
begin
 if not coalesce(private.can_configure_shop(),false) then raise exception 'ACCESS_DENIED';end if;
 if p_months is null or p_months not between 1 and 120 then raise exception 'INVALID_BOOKING_HORIZON';end if;
 update public.app_settings set booking_horizon_months=p_months where id;
end $function$;
create or replace function public.set_booking_horizon(p_months integer) returns void language sql set search_path='' as $function$
 select private.set_booking_horizon(p_months)
$function$;
revoke all on function private.set_booking_horizon(integer) from public,anon;
revoke all on function public.set_booking_horizon(integer) from public,anon;
grant execute on function private.set_booking_horizon(integer),public.set_booking_horizon(integer) to authenticated;

CREATE OR REPLACE FUNCTION private.get_available_slots(p_barber uuid, p_service uuid, p_day date)
 RETURNS TABLE(start_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with svc as(select s.duration_minutes from public.services s join public.barber_services bs on bs.service_id=s.id join public.barbers b on b.id=bs.barber_id where s.id=p_service and bs.barber_id=p_barber and s.active and bs.active and b.active and s.deleted_at is null and b.deleted_at is null),
intervals as(
select e.opens,e.closes from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day and not e.closed and not exists(select 1 from public.schedule_exceptions x where x.barber_id=p_barber and x.day=p_day and x.closed)
union all
select w.opens,w.closes from public.working_hours w where w.barber_id=p_barber and w.weekday=extract(dow from p_day) and not private.is_holiday(p_day) and not exists(select 1 from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day)
),
slots as(select distinct g as t,s.duration_minutes from svc s cross join intervals i cross join lateral generate_series((p_day+i.opens) at time zone 'Europe/Rome',((p_day+i.closes) at time zone 'Europe/Rome')-make_interval(mins=>s.duration_minutes),interval '15 minutes') g)
select t from slots where t>now() and p_day<=private.booking_max_day() and p_day>=(now() at time zone 'Europe/Rome')::date and not exists(select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed' and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(t,t+make_interval(mins=>duration_minutes),'[)')) order by t
$function$
;

CREATE OR REPLACE FUNCTION private.get_manual_booking_slots(p_barber uuid, p_service uuid, p_day date)
 RETURNS TABLE(start_at timestamp with time zone, requires_confirmation boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare duration integer;
begin
 if not coalesce(private.can_manage(p_barber),false) then raise exception 'ACCESS_DENIED';end if;
 select s.duration_minutes into duration
 from public.services s join public.barber_services bs on bs.service_id=s.id join public.barbers b on b.id=bs.barber_id
 where s.id=p_service and b.id=p_barber and s.active and bs.active and b.active and s.deleted_at is null and b.deleted_at is null;
 if not found then return;end if;
 if p_day is null or p_day<(now() at time zone 'Europe/Rome')::date
    or p_day>(private.booking_max_day())::date then return;end if;
 return query
 with regular as materialized(select s.start_at from public.get_available_slots(p_barber,p_service,p_day) s)
 select g.t,not exists(select 1 from regular r where r.start_at=g.t)
 from generate_series(p_day::timestamp at time zone 'Europe/Rome',
   ((p_day+1)::timestamp at time zone 'Europe/Rome')-make_interval(mins=>duration),
   interval '15 minutes') g(t)
 where g.t>now() and not exists(
   select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed'
   and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(g.t,g.t+make_interval(mins=>duration),'[)')
 ) order by g.t;
end
$function$
;

CREATE OR REPLACE FUNCTION private.get_reschedule_slots(p_id uuid, p_day date)
 RETURNS TABLE(start_at timestamp with time zone, requires_confirmation boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare entry public.calendar_entries; duration interval;
begin
 select * into entry from public.calendar_entries where id=p_id;
 if not found or entry.kind<>'appointment' or entry.status<>'confirmed'
    or not coalesce((private.can_manage(entry.barber_id) or private.can_manage_shop_agenda(entry.barber_id)),false) then raise exception 'ACCESS_DENIED';end if;
 if not exists(select 1 from public.services s join public.barber_services bs on bs.service_id=s.id
   join public.barbers b on b.id=bs.barber_id where s.id=entry.service_id and b.id=entry.barber_id
   and s.active and bs.active and b.active and s.deleted_at is null and b.deleted_at is null) then return;end if;
 if p_day is null or p_day<(now() at time zone 'Europe/Rome')::date
   or (p_day>(private.booking_max_day())::date and not exists(select 1 from private.recurring_occurrences ro where ro.entry_id=p_id)) then return;end if;
 duration:=entry.end_at-entry.start_at;
 return query
 with intervals as (
   select e.opens,e.closes from public.schedule_exceptions e
   where e.barber_id=entry.barber_id and e.day=p_day and not e.closed
   and not exists(select 1 from public.schedule_exceptions x where x.barber_id=entry.barber_id and x.day=p_day and x.closed)
   union all
   select w.opens,w.closes from public.working_hours w
   where w.barber_id=entry.barber_id and w.weekday=extract(dow from p_day)
   and not private.is_holiday(p_day)
   and not exists(select 1 from public.schedule_exceptions e where e.barber_id=entry.barber_id and e.day=p_day)
 )
 select g.t,not exists(select 1 from intervals i
   where g.t>=(p_day+i.opens) at time zone 'Europe/Rome'
   and g.t+duration<=(p_day+i.closes) at time zone 'Europe/Rome')
 from generate_series(p_day::timestamp at time zone 'Europe/Rome',
   ((p_day+1)::timestamp at time zone 'Europe/Rome')-duration,interval '15 minutes') g(t)
 where g.t>now() and not exists(select 1 from public.calendar_entries other
   where other.barber_id=entry.barber_id and other.id<>entry.id and other.status='confirmed'
   and tstzrange(other.start_at,other.end_at,'[)') && tstzrange(g.t,g.t+duration,'[)'))
 order by g.t;
end
$function$
;
