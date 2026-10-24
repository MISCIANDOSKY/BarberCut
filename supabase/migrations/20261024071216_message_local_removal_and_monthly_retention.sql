-- Local removal is a per-participant watermark. Message content stays on the server until retention expires.
alter table private.message_threads add column staff_hidden_id bigint not null default 0, add column client_hidden_id bigint not null default 0;
alter table private.maintenance_settings add column message_months integer not null default 6 check(message_months between 1 and 120);
alter table private.maintenance_runs add column deleted_messages integer not null default 0, add column message_months integer;
create index direct_messages_created_at_idx on private.direct_messages(created_at);

create or replace function private.hide_message_threads(p_thread uuid default null)
returns void language plpgsql security definer set search_path=''
as $function$
declare u uuid:=private.message_actor();t private.message_threads;through_id bigint;
begin
 if p_thread is null and not private.message_is_staff(u)then raise exception 'ACCESS_DENIED';end if;
 if p_thread is not null and not exists(select 1 from private.message_threads where id=p_thread and u in(staff_id,client_id))then raise exception 'ACCESS_DENIED';end if;
 for t in select * from private.message_threads where u in(staff_id,client_id) and(p_thread is null or id=p_thread) order by id for update
 loop
   select coalesce(max(id),0) into through_id from private.direct_messages where thread_id=t.id;
   update private.message_threads set
    staff_hidden_id=case when staff_id=u then greatest(staff_hidden_id,through_id)else staff_hidden_id end,
    client_hidden_id=case when client_id=u then greatest(client_hidden_id,through_id)else client_hidden_id end,
    staff_read_id=case when staff_id=u then greatest(staff_read_id,through_id)else staff_read_id end,
    client_read_id=case when client_id=u then greatest(client_read_id,through_id)else client_read_id end where id=t.id;
   update public.notifications set dismissed_at=coalesce(dismissed_at,now()),read_at=coalesce(read_at,now())
   where user_id=u and event_key in(select 'message:'||id::text from private.direct_messages where thread_id=t.id and id<=through_id);
 end loop;
end $function$;
create or replace function public.hide_message_threads(p_thread uuid default null)
returns void language sql security invoker set search_path=''
as $function$select private.hide_message_threads(p_thread)$function$;
revoke all on function private.hide_message_threads(uuid),public.hide_message_threads(uuid) from public,anon,authenticated;
grant execute on function private.hide_message_threads(uuid),public.hide_message_threads(uuid) to authenticated;

create or replace function private.save_maintenance_message_settings(p_inactive_days integer,p_appointment_days integer,p_disable_inactive boolean,p_delete_old boolean,p_message_months integer)
returns void language plpgsql security definer set search_path=''
as $function$
begin
 perform private.save_maintenance_settings(p_inactive_days,p_appointment_days,p_disable_inactive,p_delete_old);
 if p_message_months is null or p_message_months not between 1 and 120 then raise exception 'INVALID_MESSAGE_RETENTION';end if;
 update private.maintenance_settings set message_months=p_message_months where id;
end $function$;
create or replace function public.save_maintenance_message_settings(p_inactive_days integer,p_appointment_days integer,p_disable_inactive boolean,p_delete_old boolean,p_message_months integer)
returns void language sql security invoker set search_path=''
as $function$select private.save_maintenance_message_settings(p_inactive_days,p_appointment_days,p_disable_inactive,p_delete_old,p_message_months)$function$;
revoke all on function private.save_maintenance_message_settings(integer,integer,boolean,boolean,integer),public.save_maintenance_message_settings(integer,integer,boolean,boolean,integer) from public,anon,authenticated;
grant execute on function private.save_maintenance_message_settings(integer,integer,boolean,boolean,integer),public.save_maintenance_message_settings(integer,integer,boolean,boolean,integer) to authenticated;

