CREATE OR REPLACE FUNCTION private.dispatch_inactivity_notices()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n record;secret text;dispatched integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barbercut-inactivity-notices',0)) then return 0;end if;
 perform private.queue_inactivity_notices();
 -- Clear presentation context left behind by a timed-out sender.
 update auth.users a set raw_user_meta_data=raw_user_meta_data-'barbercut_warning_days'-'barbercut_warning_notice'
 where exists(select 1 from private.inactivity_notices stale join private.inactivity_cycles c on c.id=stale.cycle_id where c.user_id=a.id and a.raw_user_meta_data->>'barbercut_warning_notice'=stale.id::text and (stale.token_expires_at<=now() or stale.status in('sent','cancelled','failed')));
 for n in select id from private.inactivity_notices where status in('pending','failed','queued','sending') and attempts<6 and next_attempt_at<=now() order by created_at limit 20 for update skip locked
 loop
  secret:=gen_random_uuid()::text||gen_random_uuid()::text;
  update private.inactivity_notices set status='queued',attempts=attempts+1,token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes',next_attempt_at=now()+interval '30 minutes' where id=n.id;
  perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/inactivity-warning',headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('notice_id',n.id,'token',secret),timeout_milliseconds:=60000);
  dispatched:=dispatched+1;
 end loop;
 return dispatched;
end $function$
;
CREATE OR REPLACE FUNCTION private.dispatch_registration_emails()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n record;secret text;amount integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barbercut-registration-emails',0)) then return 0;end if;
 update auth.users a set raw_user_meta_data=raw_user_meta_data-'barbercut_approved'-'barbercut_approval_notice'
 where exists(select 1 from private.registration_emails stale where stale.user_id=a.id and a.raw_user_meta_data->>'barbercut_approval_notice'=stale.id::text and (stale.token_expires_at<=now() or stale.status in('sent','cancelled','failed')));
 for n in select id from private.registration_emails where status in('pending','failed','queued','sending') and attempts<6 and next_attempt_at<=now() order by next_attempt_at limit 10 for update skip locked
 loop
  secret:=gen_random_uuid()::text||gen_random_uuid()::text;
  update private.registration_emails set status='queued',attempts=attempts+1,token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes',next_attempt_at=now()+interval '30 minutes' where id=n.id;
  perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/registration-approved',headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('notice_id',n.id,'token',secret),timeout_milliseconds:=60000);
  amount:=amount+1;
 end loop;
 return amount;
end $function$
;
