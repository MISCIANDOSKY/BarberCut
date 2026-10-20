begin;
do $test$
declare sh uuid:=gen_random_uuid();ad uuid:=gen_random_uuid();normal uuid:=gen_random_uuid();lead uuid:=gen_random_uuid();client uuid:=gen_random_uuid();
 ss uuid:=gen_random_uuid();sa uuid:=gen_random_uuid();sn uuid:=gen_random_uuid();sl uuid:=gen_random_uuid();sc uuid:=gen_random_uuid();n integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)values
 (sh,'no-otp-shop@example.invalid',now(),'{}'),(ad,'no-otp-admin@example.invalid',now(),'{}'),
 (normal,'no-otp-normal@example.invalid',now(),'{}'),(lead,'no-otp-lead@example.invalid',now(),'{}'),(client,'no-otp-client@example.invalid',now(),'{}');
 update public.user_roles set role='shop'where user_id=sh;
 update public.user_roles set role='admin'where user_id=ad;
 update public.user_roles set role='barber'where user_id=normal;
 update public.user_roles set role='barber_admin'where user_id=lead;
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after)values
 (ss,sh,now(),now(),now()+interval '1 day'),(sa,ad,now(),now(),now()+interval '1 day'),
 (sn,normal,now(),now(),now()+interval '1 day'),(sl,lead,now(),now(),now()+interval '1 day'),(sc,client,now(),now(),now()+interval '1 day');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',sh,'role','authenticated','session_id',ss::text)::text,true);
 set local role authenticated;
 if not public.staff_session_status()then raise exception 'Shop still requires OTP';end if;
 perform public.shop_barbers();
 reset role;
 perform public.staff_authorize_session(sh,ss::text);
 if exists(select 1 from private.staff_sessions where user_id=sh)then raise exception 'Shop still creates OTP stamp';end if;
 -- Even a legacy stamp must not bypass active Auth session checks for Shop.
 insert into private.staff_sessions(user_id,session_id,otp_hash,expires_at,verified_until)values(sh,ss::text,'test-only',now(),now()+interval '8 hours');
 update auth.sessions set not_after=now()-interval '1 second'where id=ss;
 if public.staff_session_status()then raise exception 'Expired shop session accepted';end if;
 update auth.sessions set not_after=now()+interval '1 day'where id=ss;
 update auth.users set banned_until=now()+interval '1 day'where id=sh;
 if public.staff_session_status()then raise exception 'Banned shop accepted';end if;
 update auth.users set banned_until=null,email_confirmed_at=null where id=sh;
 if public.staff_session_status()then raise exception 'Unconfirmed registration accepted';end if;
 update auth.users set email_confirmed_at=now(),deleted_at=now()where id=sh;
 if public.staff_session_status()then raise exception 'Deleted shop accepted';end if;
 update auth.users set deleted_at=null where id=sh;
 delete from auth.sessions where id=ss;
 if public.staff_session_status()then raise exception 'Revoked shop session accepted';end if;
 insert into auth.sessions(id,user_id,not_after)values(ss,sh,now()+interval '1 day');
 if not public.staff_session_status()then raise exception 'Valid shop cannot reconnect';end if;
 delete from private.staff_sessions where user_id=sh;
 update public.user_roles set role='admin'where user_id=sh;
 if public.staff_session_status()then raise exception 'Shop exception leaked into Admin';end if;
 update public.user_roles set role='shop'where user_id=sh;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',sh,'role','authenticated','session_id',sa::text)::text,true);
 if public.staff_session_status()then raise exception 'Other account session accepted';end if;
 -- All other roles still need their existing verification path.
 for n in 1..4 loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',case n when 1 then ad when 2 then normal when 3 then lead else client end,
   'role','authenticated','session_id',(case n when 1 then sa when 2 then sn when 3 then sl else sc end)::text)::text,true);
  if public.staff_session_status()then raise exception 'Other role exempted %',n;end if;
 end loop;
 perform public.staff_authorize_session(ad,sa::text);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id',sa::text)::text,true);
 if not public.staff_session_status()then raise exception 'Admin OTP regressed';end if;
 perform public.staff_authorize_session(normal,sn::text);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',normal,'role','authenticated','session_id',sn::text)::text,true);
 if not public.staff_session_status()then raise exception 'Barber OTP regressed';end if;
 perform public.staff_authorize_session(lead,sl::text);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id',sl::text)::text,true);
 if not public.staff_session_status()then raise exception 'Lead OTP regressed';end if;
end $test$;
select 'PASS Shop uses active Auth session without extra OTP; other roles unchanged; expired/revoked/banned/deleted/mismatched sessions denied' result;
rollback;