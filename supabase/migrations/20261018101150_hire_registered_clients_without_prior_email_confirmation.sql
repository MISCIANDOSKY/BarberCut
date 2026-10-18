create or replace function private.resolve_barber_hire_candidate(p_email text,p_phone text)
returns uuid language plpgsql security definer set search_path='' as $function$
declare candidates uuid[]; phone_key text;
begin
 if not coalesce(private.can_configure_shop(),false) then raise exception 'ACCESS_DENIED';end if;
 phone_key:=private.booking_phone_key(p_phone);
 if p_email is null or length(trim(p_email)) not between 3 and 320 or p_phone is null or length(p_phone)>40 or phone_key is null then
   raise exception 'HIRE_ACCOUNT_UNAVAILABLE';
 end if;
 select array_agg(a.id) into candidates
 from auth.users a join public.profiles p on p.id=a.id join public.user_roles r on r.user_id=a.id
 where lower(trim(a.email))=lower(trim(p_email))
   and private.booking_phone_key(p.phone)=phone_key
   and a.deleted_at is null
   and (a.banned_until is null or a.banned_until<=now())
   and p.deletion_requested_at is null and r.role='client'
   and not exists(select 1 from public.barbers b where b.user_id=a.id and b.deleted_at is null);
 if coalesce(cardinality(candidates),0)<>1 then raise exception 'HIRE_ACCOUNT_UNAVAILABLE';end if;
 return candidates[1];
end
$function$;
