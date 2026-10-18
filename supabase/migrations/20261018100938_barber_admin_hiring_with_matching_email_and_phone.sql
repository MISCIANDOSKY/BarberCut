create function private.resolve_barber_hire_candidate(p_email text,p_phone text)
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
   and a.email_confirmed_at is not null and a.deleted_at is null
   and (a.banned_until is null or a.banned_until<=now())
   and p.deletion_requested_at is null and r.role='client'
   and not exists(select 1 from public.barbers b where b.user_id=a.id and b.deleted_at is null);
 if coalesce(cardinality(candidates),0)<>1 then raise exception 'HIRE_ACCOUNT_UNAVAILABLE';end if;
 return candidates[1];
end
$function$;
revoke all on function private.resolve_barber_hire_candidate(text,text) from public,anon,authenticated;

create function private.check_barber_hire_candidate(p_email text,p_phone text)
returns boolean language plpgsql security definer set search_path='' as $function$
begin
 perform private.resolve_barber_hire_candidate(p_email,p_phone);
 return true;
end
$function$;
create function public.check_barber_hire_candidate(p_email text,p_phone text)
returns boolean language sql security invoker set search_path='' as $function$
 select private.check_barber_hire_candidate(p_email,p_phone)
$function$;
revoke all on function private.check_barber_hire_candidate(text,text),public.check_barber_hire_candidate(text,text) from public,anon;
grant execute on function private.check_barber_hire_candidate(text,text),public.check_barber_hire_candidate(text,text) to authenticated;

create function private.hire_barber(p_email text,p_phone text,p_name text)
returns uuid language plpgsql security definer set search_path='' as $function$
declare candidate uuid; created_barber uuid;
begin
 if not coalesce(private.can_configure_shop(),false) then raise exception 'ACCESS_DENIED';end if;
 if p_name is null or length(trim(p_name)) not between 1 and 160 then raise exception 'INVALID_BARBER_NAME';end if;
 candidate:=private.resolve_barber_hire_candidate(p_email,p_phone);
 perform pg_advisory_xact_lock(hashtextextended(candidate::text,1));
 -- Lock the source records, then repeat both checks at the final save.
 perform 1 from auth.users where id=candidate for update;
 perform 1 from public.profiles where id=candidate for update;
 perform 1 from public.user_roles where user_id=candidate for update;
 if candidate is distinct from private.resolve_barber_hire_candidate(p_email,p_phone) then
   raise exception 'HIRE_ACCOUNT_UNAVAILABLE';
 end if;
 insert into public.barbers(name,user_id) values(trim(p_name),candidate) returning id into created_barber;
 -- Existing triggers assign the regular barber role and seed active services atomically.
 return created_barber;
exception when unique_violation then
 raise exception 'HIRE_ACCOUNT_UNAVAILABLE';
end
$function$;
create function public.hire_barber(p_email text,p_phone text,p_name text)
returns uuid language sql security invoker set search_path='' as $function$
 select private.hire_barber(p_email,p_phone,p_name)
$function$;
revoke all on function private.hire_barber(text,text,text),public.hire_barber(text,text,text) from public,anon;
grant execute on function private.hire_barber(text,text,text),public.hire_barber(text,text,text) to authenticated;
notify pgrst,'reload schema';
