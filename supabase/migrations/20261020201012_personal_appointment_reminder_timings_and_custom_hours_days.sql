create table private.reminder_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 offsets integer[] not null default array[60,1440],
 updated_at timestamptz not null default now()
);
alter table private.reminder_preferences enable row level security;
revoke all on private.reminder_preferences from public,anon,authenticated;
create function private.reminder_offsets(p_user uuid) returns integer[] language sql stable security definer set search_path='' as $$
 select coalesce((select offsets from private.reminder_preferences where user_id=p_user),array[60,1440])
$$;
create function private.reminder_minutes(p_event_key text) returns integer language sql immutable set search_path='' as $$
 select case split_part(p_event_key,':',2) when '48h' then 2880 when '24h' then 1440 when '1h' then 60
 else case when split_part(p_event_key,':',2) ~ '^[1-9][0-9]{0,5}m$' then rtrim(split_part(p_event_key,':',2),'m')::integer end end
$$;
create function private.reminder_enabled(p_user uuid,p_event_key text) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.reminder_minutes(p_event_key)=any(private.reminder_offsets(p_user)),false)
$$;
create function private.reminder_settings() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=private.require_push_user();
begin return jsonb_build_object('offsets',to_jsonb(private.reminder_offsets(u)));end $$;
create function public.reminder_settings() returns jsonb language sql stable set search_path='' as $$select private.reminder_settings()$$;
create function private.save_reminder_settings(p_offsets integer[]) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_push_user(); cleaned integer[];
begin
 if p_offsets is null or array_ndims(p_offsets)>1 or exists(select 1 from unnest(p_offsets)n where n is null or n<1 or n>525600 or (n<>15 and n%60<>0))
 or cardinality(p_offsets)>32 then raise exception 'INVALID_REMINDERS';end if;
 select coalesce(array_agg(n order by n),'{}'::integer[]) into cleaned from(select distinct unnest(p_offsets)n)x;
 if (select count(*) from unnest(cleaned)n where n not in(15,60,1440,2880))>12 then raise exception 'REMINDER_LIMIT';end if;
 insert into private.reminder_preferences(user_id,offsets) values(u,cleaned)
 on conflict(user_id) do update set offsets=excluded.offsets,updated_at=now();
 update private.push_deliveries d set status='cancelled',token_hash=null
 from public.notifications n,private.push_subscriptions s
 where n.id=d.notification_id and s.id=d.subscription_id and s.user_id=u
 and d.status in('pending','queued','failed') and not private.reminder_enabled(u,n.event_key);
end $$;
create function public.save_reminder_settings(p_offsets integer[]) returns void language sql set search_path='' as $$select private.save_reminder_settings(p_offsets)$$;

create or replace function private.appointment_reminders() returns void language sql security definer set search_path='' as $$
 insert into public.notifications(user_id,title,body,event_key)
 select e.client_id,
 'Promemoria appuntamento · '||case when r.minutes=2880 then '48 ore' when r.minutes=1440 then '24 ore' when r.minutes=60 then '1 ora'
 when r.minutes%1440=0 then (r.minutes/1440)::text||' giorni' when r.minutes%60=0 then (r.minutes/60)::text||' ore'
 when r.minutes=1 then '1 minuto' else r.minutes::text||' minuti' end,
 'Ricordati del tuo appuntamento! Hai prenotato '||coalesce(nullif(trim(e.service_name),''),'un servizio')||
 ' per il '||to_char(e.start_at at time zone 'Europe/Rome','DD/MM/YYYY')||
 ' alle '||to_char(e.start_at at time zone 'Europe/Rome','HH24:MI')||'. Ti aspettiamo in barberia.',
 e.id::text||':'||case r.minutes when 2880 then '48h' when 1440 then '24h' when 60 then '1h' else r.minutes::text||'m' end||':'||extract(epoch from e.start_at)::text
 from public.calendar_entries e
 cross join lateral unnest(private.reminder_offsets(e.client_id))r(minutes)
 where e.client_id is not null and e.kind='appointment' and e.status='confirmed' and e.start_at>now()
 and e.start_at<=now()+r.minutes*interval '1 minute'
 and e.start_at>=now()+greatest(0,r.minutes-2)*interval '1 minute'
 on conflict(event_key) do nothing
$$;
create or replace function private.queue_appointment_push() returns trigger language plpgsql security definer set search_path='' as $$
declare entry public.calendar_entries%rowtype;
begin
 if new.event_key is null or new.event_key !~ '^[0-9a-f-]{36}:(24h|48h|1h|[1-9][0-9]{0,5}m):[0-9]+([.][0-9]+)?$'
 or not private.reminder_enabled(new.user_id,new.event_key) then return new;end if;
 select * into entry from public.calendar_entries where id=split_part(new.event_key,':',1)::uuid and client_id=new.user_id and kind='appointment'
 and status='confirmed' and start_at>now() and extract(epoch from start_at)=split_part(new.event_key,':',3)::numeric;
 if not found or not coalesce((select enabled from private.push_preferences where user_id=new.user_id),private.push_default_enabled(new.user_id)) then return new;end if;
 insert into private.push_deliveries(notification_id,subscription_id,entry_id,entry_start,expires_at)
 select new.id,s.id,entry.id,entry.start_at,least(entry.start_at,now()+interval '1 hour') from private.push_subscriptions s
 where s.user_id=new.user_id on conflict do nothing;
 return new;
end $$;
create or replace function private.push_delivery_valid(p_delivery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.push_deliveries d
 join private.push_subscriptions s on s.id=d.subscription_id
 join public.notifications n on n.id=d.notification_id and n.user_id=s.user_id
 join public.calendar_entries e on e.id=d.entry_id and e.client_id=s.user_id
 join auth.users a on a.id=s.user_id
 where d.id=p_delivery and d.expires_at>now() and e.status='confirmed' and e.start_at=d.entry_start and e.start_at>now()
 and n.dismissed_at is null and a.deleted_at is null and a.email_confirmed_at is not null and(a.banned_until is null or a.banned_until<=now())
 and private.reminder_enabled(s.user_id,n.event_key)
 and coalesce((select enabled from private.push_preferences where user_id=s.user_id),private.push_default_enabled(s.user_id)))
$$;
revoke all on function private.reminder_offsets(uuid),private.reminder_minutes(text),private.reminder_enabled(uuid,text) from public,anon,authenticated;
revoke all on function private.reminder_settings(),public.reminder_settings(),private.save_reminder_settings(integer[]),public.save_reminder_settings(integer[]) from public,anon;
grant execute on function private.reminder_settings(),public.reminder_settings(),private.save_reminder_settings(integer[]),public.save_reminder_settings(integer[]) to authenticated;
do $$declare job bigint;begin
 select jobid into job from cron.job where jobname='barbercut-appointment-reminders';
 if job is not null then perform cron.alter_job(job,schedule:='* * * * *');end if;
end $$;
