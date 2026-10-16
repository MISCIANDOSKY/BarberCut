create extension if not exists pg_net with schema extensions;
create table private.inactivity_cycles(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 activity_at timestamptz not null,
 inactive_days integer not null,
 disable_after timestamptz not null,
 unique(user_id,activity_at,inactive_days)
);
create table private.inactivity_notices(
 id uuid primary key default gen_random_uuid(),
 cycle_id uuid not null references private.inactivity_cycles(id) on delete cascade,
 lead_days integer not null check(lead_days in(30,15,7)),
 status text not null default 'pending' check(status in('pending','queued','sending','sent','failed','cancelled')),
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 token_hash bytea,
 token_expires_at timestamptz,
 sent_at timestamptz,
 created_at timestamptz not null default now(),
 unique(cycle_id,lead_days)
);
alter table private.inactivity_cycles enable row level security;
alter table private.inactivity_notices enable row level security;
revoke all on private.inactivity_cycles,private.inactivity_notices from public,anon,authenticated;
create index inactivity_notice_dispatch_idx on private.inactivity_notices(next_attempt_at) where status in('pending','queued','sending','failed');

create function private.inactivity_candidates()
returns table(user_id uuid,email text,activity_at timestamptz,inactive_days integer)
language sql stable security definer set search_path='' as $$
 select a.id,a.email::text,
 greatest(a.created_at,a.last_sign_in_at,
  (select x.last_seen_at from private.user_activity x where x.user_id=a.id),
  (select max(greatest(s.created_at,s.updated_at,s.refreshed_at at time zone 'UTC')) from auth.sessions s where s.user_id=a.id)),
 cfg.inactive_days
 from auth.users a join public.user_roles r on r.user_id=a.id and r.role='client'
 cross join private.maintenance_settings cfg
 where cfg.id and cfg.disable_inactive and a.email is not null and a.email<>''
 and a.deleted_at is null and (a.banned_until is null or a.banned_until<=now())
 and not exists(select 1 from public.barbers b where b.user_id=a.id)
 and not exists(select 1 from private.inactive_accounts i where i.user_id=a.id)
 and not exists(select 1 from public.calendar_entries e where e.client_id=a.id and e.kind='appointment' and e.status='confirmed' and e.end_at>now())
$$;
create function private.queue_inactivity_notices() returns integer language plpgsql security definer set search_path='' as $$
declare added integer;
begin
 insert into private.inactivity_cycles(user_id,activity_at,inactive_days,disable_after)
 select v.user_id,v.activity_at,v.inactive_days,greatest(v.activity_at+make_interval(days=>v.inactive_days),now()+interval '30 days')
 from private.inactivity_candidates() v
 where v.activity_at+make_interval(days=>v.inactive_days)<=now()+interval '30 days'
 on conflict(user_id,activity_at,inactive_days) do nothing;
 update private.inactivity_notices n set status='cancelled',token_hash=null
 from private.inactivity_cycles c
 where n.cycle_id=c.id and n.status in('pending','queued','failed')
 and not exists(select 1 from private.inactivity_candidates() v where v.user_id=c.user_id and v.activity_at=c.activity_at and v.inactive_days=c.inactive_days);
 insert into private.inactivity_notices(cycle_id,lead_days)
 select c.id,(select min(d) from unnest(array[30,15,7]) d where ceil(extract(epoch from(c.disable_after-now()))/86400)<=d)
 from private.inactivity_cycles c join private.inactivity_candidates() v on v.user_id=c.user_id and v.activity_at=c.activity_at and v.inactive_days=c.inactive_days
 where c.disable_after<=now()+interval '30 days'
 on conflict(cycle_id,lead_days) do nothing;
 get diagnostics added=row_count;
 return added;
