create table private.maintenance_settings (
 id boolean primary key default true check(id),
 inactive_days integer not null default 120 check(inactive_days between 1 and 36500),
 appointment_days integer not null default 40 check(appointment_days between 1 and 36500),
 disable_inactive boolean not null default true,
 delete_old_appointments boolean not null default true
);
insert into private.maintenance_settings(id) values(true);
create table private.user_activity (
 user_id uuid primary key references auth.users(id) on delete cascade,
 last_seen_at timestamptz not null default now()
);
insert into private.user_activity(user_id,last_seen_at)
 select u.id,greatest(u.created_at,u.last_sign_in_at,
  (select max(greatest(s.created_at,s.updated_at,s.refreshed_at at time zone 'UTC')) from auth.sessions s where s.user_id=u.id))
 from auth.users u;
create table private.inactive_accounts (
 user_id uuid primary key references auth.users(id) on delete cascade,
 disabled_at timestamptz not null default now(),
 previous_banned_until timestamptz
);
create table private.maintenance_runs (
 id bigint generated always as identity primary key,
 finished_at timestamptz not null default now(),
 disabled_accounts integer not null,
 deleted_appointments integer not null,
 inactive_days integer not null,
 appointment_days integer not null
);
alter table private.maintenance_settings enable row level security;
alter table private.user_activity enable row level security;
alter table private.inactive_accounts enable row level security;
alter table private.maintenance_runs enable row level security;
revoke all on private.maintenance_settings,private.user_activity,private.inactive_accounts,private.maintenance_runs from public,anon,authenticated;
create index calendar_maintenance_end_idx on public.calendar_entries(end_at) where kind='appointment';

create function private.record_activity() returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 perform 1 from auth.users where id=auth.uid() and deleted_at is null and (banned_until is null or banned_until<=now()) for share;
 if not found then return;end if;
 insert into private.user_activity(user_id,last_seen_at) values(auth.uid(),now())
 on conflict(user_id) do update set last_seen_at=excluded.last_seen_at
 where private.user_activity.last_seen_at<now()-interval '15 minutes';
end $$;
create function public.record_activity() returns void language sql security invoker set search_path='' as $$select private.record_activity()$$;
revoke all on function private.record_activity(),public.record_activity() from public,anon;
grant execute on function private.record_activity(),public.record_activity() to authenticated;

create function private.maintenance_status() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 return jsonb_build_object(
 'settings',(select to_jsonb(s) from private.maintenance_settings s where id),
 'last_run',(select to_jsonb(r) from private.maintenance_runs r order by id desc limit 1),
 'disabled_count',(select count(*) from private.inactive_accounts),
 'disabled_accounts',coalesce((select jsonb_agg(t) from (
 select i.user_id,i.disabled_at,p.first_name,p.last_name from private.inactive_accounts i join public.profiles p on p.id=i.user_id order by i.disabled_at desc limit 100)t),'[]'::jsonb));
end $$;
create function public.maintenance_status() returns jsonb language sql security invoker set search_path='' as $$select private.maintenance_status()$$;
create function private.save_maintenance_settings(p_inactive_days integer,p_appointment_days integer,p_disable_inactive boolean,p_delete_old boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 if p_inactive_days is null or p_appointment_days is null or p_inactive_days not between 1 and 36500 or p_appointment_days not between 1 and 36500 or p_disable_inactive is null or p_delete_old is null then raise exception 'INVALID_MAINTENANCE_DAYS';end if;
 update private.maintenance_settings set inactive_days=p_inactive_days,appointment_days=p_appointment_days,disable_inactive=p_disable_inactive,delete_old_appointments=p_delete_old where id;
end $$;
create function public.save_maintenance_settings(p_inactive_days integer,p_appointment_days integer,p_disable_inactive boolean,p_delete_old boolean) returns void language sql security invoker set search_path='' as $$select private.save_maintenance_settings(p_inactive_days,p_appointment_days,p_disable_inactive,p_delete_old)$$;
create function private.reactivate_inactive_account(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare previous timestamptz;
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 perform 1 from auth.users where id=p_user for update;
 select previous_banned_until into previous from private.inactive_accounts where user_id=p_user for update;
 if not found then raise exception 'ACCOUNT_NOT_DISABLED';end if;
 update auth.users set banned_until=previous,updated_at=now() where id=p_user;
 delete from private.inactive_accounts where user_id=p_user;
 insert into private.user_activity(user_id,last_seen_at) values(p_user,now()) on conflict(user_id) do update set last_seen_at=excluded.last_seen_at;
end $$;
create function public.reactivate_inactive_account(p_user uuid) returns void language sql security invoker set search_path='' as $$select private.reactivate_inactive_account(p_user)$$;
revoke all on function private.maintenance_status(),public.maintenance_status(),private.save_maintenance_settings(integer,integer,boolean,boolean),public.save_maintenance_settings(integer,integer,boolean,boolean),private.reactivate_inactive_account(uuid),public.reactivate_inactive_account(uuid) from public,anon;
grant execute on function private.maintenance_status(),public.maintenance_status(),private.save_maintenance_settings(integer,integer,boolean,boolean),public.save_maintenance_settings(integer,integer,boolean,boolean),private.reactivate_inactive_account(uuid),public.reactivate_inactive_account(uuid) to authenticated;

create function private.run_daily_maintenance() returns jsonb language plpgsql security definer set search_path='' as $$
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
end $$;
revoke all on function private.run_daily_maintenance() from public,anon,authenticated,service_role;
select cron.schedule('barbercut-daily-maintenance','15 3 * * *','select private.run_daily_maintenance();');
