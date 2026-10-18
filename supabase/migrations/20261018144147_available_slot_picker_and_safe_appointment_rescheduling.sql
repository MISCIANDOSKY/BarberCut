create function private.get_reschedule_slots(p_id uuid,p_day date)
returns table(start_at timestamptz,requires_confirmation boolean)
language plpgsql stable security definer set search_path='' as $fn$
declare entry public.calendar_entries; duration interval;
begin
 select * into entry from public.calendar_entries where id=p_id;
 if not found or entry.kind<>'appointment' or entry.status<>'confirmed'
    or not coalesce(private.can_manage(entry.barber_id),false) then raise exception 'ACCESS_DENIED';end if;
 if not exists(select 1 from public.services s join public.barber_services bs on bs.service_id=s.id
   join public.barbers b on b.id=bs.barber_id where s.id=entry.service_id and b.id=entry.barber_id
   and s.active and bs.active and b.active and s.deleted_at is null and b.deleted_at is null) then return;end if;
 if p_day is null or p_day<(now() at time zone 'Europe/Rome')::date
   or p_day>((now() at time zone 'Europe/Rome')::date+interval '3 months')::date then return;end if;
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
$fn$;
create function public.get_reschedule_slots(p_id uuid,p_day date)
returns table(start_at timestamptz,requires_confirmation boolean)
language sql stable security invoker set search_path='' as $fn$
 select * from private.get_reschedule_slots(p_id,p_day)
$fn$;

create function private.reschedule_appointment(p_id uuid,p_start timestamptz,p_confirm_closed boolean)
returns void language plpgsql security definer set search_path='' as $fn$
declare entry public.calendar_entries; initial_barber uuid; duration interval; needs_confirmation boolean;
begin
 select * into entry from public.calendar_entries where id=p_id;
 if not found or entry.kind<>'appointment' or entry.status<>'confirmed'
   or not coalesce(private.can_manage(entry.barber_id),false) then raise exception 'ACCESS_DENIED';end if;
 initial_barber:=entry.barber_id;
 perform pg_advisory_xact_lock(hashtextextended(coalesce(entry.client_id::text,'guest:'||entry.id::text),1));
 perform pg_advisory_xact_lock(hashtextextended(entry.barber_id::text,2));
 select * into entry from public.calendar_entries where id=p_id for update;
 if not found or entry.kind<>'appointment' or entry.status<>'confirmed'
   or entry.barber_id<>initial_barber or not coalesce(private.can_manage(entry.barber_id),false) then raise exception 'ACCESS_DENIED';end if;
 perform 1 from public.services where id=entry.service_id and deleted_at is null for share;
 if not found then raise exception 'SLOT_TAKEN';end if;
 select s.requires_confirmation into needs_confirmation from private.get_reschedule_slots(p_id,(p_start at time zone 'Europe/Rome')::date) s where s.start_at=p_start;
 if not found then raise exception 'SLOT_TAKEN';end if;
 if needs_confirmation and not coalesce(p_confirm_closed,false) then raise exception 'CLOSED_DAY_CONFIRM_REQUIRED';end if;
 if p_start=entry.start_at then return;end if;
 duration:=entry.end_at-entry.start_at;
 update public.calendar_entries set start_at=p_start,end_at=p_start+duration,updated_at=now() where id=p_id;
end
$fn$;
create function public.reschedule_appointment(p_id uuid,p_start timestamptz,p_confirm_closed boolean)
returns void language sql security invoker set search_path='' as $fn$
 select private.reschedule_appointment(p_id,p_start,p_confirm_closed)
$fn$;
-- Keep old clients safe: outside-hours moves still require explicit confirmation.
create or replace function private.reschedule_appointment(p_id uuid,p_start timestamptz)
returns void language plpgsql security definer set search_path='' as $fn$
begin
 perform private.reschedule_appointment(p_id,p_start,false);
end
$fn$;
revoke all on function private.get_reschedule_slots(uuid,date),public.get_reschedule_slots(uuid,date),
 private.reschedule_appointment(uuid,timestamptz,boolean),public.reschedule_appointment(uuid,timestamptz,boolean) from public,anon;
grant execute on function private.get_reschedule_slots(uuid,date),public.get_reschedule_slots(uuid,date),
 private.reschedule_appointment(uuid,timestamptz,boolean),public.reschedule_appointment(uuid,timestamptz,boolean) to authenticated;
notify pgrst,'reload schema';
