begin;
do $test$
declare u uuid; phone text; prefix text;
begin
 foreach phone in array array['','123456789','12345678901','abcdefghij','333 1234567']
 loop
  u:=gen_random_uuid();
  begin
   insert into auth.users(id,aud,email,raw_user_meta_data) values(u,'authenticated',u::text||'@phone.invalid',jsonb_build_object('phone','+39'||phone,'phone_country_code','+39','phone_national',phone));
   raise exception 'Invalid signup phone accepted';
  exception when raise_exception then if sqlerrm<>'REGISTRATION_PHONE_INVALID' then raise;end if;end;
  if exists(select 1 from public.profiles where id=u) then raise exception 'Invalid signup left profile';end if;
 end loop;
 foreach prefix in array array['','39','+','+0','+1234','+ab']
 loop
  u:=gen_random_uuid();
  begin
   insert into auth.users(id,aud,email,raw_user_meta_data) values(u,'authenticated',u::text||'@phone.invalid',jsonb_build_object('phone',prefix||'3331234567','phone_country_code',prefix,'phone_national','3331234567'));
   raise exception 'Invalid prefix accepted';
  exception when raise_exception then if sqlerrm<>'REGISTRATION_PHONE_INVALID' then raise;end if;end;
 end loop;
 u:=gen_random_uuid();
 begin
  insert into auth.users(id,aud,email,raw_user_meta_data) values(u,'authenticated',u::text||'@phone.invalid','{}');
  raise exception 'Missing phone accepted';
 exception when raise_exception then if sqlerrm<>'REGISTRATION_PHONE_INVALID' then raise;end if;end;
 u:=gen_random_uuid();
 begin
  insert into auth.users(id,aud,email,raw_user_meta_data) values(u,'authenticated',u::text||'@phone.invalid','{"phone":"+393331234568","phone_country_code":"+39","phone_national":"3331234567"}');
  raise exception 'Mismatched combined phone accepted';
 exception when raise_exception then if sqlerrm<>'REGISTRATION_PHONE_INVALID' then raise;end if;end;
 foreach prefix in array array['+39','+1','+358']
 loop
  u:=gen_random_uuid();
  insert into auth.users(id,aud,email,raw_user_meta_data) values(u,'authenticated',u::text||'@phone.invalid',jsonb_build_object('phone',prefix||'3331234567','phone_country_code',prefix,'phone_national','3331234567','first_name','Test','last_name','Cliente'));
  if not exists(select 1 from public.profiles p where p.id=u and p.phone=prefix||'3331234567') then raise exception 'Combined phone not saved';end if;
  if not exists(select 1 from public.user_roles where user_id=u and role='client') then raise exception 'Client role missing';end if;
  if not exists(select 1 from private.client_memberships where user_id=u) then raise exception 'Membership missing';end if;
 end loop;
u:=gen_random_uuid();
 insert into auth.users(id,aud,email,raw_user_meta_data) values(u,'authenticated',u::text||'@phone.invalid','{"phone":"3331234567"}');
 if not exists(select 1 from public.profiles p where p.id=u and p.phone='+393331234567') then raise exception 'Cached registration phone not normalized';end if;
end $test$;
select 'registration_phone_prefix_test_passed' as result;
rollback;
