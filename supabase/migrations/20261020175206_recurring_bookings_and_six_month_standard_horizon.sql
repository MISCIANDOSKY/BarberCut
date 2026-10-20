alter table public.app_settings add column recurring_max integer not null default 5 check(recurring_max>=0), add column recurring_unlimited boolean not null default false;
create table private.recurring_plans (
 id uuid primary key default gen_random_uuid(), anchor_id uuid not null unique,
 client_id uuid not null references auth.users(id) on delete cascade,
 barber_id uuid not null references public.barbers(id),
 service_id uuid not null references public.services(id),
 original_start timestamptz not null, every_days integer not null check(every_days in(7,14,21,28)),
 repetitions integer not null check(repetitions>0), created_at timestamptz not null default now()
);
create table private.recurring_occurrences (
 plan_id uuid not null references private.recurring_plans(id) on delete cascade,
 ordinal integer not null check(ordinal>0),
 entry_id uuid unique references public.calendar_entries(id) on delete set null,
 skipped boolean not null default false, primary key(plan_id,ordinal)
);
alter table private.recurring_plans enable row level security;
alter table private.recurring_occurrences enable row level security;
revoke all on private.recurring_plans,private.recurring_occurrences from public,anon,authenticated;
create index recurring_plans_client_idx on private.recurring_plans(client_id);
CREATE OR REPLACE FUNCTION private.recurring_available_slots(p_barber uuid, p_service uuid, p_day date)
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
select t from slots where t>now() and p_day>=(now() at time zone 'Europe/Rome')::date and not exists(select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed' and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(t,t+make_interval(mins=>duration_minutes),'[)')) order by t
$function$;

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
select t from slots where t>now() and p_day<=(now() at time zone 'Europe/Rome')::date+interval '6 months' and p_day>=(now() at time zone 'Europe/Rome')::date and not exists(select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed' and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(t,t+make_interval(mins=>duration_minutes),'[)')) order by t
$function$;

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
    or p_day>((now() at time zone 'Europe/Rome')::date+interval '6 months')::date then return;end if;
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
$function$;

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
    or not coalesce(private.can_manage(entry.barber_id),false) then raise exception 'ACCESS_DENIED';end if;
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

create function private.set_recurring_policy(p_max integer,p_unlimited boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.can_configure_shop(),false) then raise exception 'ACCESS_DENIED';end if;
 if p_max is null or p_max<0 or p_unlimited is null then raise exception 'INVALID_RECURRENCE';end if;
 update public.app_settings set recurring_max=p_max,recurring_unlimited=p_unlimited where id;
end $$;
create function private.recurring_count(p_client uuid) returns bigint language sql stable security definer set search_path='' as $$
 select count(*) from private.recurring_occurrences o join private.recurring_plans p on p.id=o.plan_id
 join public.calendar_entries e on e.id=o.entry_id where p.client_id=p_client and e.status='confirmed' and e.start_at>now()
$$;
create function private.recurring_anchor(p_anchor uuid) returns public.calendar_entries language plpgsql stable security definer set search_path='' as $$
declare e public.calendar_entries;
begin
 select * into e from public.calendar_entries where id=p_anchor;
 if auth.uid() is null or e.id is null or e.client_id is distinct from auth.uid() or e.created_by is distinct from auth.uid()
 or e.kind<>'appointment' or e.status<>'confirmed' or e.start_at<=now()
 or length(e.guest_first_name)>0 or exists(select 1 from private.recurring_occurrences o where o.entry_id=p_anchor)
 then raise exception 'ACCESS_DENIED';end if;
 return e;
end $$;
create function private.create_recurring_plan(p_anchor uuid,p_every integer,p_count integer) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.calendar_entries; config public.app_settings; existing private.recurring_plans; result uuid;
begin
 e:=private.recurring_anchor(p_anchor);
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
 select * into existing from private.recurring_plans where anchor_id=p_anchor;
 if found then
  if existing.every_days<>p_every or existing.repetitions<>p_count then raise exception 'RECURRENCE_LOCKED';end if;
  return existing.id;
 end if;
 select * into config from public.app_settings where id;
 if not config.bookings_enabled then raise exception 'BOOKINGS_DISABLED';end if;
 if p_every is null or p_every not in(7,14,21,28) or p_count is null or p_count<1 then raise exception 'INVALID_RECURRENCE';end if;
 if not config.recurring_unlimited and private.recurring_count(auth.uid())+p_count>config.recurring_max then raise exception 'RECURRENCE_LIMIT';end if;
 insert into private.recurring_plans(anchor_id,client_id,barber_id,service_id,original_start,every_days,repetitions)
 values(e.id,auth.uid(),e.barber_id,e.service_id,e.start_at,p_every,p_count) returning id into result;
 return result;
end $$;
create function private.recurring_plan_context(p_plan uuid) returns private.recurring_plans language plpgsql stable security definer set search_path='' as $$
declare p private.recurring_plans;
begin
 select * into p from private.recurring_plans where id=p_plan and client_id=auth.uid();
 if not found or auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 return p;
end $$;
create function private.list_recurring_dates(p_plan uuid,p_offset integer default 0)
 returns table(ordinal integer,expected_start timestamptz,available boolean,state text,entry_id uuid,booked_start timestamptz)
 language plpgsql stable security definer set search_path='' as $$
declare p private.recurring_plans;
begin
 p:=private.recurring_plan_context(p_plan);
 if p_offset is null or p_offset<0 then raise exception 'INVALID_RECURRENCE';end if;
 return query
 with dates as(select i,((p.original_start at time zone 'Europe/Rome')+make_interval(days=>p.every_days*i)) as local_start
 from generate_series(p_offset+1,least(p.repetitions::bigint,p_offset::bigint+25)::integer)i)
 select d.i,d.local_start at time zone 'Europe/Rome',
 ((d.local_start at time zone 'Europe/Rome') at time zone 'Europe/Rome')=d.local_start
 and exists(select 1 from private.recurring_available_slots(p.barber_id,p.service_id,d.local_start::date)s where s.start_at=d.local_start at time zone 'Europe/Rome'),
 case when o.plan_id is null then 'pending' when o.skipped then 'skipped' else 'booked' end,
 o.entry_id,e.start_at
 from dates d left join private.recurring_occurrences o on o.plan_id=p.id and o.ordinal=d.i
 left join public.calendar_entries e on e.id=o.entry_id order by d.i;
end $$;
create function private.get_recurring_slots(p_plan uuid,p_day date) returns table(start_at timestamptz)
 language plpgsql stable security definer set search_path='' as $$
declare p private.recurring_plans;
begin
 p:=private.recurring_plan_context(p_plan);
 return query select s.start_at from private.recurring_available_slots(p.barber_id,p.service_id,p_day)s
 where s.start_at>p.original_start;
end $$;
create function private.save_recurring_date(p_plan uuid,p_ordinal integer,p_start timestamptz default null) returns uuid
 language plpgsql security definer set search_path='' as $$
declare p private.recurring_plans; e public.calendar_entries; config public.app_settings; svc public.services; result uuid;
begin
 p:=private.recurring_plan_context(p_plan);
 if p_ordinal is null or p_ordinal<1 or p_ordinal>p.repetitions then raise exception 'INVALID_RECURRENCE';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
 perform pg_advisory_xact_lock(hashtextextended(p.barber_id::text,2));
 if exists(select 1 from private.recurring_occurrences o where o.plan_id=p.id and o.ordinal=p_ordinal) then
  select o.entry_id into result from private.recurring_occurrences o where o.plan_id=p.id and o.ordinal=p_ordinal;return result;
 end if;
 if p_start is null then
  insert into private.recurring_occurrences(plan_id,ordinal,skipped)values(p.id,p_ordinal,true);return null;
 end if;
 e:=private.recurring_anchor(p.anchor_id);
 if e.barber_id<>p.barber_id or e.service_id<>p.service_id then raise exception 'RECURRENCE_LOCKED';end if;
 select * into config from public.app_settings where id for share;
 if not config.bookings_enabled then raise exception 'BOOKINGS_DISABLED';end if;
 if not config.recurring_unlimited and private.recurring_count(auth.uid())>=config.recurring_max then raise exception 'RECURRENCE_LIMIT';end if;
 if not exists(select 1 from public.profiles where id=auth.uid() and deletion_requested_at is null and length(trim(first_name))>0 and length(trim(last_name))>0 and length(trim(phone))>0) then raise exception 'PROFILE_REQUIRED';end if;
 if exists(select 1 from public.terms_versions where published) and not exists(select 1 from public.terms_acceptances a join public.terms_versions t on t.id=a.terms_id where a.user_id=auth.uid() and t.published) then raise exception 'TERMS_REQUIRED';end if;
 select * into strict svc from public.services where id=p.service_id and deleted_at is null for share;
 if p_start<=p.original_start or not exists(select 1 from private.get_recurring_slots(p.id,(p_start at time zone 'Europe/Rome')::date)s where s.start_at=p_start)
 then raise exception 'SLOT_TAKEN';end if;
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by)
 values(p.barber_id,'appointment',auth.uid(),p.service_id,p_start,p_start+make_interval(mins=>svc.duration_minutes),svc.name,svc.price,auth.uid()) returning id into result;
 insert into private.recurring_occurrences(plan_id,ordinal,entry_id)values(p.id,p_ordinal,result);
 return result;
end $$;
create function private.recurring_allowance() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 return (select jsonb_build_object('maximum',recurring_max,'unlimited',recurring_unlimited,'used',private.recurring_count(auth.uid())) from public.app_settings where id);
end $$;
create function private.appointment_is_recurring(p_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if not exists(select 1 from public.calendar_entries e where e.id=p_id and(e.client_id=auth.uid() or private.can_manage(e.barber_id))) then raise exception 'ACCESS_DENIED';end if;
 return exists(select 1 from private.recurring_occurrences o where o.entry_id=p_id);
end $$;
create function public.set_recurring_policy(p_max integer,p_unlimited boolean) returns void language sql set search_path='' as $$ select private.set_recurring_policy(p_max,p_unlimited) $$;
create function public.create_recurring_plan(p_anchor uuid,p_every integer,p_count integer) returns uuid language sql set search_path='' as $$ select private.create_recurring_plan(p_anchor,p_every,p_count) $$;
create function public.list_recurring_dates(p_plan uuid,p_offset integer default 0) returns table(ordinal integer,expected_start timestamptz,available boolean,state text,entry_id uuid,booked_start timestamptz) language sql set search_path='' as $$ select * from private.list_recurring_dates(p_plan,p_offset) $$;
create function public.get_recurring_slots(p_plan uuid,p_day date) returns table(start_at timestamptz) language sql set search_path='' as $$ select * from private.get_recurring_slots(p_plan,p_day) $$;
create function public.save_recurring_date(p_plan uuid,p_ordinal integer,p_start timestamptz default null) returns uuid language sql set search_path='' as $$ select private.save_recurring_date(p_plan,p_ordinal,p_start) $$;
create function public.recurring_allowance() returns jsonb language sql set search_path='' as $$ select private.recurring_allowance() $$;
create function public.appointment_is_recurring(p_id uuid) returns boolean language sql set search_path='' as $$ select private.appointment_is_recurring(p_id) $$;
revoke all on function private.set_recurring_policy(integer,boolean) from public,anon;grant execute on function private.set_recurring_policy(integer,boolean) to authenticated;
revoke all on function public.set_recurring_policy(integer,boolean) from public,anon;grant execute on function public.set_recurring_policy(integer,boolean) to authenticated;
revoke all on function private.create_recurring_plan(uuid,integer,integer) from public,anon;grant execute on function private.create_recurring_plan(uuid,integer,integer) to authenticated;
revoke all on function public.create_recurring_plan(uuid,integer,integer) from public,anon;grant execute on function public.create_recurring_plan(uuid,integer,integer) to authenticated;
revoke all on function private.list_recurring_dates(uuid,integer) from public,anon;grant execute on function private.list_recurring_dates(uuid,integer) to authenticated;
revoke all on function public.list_recurring_dates(uuid,integer) from public,anon;grant execute on function public.list_recurring_dates(uuid,integer) to authenticated;
revoke all on function private.get_recurring_slots(uuid,date) from public,anon;grant execute on function private.get_recurring_slots(uuid,date) to authenticated;
revoke all on function public.get_recurring_slots(uuid,date) from public,anon;grant execute on function public.get_recurring_slots(uuid,date) to authenticated;
revoke all on function private.save_recurring_date(uuid,integer,timestamptz) from public,anon;grant execute on function private.save_recurring_date(uuid,integer,timestamptz) to authenticated;
revoke all on function public.save_recurring_date(uuid,integer,timestamptz) from public,anon;grant execute on function public.save_recurring_date(uuid,integer,timestamptz) to authenticated;
revoke all on function private.recurring_allowance() from public,anon;grant execute on function private.recurring_allowance() to authenticated;
revoke all on function public.recurring_allowance() from public,anon;grant execute on function public.recurring_allowance() to authenticated;
revoke all on function private.appointment_is_recurring(uuid) from public,anon;grant execute on function private.appointment_is_recurring(uuid) to authenticated;
revoke all on function public.appointment_is_recurring(uuid) from public,anon;grant execute on function public.appointment_is_recurring(uuid) to authenticated;
revoke all on function private.recurring_available_slots(uuid,uuid,date) from public,anon,authenticated;
revoke all on function private.recurring_count(uuid) from public,anon,authenticated;
revoke all on function private.recurring_anchor(uuid) from public,anon,authenticated;
revoke all on function private.recurring_plan_context(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.book_appointment(p_barber uuid, p_service uuid, p_start timestamp with time zone, p_client uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c uuid:=coalesce(p_client,auth.uid()); svc public.services; result uuid; staff boolean:=private.can_manage(p_barber);
begin
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

CREATE OR REPLACE FUNCTION private.book_manual_appointment(p_barber uuid, p_service uuid, p_start timestamp with time zone, p_first_name text, p_last_name text, p_phone text DEFAULT ''::text, p_confirm_closed boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare svc public.services; result uuid; matches uuid[]; linked_client uuid; phone_key text; needs_confirmation boolean;
begin
  if not coalesce(private.can_manage(p_barber),false) then raise exception 'ACCESS_DENIED';end if;
  if p_first_name is null or p_last_name is null
     or length(trim(p_first_name)) not between 1 and 120
     or length(trim(p_last_name)) not between 1 and 120
     or length(coalesce(p_phone,''))>40 then raise exception 'GUEST_NAME_REQUIRED';end if;
  phone_key:=private.booking_phone_key(p_phone);
  if phone_key is not null then
    select array_agg(p.id) into matches
    from public.profiles p join auth.users a on a.id=p.id
    where p.deletion_requested_at is null
      and (a.banned_until is null or a.banned_until<=now())
      and private.booking_phone_key(p.phone)=phone_key;
    if coalesce(cardinality(matches),0)>1 then raise exception 'PHONE_MATCH_AMBIGUOUS';end if;
    linked_client:=matches[1];
  end if;
  if linked_client is not null then
    perform pg_advisory_xact_lock(hashtextextended(linked_client::text,1));
    -- Lock the matching profile and recheck its number before associating the booking.
    perform 1 from public.profiles p where p.id=linked_client
      and p.deletion_requested_at is null and private.booking_phone_key(p.phone)=phone_key for share;
    if not found then raise exception 'PHONE_MATCH_CHANGED';end if;
    if(select count(*) from public.calendar_entries where client_id=linked_client and kind='appointment' and status='confirmed' and start_at>now() and not exists(select 1 from private.recurring_occurrences ro where ro.entry_id=calendar_entries.id))>=5 then
      raise exception 'LIMIT_FIVE';
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
  select * into strict svc from public.services where id=p_service and deleted_at is null for share;
  select s.requires_confirmation into needs_confirmation
    from private.get_manual_booking_slots(p_barber,p_service,(p_start at time zone 'Europe/Rome')::date) s
    where s.start_at=p_start;
  if not found then raise exception 'SLOT_TAKEN';end if;
  if needs_confirmation and not coalesce(p_confirm_closed,false) then
    raise exception 'CLOSED_DAY_CONFIRM_REQUIRED';
  end if;
  insert into public.calendar_entries(
    barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by,guest_first_name,guest_last_name,guest_phone
  ) values(
    p_barber,'appointment',linked_client,p_service,p_start,p_start+make_interval(mins=>svc.duration_minutes),
    svc.name,svc.price,auth.uid(),trim(p_first_name),trim(p_last_name),trim(coalesce(p_phone,''))
  ) returning id into result;
  return result;
end
$function$;