end $$;
create function private.dispatch_inactivity_notices() returns integer language plpgsql security definer set search_path='' as $$
declare n record;secret text;dispatched integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barbercut-inactivity-notices',0)) then return 0;end if;
 perform private.queue_inactivity_notices();
 for n in select id from private.inactivity_notices where status in('pending','failed','queued','sending') and attempts<6 and next_attempt_at<=now() order by created_at limit 20 for update skip locked
 loop
  secret:=gen_random_uuid()::text||gen_random_uuid()::text;
  update private.inactivity_notices set status='queued',attempts=attempts+1,token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes',next_attempt_at=now()+interval '30 minutes' where id=n.id;
  perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/inactivity-warning',headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('notice_id',n.id,'token',secret),timeout_milliseconds:=60000);
  dispatched:=dispatched+1;
 end loop;
 return dispatched;
end $$;

create function private.claim_inactivity_notice(p_notice uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare n private.inactivity_notices%rowtype;c private.inactivity_cycles%rowtype;address text;remaining integer;phase integer;
begin
 select * into n from private.inactivity_notices where id=p_notice and status='queued' and token_hash=extensions.digest(p_token,'sha256') and token_expires_at>now() for update;
 if not found then return null;end if;
 select * into c from private.inactivity_cycles where id=n.cycle_id for update;
 select v.email into address from private.inactivity_candidates() v where v.user_id=c.user_id and v.activity_at=c.activity_at and v.inactive_days=c.inactive_days;
 phase:=(select min(d) from unnest(array[30,15,7]) d where ceil(extract(epoch from(c.disable_after-now()))/86400)<=d);
 if address is null or phase is distinct from n.lead_days then
  update private.inactivity_notices set status='cancelled',token_hash=null where id=n.id;
  return jsonb_build_object('cancelled',true);
 end if;
 if n.lead_days=7 then
  update private.inactivity_cycles set disable_after=greatest(disable_after,now()+interval '7 days') where id=c.id returning * into c;
 end if;
 remaining:=greatest(1,ceil(extract(epoch from(c.disable_after-now()))/86400)::integer);
 update private.inactivity_notices set status='sending',next_attempt_at=now()+interval '30 minutes' where id=n.id;
 -- This metadata is used for email presentation only, never authorization.
 update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('barbercut_warning_days',remaining,'barbercut_warning_notice',n.id::text) where id=c.user_id;
 return jsonb_build_object('email',address,'days',remaining);
end $$;
create function private.finish_inactivity_notice(p_notice uuid,p_token text,p_sent boolean) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 select c.user_id into uid from private.inactivity_notices n join private.inactivity_cycles c on c.id=n.cycle_id where n.id=p_notice and n.status='sending' and n.token_hash=extensions.digest(p_token,'sha256') for update of n;
 if not found then return;end if;
 update auth.users set raw_user_meta_data=raw_user_meta_data-'barbercut_warning_days'-'barbercut_warning_notice' where id=uid and raw_user_meta_data->>'barbercut_warning_notice'=p_notice::text;
 update private.inactivity_notices set status=case when p_sent then 'sent' else 'failed' end,sent_at=case when p_sent then now() else null end,token_hash=null,next_attempt_at=now()+interval '30 minutes' where id=p_notice;
end $$;
create function public.claim_inactivity_notice(p_notice uuid,p_token text) returns jsonb language sql security invoker set search_path='' as $$select private.claim_inactivity_notice(p_notice,p_token)$$;
create function public.finish_inactivity_notice(p_notice uuid,p_token text,p_sent boolean) returns void language sql security invoker set search_path='' as $$select private.finish_inactivity_notice(p_notice,p_token,p_sent)$$;
revoke all on function private.inactivity_candidates(),private.queue_inactivity_notices(),private.dispatch_inactivity_notices(),private.claim_inactivity_notice(uuid,text),private.finish_inactivity_notice(uuid,text,boolean),public.claim_inactivity_notice(uuid,text),public.finish_inactivity_notice(uuid,text,boolean) from public,anon,authenticated,service_role;
grant execute on function private.claim_inactivity_notice(uuid,text),private.finish_inactivity_notice(uuid,text,boolean),public.claim_inactivity_notice(uuid,text),public.finish_inactivity_notice(uuid,text,boolean) to service_role;
CREATE OR REPLACE FUNCTION private.run_daily_maintenance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg private.maintenance_settings%rowtype;u record;disabled integer:=0;removed integer:=0;cutoff timestamptz;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barbercut-daily-maintenance',0)) then return '{"skipped":true}'::jsonb;end if;
 select * into strict cfg from private.maintenance_settings where id;
 if cfg.disable_inactive then
  for u in
   select a.id,a.banned_until from auth.users a
   join public.user_roles r on r.user_id=a.id and r.role='client'
   where a.deleted_at is null and (a.banned_until is null or a.banned_until<=now())
    and not exists(select 1 from public.barbers b where b.user_id=a.id)
    and not exists(select 1 from private.inactive_accounts i where i.user_id=a.id)
    and not exists(select 1 from public.calendar_entries e where e.client_id=a.id and e.kind='appointment' and e.status='confirmed' and e.end_at>now())
    and greatest(a.created_at,a.last_sign_in_at,
     (select x.last_seen_at from private.user_activity x where x.user_id=a.id),
     (select max(greatest(s.created_at,s.updated_at,s.refreshed_at at time zone 'UTC')) from auth.sessions s where s.user_id=a.id))<now()-make_interval(days=>cfg.inactive_days)
   for update of a skip locked
  loop
   -- Activity calls acquire a shared user lock, so recheck after obtaining the user lock.
   if exists(select 1 from private.user_activity where user_id=u.id and last_seen_at>=now()-make_interval(days=>cfg.inactive_days)) then continue;end if;
   -- Never disable a client before the final warning has had a full seven-day grace period.
   if not exists (
    select 1 from private.inactivity_cycles c
    join private.inactivity_candidates() v on v.user_id=c.user_id and v.activity_at=c.activity_at and v.inactive_days=c.inactive_days
    where c.user_id=u.id and c.disable_after<=now()
     and exists(select 1 from private.inactivity_notices n where n.cycle_id=c.id and n.lead_days=7 and n.status='sent' and n.sent_at<=now()-interval '7 days')
   ) then continue;end if;
   insert into private.inactive_accounts(user_id,previous_banned_until) values(u.id,u.banned_until);
   update auth.users set banned_until=now()+interval '100 years',updated_at=now() where id=u.id;
   delete from auth.sessions where user_id=u.id;
   disabled:=disabled+1;
  end loop;
 end if;
 if cfg.delete_old_appointments then
  cutoff:=(((now() at time zone 'Europe/Rome')::date-cfg.appointment_days)::timestamp at time zone 'Europe/Rome');
  delete from public.calendar_entries where kind='appointment' and end_at<cutoff;
  get diagnostics removed=row_count;
 end if;
 insert into private.maintenance_runs(disabled_accounts,deleted_appointments,inactive_days,appointment_days) values(disabled,removed,cfg.inactive_days,cfg.appointment_days);
 return jsonb_build_object('disabled_accounts',disabled,'deleted_appointments',removed);
end $function$

;
create function private.booking_keeps_account_active() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind='appointment' and new.client_id is not null and auth.uid()=new.client_id then
 insert into private.user_activity(user_id,last_seen_at) values(new.client_id,now()) on conflict(user_id) do update set last_seen_at=excluded.last_seen_at;
 end if;
 return new;
end $$;
revoke all on function private.booking_keeps_account_active() from public,anon,authenticated;
create trigger booking_keeps_account_active after insert on public.calendar_entries for each row execute function private.booking_keeps_account_active();
select cron.schedule('barbercut-inactivity-warning-dispatch','*/15 * * * *','select private.dispatch_inactivity_notices();');
