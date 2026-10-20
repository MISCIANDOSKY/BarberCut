begin;
update public.app_settings set require_user_approval=false where id;
update private.maintenance_settings set disable_inactive=true,inactive_days=120,delete_old_appointments=false where id;
do $test$
declare ad uuid:=gen_random_uuid();barb uuid:=gen_random_uuid();lead uuid:=gen_random_uuid();shop uuid:=gen_random_uuid();client uuid:=gen_random_uuid();promoted uuid:=gen_random_uuid();uid uuid;cycle uuid;notice uuid;secret text:=gen_random_uuid()::text;payload jsonb;
begin
 insert into auth.users(id,email,created_at,last_sign_in_at,raw_user_meta_data)values
 (ad,'inactivity-exempt-admin@example.invalid',now()-interval '200 days',now()-interval '180 days','{}'),
 (barb,'inactivity-exempt-barber@example.invalid',now()-interval '200 days',now()-interval '180 days','{}'),
 (lead,'inactivity-exempt-lead@example.invalid',now()-interval '200 days',now()-interval '180 days','{}'),
 (shop,'inactivity-exempt-shop@example.invalid',now()-interval '200 days',now()-interval '180 days','{}'),
 (client,'inactivity-client-control@example.invalid',now()-interval '200 days',now()-interval '180 days','{}'),
 (promoted,'inactivity-promoted-shop@example.invalid',now()-interval '200 days',now()-interval '180 days','{}');
 update public.user_roles set role='admin'where user_id=ad;
 update public.user_roles set role='barber'where user_id=barb;
 update public.user_roles set role='barber_admin'where user_id=lead;
 update public.user_roles set role='shop'where user_id=shop;
 if exists(select 1 from private.inactivity_candidates() where user_id in(ad,barb,lead,shop))then raise exception 'Exempt role became inactivity candidate';end if;
 if not exists(select 1 from private.inactivity_candidates()where user_id=client)then raise exception 'Client inactivity selection broken';end if;
 perform private.queue_inactivity_notices();
 if exists(select 1 from private.inactivity_cycles where user_id in(ad,barb,lead,shop))then raise exception 'Warning created for exempt role';end if;
 -- An old client warning must not disable an account after promotion to an exempt role.
 foreach uid in array array[ad,barb,lead,shop] loop
  insert into private.inactivity_cycles(user_id,activity_at,inactive_days,disable_after)values(uid,now()-interval '180 days',120,now()-interval '1 day')returning id into cycle;
  insert into private.inactivity_notices(cycle_id,lead_days,status,sent_at)values(cycle,7,'sent',now()-interval '8 days');
 end loop;
 select id into cycle from private.inactivity_cycles where user_id=client;
 update private.inactivity_cycles set disable_after=now()-interval '1 day'where id=cycle;
 insert into private.inactivity_notices(cycle_id,lead_days,status,sent_at)values(cycle,7,'sent',now()-interval '8 days');
 perform private.run_daily_maintenance();
 if exists(select 1 from private.inactive_accounts where user_id in(ad,barb,lead,shop))then raise exception 'Exempt account disabled';end if;
 if exists(select 1 from auth.users where id in(ad,barb,lead,shop)and banned_until>now())then raise exception 'Exempt account banned';end if;
 if not exists(select 1 from private.inactive_accounts where user_id=client)then raise exception 'Eligible client not disabled after final grace';end if;
 -- Recheck the current role before sending a queued warning.
 select id into cycle from private.inactivity_cycles where user_id=promoted;
 select id into notice from private.inactivity_notices where cycle_id=cycle;
 update private.inactivity_notices set status='queued',token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes'where id=notice;
 update public.user_roles set role='shop'where user_id=promoted;
 payload:=private.claim_inactivity_notice(notice,secret);
 if payload->>'cancelled' is distinct from 'true'then raise exception 'Queued warning survived Barberia promotion';end if;
 perform private.queue_inactivity_notices();
 if exists(select 1 from private.inactivity_notices n join private.inactivity_cycles c on c.id=n.cycle_id where c.user_id=promoted and n.status in('pending','queued','failed'))then raise exception 'Pending Barberia warning retained';end if;
end $test$;
select 'PASS Admin, Barbiere, Barbiere Admin and Barberia excluded; client control, stale warnings and promotion verified' as result;
rollback;
