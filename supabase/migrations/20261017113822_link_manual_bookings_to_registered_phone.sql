-- Exact canonical phone matching only inside the staff booking RPC.
create or replace function private.booking_phone_key(p_phone text)
returns text
language plpgsql immutable
set search_path=''
as $function$
declare cleaned text:=trim(coalesce(p_phone,'')); digits text;
begin
  if cleaned='' or cleaned !~ '^[+0-9 ()./-]+$' then return null; end if;
  digits:=regexp_replace(cleaned,'[^0-9]','','g');
  if cleaned like '+%' then
    if position('+' in substring(cleaned from 2))>0 then return null; end if;
  elsif digits like '00%' then
    digits:=substring(digits from 3);
  else
    -- Italian local numbers use +39; retain the significant zero of landlines.
    if not (digits like '39%' and length(digits)>10) then digits:='39'||digits; end if;
  end if;
  if length(digits) not between 8 and 15 or digits like '0%' then return null; end if;
  return digits;
end
$function$;
revoke all on function private.booking_phone_key(text) from public,anon,authenticated;

create or replace function private.book_guest_appointment(
  p_barber uuid,p_service uuid,p_start timestamptz,p_first_name text,p_last_name text,p_phone text default ''
)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare svc public.services; result uuid; matches uuid[]; linked_client uuid; phone_key text;
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
  if not exists(select 1 from public.get_available_slots(p_barber,p_service,(p_start at time zone 'Europe/Rome')::date) a where a.start_at=p_start) then raise exception 'SLOT_TAKEN';end if;
  insert into public.calendar_entries(
    barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by,guest_first_name,guest_last_name,guest_phone
  ) values(
    p_barber,'appointment',linked_client,p_service,p_start,p_start+make_interval(mins=>svc.duration_minutes),
    svc.name,svc.price,auth.uid(),trim(p_first_name),trim(p_last_name),trim(coalesce(p_phone,''))
  ) returning id into result;
  return result;
end
$function$;
