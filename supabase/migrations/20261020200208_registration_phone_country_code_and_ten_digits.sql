CREATE OR REPLACE FUNCTION private.new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prefix text; national text; full_phone text; raw_phone text;
begin
 if new.aud='authenticated' then
  raw_phone:=coalesce(new.raw_user_meta_data->>'phone','');
  if new.raw_user_meta_data ? 'phone_country_code' or new.raw_user_meta_data ? 'phone_national' then
   prefix:=coalesce(new.raw_user_meta_data->>'phone_country_code','');
   national:=coalesce(new.raw_user_meta_data->>'phone_national','');
   if raw_phone<>prefix||national then raise exception 'REGISTRATION_PHONE_INVALID';end if;
  elsif raw_phone ~ '^[0-9]{10}$' then
   prefix:='+39'; national:=raw_phone;
  elsif raw_phone ~ '^\+[1-9][0-9]{10,12}$' then
   prefix:=left(raw_phone,length(raw_phone)-10);national:=right(raw_phone,10);
  else raise exception 'REGISTRATION_PHONE_INVALID';
  end if;
  if prefix !~ '^\+[1-9][0-9]{0,2}$' or national !~ '^[0-9]{10}$' then raise exception 'REGISTRATION_PHONE_INVALID';end if;
  full_phone:=prefix||national;
 end if;
 insert into public.profiles(id,first_name,last_name,phone) values(new.id,coalesce(new.raw_user_meta_data->>'first_name',''),coalesce(new.raw_user_meta_data->>'last_name',''),coalesce(full_phone,new.raw_user_meta_data->>'phone',''));
 insert into public.user_roles(user_id) values(new.id);
 insert into private.client_memberships(user_id,status) values(new.id,case when coalesce((select require_user_approval from public.app_settings where id),true) then 'pending' else 'approved' end);
 return new;
end $function$
;