create or replace function private.purge_old_messages()
returns integer language plpgsql security definer set search_path=''
as $function$
declare cutoff timestamptz;removed integer;
begin
 select ((now() at time zone 'Europe/Rome')-make_interval(months=>message_months)) at time zone 'Europe/Rome' into strict cutoff from private.maintenance_settings where id;
 delete from public.notifications where event_key in(select 'message:'||id::text from private.direct_messages where created_at<cutoff);
 delete from private.direct_messages where created_at<cutoff;
 get diagnostics removed=row_count;
 update private.message_threads t set last_staff_at=(select max(created_at)from private.direct_messages where thread_id=t.id and sender_id=t.staff_id) where last_staff_at<cutoff;
 delete from private.message_threads t where updated_at<cutoff and not exists(select 1 from private.direct_messages where thread_id=t.id);
 return removed;
end $function$;
revoke all on function private.purge_old_messages() from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.message_inbox(p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=private.message_actor();
begin
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'INVALID_MESSAGE';end if;
 return jsonb_build_object('can_start',private.message_is_staff(u),'server_time',now(),'retention_months',(select message_months from private.maintenance_settings where id),'items',coalesce((
 select jsonb_agg(jsonb_build_object('id',t.id,'client_id',case when t.staff_id=u then t.client_id else t.staff_id end,
 'name',private.message_name(case when t.staff_id=u then t.client_id else t.staff_id end),
 'last_body',left(m.body,120),'last_at',m.created_at,
 'unread',(select count(*) from private.direct_messages d where d.thread_id=t.id and d.sender_id<>u and
 d.id>case when t.staff_id=u then t.staff_read_id else t.client_read_id end)))
 from (select * from private.message_threads where (staff_id=u or client_id=u) and exists(select 1 from private.direct_messages v where v.thread_id=message_threads.id and v.id>case when staff_id=u then staff_hidden_id else client_hidden_id end) order by updated_at desc,id limit 100 offset p_offset)t
 join lateral(select body,created_at from private.direct_messages where thread_id=t.id and id>case when t.staff_id=u then t.staff_hidden_id else t.client_hidden_id end order by id desc limit 1)m on true
 ),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION private.message_history(p_thread uuid, p_before bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=private.message_actor();t private.message_threads;allowed boolean;
begin
 select * into t from private.message_threads where id=p_thread and u in(staff_id,client_id);
 if not found then raise exception 'ACCESS_DENIED';end if;
 allowed:=private.message_admin_barber_pair(t.staff_id,t.client_id) or u=t.staff_id or (private.message_is_staff(t.staff_id) and private.message_reply_allowed(t.last_staff_at,now()));
 return jsonb_build_object('thread_id',t.id,'client_id',case when t.staff_id=u then t.client_id else t.staff_id end,
 'name',private.message_name(case when t.staff_id=u then t.client_id else t.staff_id end),
 'can_send',allowed,'can_start',private.message_is_staff(u),'server_time',now(),'hidden_through',(case when t.staff_id=u then t.staff_hidden_id else t.client_hidden_id end)::text,
 'reply_until',case when private.message_admin_barber_pair(t.staff_id,t.client_id) or t.last_staff_at is null then null else (((t.last_staff_at at time zone 'Europe/Rome')::date+1)::timestamp at time zone 'Europe/Rome')end,
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',m.id::text,'body',m.body,'own',m.sender_id=u,'created_at',m.created_at) order by m.id)
 from(select * from private.direct_messages where thread_id=t.id and id>case when t.staff_id=u then t.staff_hidden_id else t.client_hidden_id end and(p_before is null or id<p_before) order by id desc limit 100)m),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION private.run_daily_maintenance()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cfg private.maintenance_settings%rowtype;u record;disabled integer:=0;removed integer:=0;messages_removed integer:=0;cutoff timestamptz;
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
 messages_removed:=private.purge_old_messages();
 insert into private.maintenance_runs(disabled_accounts,deleted_appointments,inactive_days,appointment_days,deleted_messages,message_months) values(disabled,removed,cfg.inactive_days,cfg.appointment_days,messages_removed,cfg.message_months);
 return jsonb_build_object('disabled_accounts',disabled,'deleted_appointments',removed,'deleted_messages',messages_removed);
end $function$;
