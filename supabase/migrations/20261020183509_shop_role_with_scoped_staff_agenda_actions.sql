alter table public.user_roles drop constraint user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check(role in('client','barber','barber_admin','admin','shop'));
CREATE OR REPLACE FUNCTION public.staff_authorize_session(p_user uuid, p_session text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
insert into private.staff_sessions(user_id,session_id,otp_hash,expires_at,verified_until) select p_user,p_session,'managed-by-supabase-auth',now(),now()+interval '8 hours' where exists(select 1 from public.user_roles where user_id=p_user and role in('admin','barber','barber_admin','shop')) on conflict(user_id,session_id) do update set verified_until=now()+interval '8 hours'
$function$;
create function private.can_manage_shop_agenda(p_barber uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.has_role('shop'),false) and exists(
 select 1 from public.barbers b join public.user_roles r on r.user_id=b.user_id
 where b.id=p_barber and b.active and b.deleted_at is null and r.role in('barber','barber_admin'))
$$;
revoke all on function private.can_manage_shop_agenda(uuid) from public,anon;
grant execute on function private.can_manage_shop_agenda(uuid) to authenticated;
create function private.shop_barbers() returns table(id uuid,name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('shop'),false) then raise exception 'ACCESS_DENIED';end if;
 return query select b.id,b.name from public.barbers b join public.user_roles r on r.user_id=b.user_id
 where b.active and b.deleted_at is null and r.role in('barber','barber_admin') order by b.name,b.id;
end $$;
create function private.shop_agenda(p_barber uuid,p_day date)
returns table(id uuid,start_at timestamptz,end_at timestamptz,client_name text,service_name text,phone text,price numeric)
language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('shop'),false) then raise exception 'ACCESS_DENIED';end if;
 if not exists(select 1 from private.shop_barbers() b where b.id=p_barber) then raise exception 'ACCESS_DENIED';end if;
 if p_day is null then raise exception 'INVALID_DATE';end if;
 return query
 select e.id,e.start_at,e.end_at,
 trim(case when e.guest_first_name<>'' or e.guest_last_name<>'' then e.guest_first_name||' '||e.guest_last_name
 else coalesce(p.first_name,'')||' '||coalesce(p.last_name,'') end),e.service_name,coalesce(nullif(e.guest_phone,''),p.phone,''),e.price
 from public.calendar_entries e left join public.profiles p on p.id=e.client_id
 where e.barber_id=p_barber and e.kind='appointment' and e.status='confirmed'
 and e.start_at>=p_day::timestamp at time zone 'Europe/Rome'
 and e.start_at<(p_day+1)::timestamp at time zone 'Europe/Rome'
 order by e.start_at,e.id;
end $$;
create function public.shop_barbers() returns table(id uuid,name text) language sql set search_path='' as $$select * from private.shop_barbers()$$;
create function public.shop_agenda(p_barber uuid,p_day date) returns table(id uuid,start_at timestamptz,end_at timestamptz,client_name text,service_name text,phone text,price numeric)
language sql set search_path='' as $$select * from private.shop_agenda(p_barber,p_day)$$;
revoke all on function private.shop_barbers(),public.shop_barbers(),private.shop_agenda(uuid,date),public.shop_agenda(uuid,date) from public,anon;
grant execute on function private.shop_barbers(),public.shop_barbers(),private.shop_agenda(uuid,date),public.shop_agenda(uuid,date) to authenticated;
CREATE OR REPLACE FUNCTION private.book_appointment(p_barber uuid, p_service uuid, p_start timestamp with time zone, p_client uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c uuid:=coalesce(p_client,auth.uid()); svc public.services; result uuid; staff boolean:=private.can_manage(p_barber);
begin
 if exists(select 1 from public.user_roles where user_id=auth.uid() and role='shop') then raise exception 'ACCESS_DENIED';end if;
if auth.uid() is null or(c<>auth.uid() and not staff) then raise exception 'ACCESS_DENIED'; end if;
if not staff and not (select bookings_enabled from public.app_settings where id) then raise exception 'BOOKINGS_DISABLED'; end if;
perform pg_advisory_xact_lock(hashtextextended(c::text,1));
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
if not exists(select 1 from public.profiles where id=c and deletion_requested_at is null and length(trim(first_name))>0 and length(trim(last_name))>0 and length(trim(phone))>0) then raise exception 'PROFILE_REQUIRED'; end if;
if exists(select 1 from public.terms_versions where published) and not exists(select 1 from public.terms_acceptances a join public.terms_versions t on t.id=a.terms_id where a.user_id=c and t.published) then raise exception 'TERMS_REQUIRED'; end if;
if(select count(*) from public.calendar_entries where client_id=c and kind='appointment' and status='confirmed' and start_at>now() and not exists(select 1 from private.recurring_occurrences ro where ro.entry_id=calendar_entries.id))>=5 then raise exception 'LIMIT_FIVE'; end if;
select * into strict svc from public.services where id=p_service and deleted_at is null for share;
if not exists(select 1 from public.get_available_slots(p_barber,p_service,(p_start at time zone 'Europe/Rome')::date) a where a.start_at=p_start) then raise exception 'SLOT_TAKEN'; end if;
insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by) values(p_barber,'appointment',c,p_service,p_start,p_start+make_interval(mins=>svc.duration_minutes),svc.name,svc.price,auth.uid()) returning id into result;
return result;
end $function$;

