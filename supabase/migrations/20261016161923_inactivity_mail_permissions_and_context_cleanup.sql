grant usage on schema private to service_role;
create or replace function private.record_activity() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 perform 1 from auth.users where id=auth.uid() and deleted_at is null and (banned_until is null or banned_until<=now()) for share;
 if not found then return;end if;
 insert into private.user_activity(user_id,last_seen_at) values(auth.uid(),now())
 on conflict(user_id) do update set last_seen_at=excluded.last_seen_at
 where private.user_activity.last_seen_at<now()-interval '15 minutes';
 update auth.users set raw_user_meta_data=raw_user_meta_data-'barbercut_warning_days'-'barbercut_warning_notice'
 where id=auth.uid() and raw_user_meta_data?'barbercut_warning_notice';
end $$;
create or replace function private.dispatch_inactivity_notices() returns integer language plpgsql security definer set search_path='' as $$
declare n record;secret text;dispatched integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barbercut-inactivity-notices',0)) then return 0;end if;
 perform private.queue_inactivity_notices();
 -- Clear presentation context left behind by a timed-out sender.
 update auth.users a set raw_user_meta_data=raw_user_meta_data-'barbercut_warning_days'-'barbercut_warning_notice'
 where exists(select 1 from private.inactivity_notices n join private.inactivity_cycles c on c.id=n.cycle_id where c.user_id=a.id and a.raw_user_meta_data->>'barbercut_warning_notice'=n.id::text and (n.token_expires_at<=now() or n.status in('sent','cancelled','failed')));
 for n in select id from private.inactivity_notices where status in('pending','failed','queued','sending') and attempts<6 and next_attempt_at<=now() order by created_at limit 20 for update skip locked
 loop
  secret:=gen_random_uuid()::text||gen_random_uuid()::text;
  update private.inactivity_notices set status='queued',attempts=attempts+1,token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes',next_attempt_at=now()+interval '30 minutes' where id=n.id;
  perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/inactivity-warning',headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('notice_id',n.id,'token',secret),timeout_milliseconds:=60000);
  dispatched:=dispatched+1;
 end loop;
 return dispatched;
end $$;
