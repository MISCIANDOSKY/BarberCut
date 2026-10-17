begin;
-- These fixtures model clients already admitted to the barber shop.
update public.app_settings set require_user_approval=false where id;
do $test$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();ad uuid:=gen_random_uuid();barb uuid:=gen_random_uuid();overdue uuid:=gen_random_uuid();ca uuid;cb uuid;cc uuid;co uuid;notice uuid;secret text:=gen_random_uuid()::text||gen_random_uuid()::text;othersecret text:=gen_random_uuid()::text||gen_random_uuid()::text;j jsonb;count_before integer;
begin
 insert into auth.users(id,email,created_at,last_sign_in_at,raw_user_meta_data) values
 (a,'warning-30@example.invalid',now()-interval '200 days',now()-interval '90 days','{"first_name":"Test30"}'),
 (b,'warning-15@example.invalid',now()-interval '200 days',now()-interval '105 days','{}'),
 (c,'warning-7@example.invalid',now()-interval '200 days',now()-interval '113 days','{"keep_me":"yes"}'),
 (ad,'warning-admin@example.invalid',now()-interval '200 days',now()-interval '150 days','{}'),
 (barb,'warning-barber@example.invalid',now()-interval '200 days',now()-interval '150 days','{}'),
 (overdue,'warning-overdue@example.invalid',now()-interval '200 days',now()-interval '150 days','{}');
 update public.user_roles set role='admin' where user_id=ad;
 update public.user_roles set role='barber' where user_id=barb;
 insert into private.inactivity_cycles(user_id,activity_at,inactive_days,disable_after) values
 (b,now()-interval '105 days',120,now()+interval '15 days'),
 (c,now()-interval '113 days',120,now()+interval '7 days');
 perform private.queue_inactivity_notices();
 if exists(select 1 from private.inactivity_cycles where user_id in(ad,barb)) then raise exception 'staff warning created';end if;
 select id into ca from private.inactivity_cycles where user_id=a;
 select id into cb from private.inactivity_cycles where user_id=b;
 select id into cc from private.inactivity_cycles where user_id=c;
 select id into co from private.inactivity_cycles where user_id=overdue;
 if not exists(select 1 from private.inactivity_notices where cycle_id=ca and lead_days=30) or not exists(select 1 from private.inactivity_notices where cycle_id=cb and lead_days=15) or not exists(select 1 from private.inactivity_notices where cycle_id=cc and lead_days=7) then raise exception 'warning schedule incorrect';end if;
 if (select disable_after from private.inactivity_cycles where id=co)<now()+interval '30 days' then raise exception 'overdue client lacks grace';end if;
 select count(*) into count_before from private.inactivity_notices;
 perform private.queue_inactivity_notices();
 if (select count(*) from private.inactivity_notices)<>count_before then raise exception 'duplicate warning';end if;
 select id into notice from private.inactivity_notices where cycle_id=cc and lead_days=7;
 update private.inactivity_notices set status='queued',token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes' where id=notice;
 if private.claim_inactivity_notice(notice,othersecret) is not null then raise exception 'forged token accepted';end if;
 set local role service_role;
 j:=public.claim_inactivity_notice(notice,secret);
 reset role;
 if (j->>'days')::integer<>7 then raise exception 'final notice missing days';end if;
 if private.claim_inactivity_notice(notice,secret) is not null then raise exception 'claim replay accepted';end if;
 if not exists(select 1 from auth.users where id=c and raw_user_meta_data->>'barbercut_warning_days'='7') then raise exception 'email context missing';end if;
 perform private.finish_inactivity_notice(notice,secret,true);
 if not exists(select 1 from auth.users where id=c and raw_user_meta_data->>'keep_me'='yes' and not raw_user_meta_data?'barbercut_warning_days') then raise exception 'context cleanup incorrect';end if;
 if exists(select 1 from private.user_activity where user_id=c) then raise exception 'sending warning reset inactivity';end if;
 perform private.run_daily_maintenance();
 if exists(select 1 from private.inactive_accounts where user_id in(a,b,c,overdue)) then raise exception 'early disabling before notice grace';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
 set local role authenticated;
 perform public.record_activity();
 begin perform public.claim_inactivity_notice(notice,secret);raise exception 'client can claim notices';exception when insufficient_privilege then null;end;
 reset role;
 perform private.queue_inactivity_notices();
 if exists(select 1 from private.inactivity_notices where cycle_id=ca and status<>'cancelled') then raise exception 'login did not cancel old warning';end if;
 select id into notice from private.inactivity_notices where cycle_id=cb;
 update private.inactivity_notices set status='queued',token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes' where id=notice;
 update public.user_roles set role='admin' where user_id=b;
 j:=private.claim_inactivity_notice(notice,secret);
 if j->>'cancelled'<>'true' then raise exception 'role promotion not checked before sending';end if;
end $test$;
rollback;