CREATE OR REPLACE FUNCTION private.cancel_appointment(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e public.calendar_entries; hours int;
begin
select * into strict e from public.calendar_entries where id=p_id for update;
if exists(select 1 from public.user_roles where user_id=auth.uid() and role='shop') and (e.kind<>'appointment' or not private.can_manage_shop_agenda(e.barber_id)) then raise exception 'ACCESS_DENIED';end if;
if not (private.can_manage(e.barber_id) or private.can_manage_shop_agenda(e.barber_id)) then
if e.client_id is distinct from auth.uid() or auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
select cancellation_hours into hours from public.app_settings where id;
if hours is null then raise exception 'CANCELLATION_NOT_CONFIGURED';end if;
if e.start_at<now()+make_interval(hours=>hours) then raise exception 'CANCELLATION_TOO_LATE';end if;
end if;
update public.calendar_entries set status='cancelled',updated_at=now() where id=p_id;
end $function$;

CREATE OR REPLACE FUNCTION private.recurring_plan_context(p_plan uuid)
 RETURNS private.recurring_plans
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p private.recurring_plans;
begin
 if exists(select 1 from public.user_roles where user_id=auth.uid() and role='shop') then raise exception 'ACCESS_DENIED';end if;
 select * into p from private.recurring_plans where id=p_plan and client_id=auth.uid();
 if not found or auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 return p;
end $function$;


CREATE OR REPLACE FUNCTION private.appointment_is_recurring(p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not exists(select 1 from public.calendar_entries e where e.id=p_id and(e.client_id=auth.uid() or (private.can_manage(e.barber_id) or private.can_manage_shop_agenda(e.barber_id)))) then raise exception 'ACCESS_DENIED';end if;
 return exists(select 1 from private.recurring_occurrences o where o.entry_id=p_id);
end $function$;

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
   or (p_day>((now() at time zone 'Europe/Rome')::date+interval '6 months')::date and not exists(select 1 from private.recurring_occurrences ro where ro.entry_id=p_id)) then return;end if;
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
$function$;

CREATE OR REPLACE FUNCTION private.reschedule_appointment(p_id uuid, p_start timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.reschedule_appointment(p_id,p_start,false);
end
$function$;

CREATE OR REPLACE FUNCTION private.reschedule_appointment(p_id uuid, p_start timestamp with time zone, p_confirm_closed boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare entry public.calendar_entries; initial_barber uuid; duration interval; needs_confirmation boolean;
begin
 select * into entry from public.calendar_entries where id=p_id;
 if not found or entry.kind<>'appointment' or entry.status<>'confirmed'
   or not coalesce((private.can_manage(entry.barber_id) or private.can_manage_shop_agenda(entry.barber_id)),false) then raise exception 'ACCESS_DENIED';end if;
 initial_barber:=entry.barber_id;
 perform pg_advisory_xact_lock(hashtextextended(coalesce(entry.client_id::text,'guest:'||entry.id::text),1));
 perform pg_advisory_xact_lock(hashtextextended(entry.barber_id::text,2));
 select * into entry from public.calendar_entries where id=p_id for update;
 if not found or entry.kind<>'appointment' or entry.status<>'confirmed'
   or entry.barber_id<>initial_barber or not coalesce((private.can_manage(entry.barber_id) or private.can_manage_shop_agenda(entry.barber_id)),false) then raise exception 'ACCESS_DENIED';end if;
 perform 1 from public.services where id=entry.service_id and deleted_at is null for share;
 if not found then raise exception 'SLOT_TAKEN';end if;
 select s.requires_confirmation into needs_confirmation from private.get_reschedule_slots(p_id,(p_start at time zone 'Europe/Rome')::date) s where s.start_at=p_start;
 if not found then raise exception 'SLOT_TAKEN';end if;
 if needs_confirmation and not coalesce(p_confirm_closed,false) then raise exception 'CLOSED_DAY_CONFIRM_REQUIRED';end if;
 if p_start=entry.start_at then return;end if;
 duration:=entry.end_at-entry.start_at;
 update public.calendar_entries set start_at=p_start,end_at=p_start+duration,updated_at=now() where id=p_id;
end
$function$;
