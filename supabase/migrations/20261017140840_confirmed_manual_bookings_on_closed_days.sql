-- Manual bookings can override calendar closures only after explicit staff confirmation.
create or replace function private.manual_day_closed(p_barber uuid,p_day date)
returns boolean language sql stable set search_path='' as $function$
 select private.is_holiday(p_day)
 or exists(select 1 from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day and e.closed)
 or not exists(
   select 1 from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day and not e.closed
   union all
   select 1 from public.working_hours w where w.barber_id=p_barber and w.weekday=extract(dow from p_day)
     and not exists(select 1 from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day)
 );
$function$;
revoke all on function private.manual_day_closed(uuid,date) from public,anon,authenticated;

create or replace function private.get_manual_booking_slots(p_barber uuid,p_service uuid,p_day date)
returns table(start_at timestamptz,requires_confirmation boolean)
language plpgsql stable security definer set search_path='' as $function$
declare duration integer; closed_day boolean;
begin
 if not coalesce(private.can_manage(p_barber),false) then raise exception 'ACCESS_DENIED';end if;
 select s.duration_minutes into duration
 from public.services s join public.barber_services bs on bs.service_id=s.id join public.barbers b on b.id=bs.barber_id
 where s.id=p_service and b.id=p_barber and s.active and b.active and s.deleted_at is null and b.deleted_at is null;
 if not found then return;end if;
 if p_day is null or p_day<(now() at time zone 'Europe/Rome')::date
    or p_day>((now() at time zone 'Europe/Rome')::date+interval '3 months')::date then return;end if;
 closed_day:=private.manual_day_closed(p_barber,p_day);
 if not closed_day then
   return query select s.start_at,false from public.get_available_slots(p_barber,p_service,p_day) s;
   return;
 end if;
 return query
 select g.t,true
 from generate_series(p_day::timestamp at time zone 'Europe/Rome',
   ((p_day+1)::timestamp at time zone 'Europe/Rome')-make_interval(mins=>duration),
   interval '15 minutes') g(t)
 where g.t>now() and not exists(
   select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed'
   and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(g.t,g.t+make_interval(mins=>duration),'[)')
 ) order by g.t;
end $function$;
revoke all on function private.get_manual_booking_slots(uuid,uuid,date) from public,anon;
grant execute on function private.get_manual_booking_slots(uuid,uuid,date) to authenticated;
create or replace function public.get_manual_booking_slots(p_barber uuid,p_service uuid,p_day date)
returns table(start_at timestamptz,requires_confirmation boolean)
language sql security invoker set search_path='' as $function$
 select * from private.get_manual_booking_slots(p_barber,p_service,p_day)
$function$;
revoke all on function public.get_manual_booking_slots(uuid,uuid,date) from public,anon;
grant execute on function public.get_manual_booking_slots(uuid,uuid,date) to authenticated;

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
    if(select count(*) from public.calendar_entries where client_id=linked_client and kind='appointment' and status='confirmed' and start_at>now())>=5 then
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
revoke all on function private.book_manual_appointment(uuid,uuid,timestamptz,text,text,text,boolean) from public,anon;
grant execute on function private.book_manual_appointment(uuid,uuid,timestamptz,text,text,text,boolean) to authenticated;
create or replace function public.book_manual_appointment(
 p_barber uuid,p_service uuid,p_start timestamptz,p_first_name text,p_last_name text,p_phone text default '',p_confirm_closed boolean default false
)
returns uuid language sql security invoker set search_path='' as $function$
 select private.book_manual_appointment(p_barber,p_service,p_start,p_first_name,p_last_name,p_phone,p_confirm_closed)
$function$;
revoke all on function public.book_manual_appointment(uuid,uuid,timestamptz,text,text,text,boolean) from public,anon;
grant execute on function public.book_manual_appointment(uuid,uuid,timestamptz,text,text,text,boolean) to authenticated;

-- Keep older clients safe: six-argument guest bookings never silently override a closure.
create or replace function private.book_guest_appointment(
 p_barber uuid,p_service uuid,p_start timestamptz,p_first_name text,p_last_name text,p_phone text default ''
)
returns uuid language sql security invoker set search_path='' as $function$
 select private.book_manual_appointment(p_barber,p_service,p_start,p_first_name,p_last_name,p_phone,false)
$function$;
notify pgrst,'reload schema';
