create table private.push_config(
 id boolean primary key default true check(id),
 public_key text, private_key text,
 setup_hash bytea, setup_expires_at timestamptz
);
insert into private.push_config(id) values(true);
create table private.push_preferences(
 user_id uuid primary key references auth.users(id) on delete cascade,
 enabled boolean not null default true,
 updated_at timestamptz not null default now()
);
create table private.push_subscriptions(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text not null unique,
 p256dh text not null, auth_key text not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index push_subscriptions_user_idx on private.push_subscriptions(user_id);
create table private.push_deliveries(
 id uuid primary key default gen_random_uuid(),
 notification_id uuid not null references public.notifications(id) on delete cascade,
 subscription_id uuid not null references private.push_subscriptions(id) on delete cascade,
 entry_id uuid not null references public.calendar_entries(id) on delete cascade,
 entry_start timestamptz not null,
 expires_at timestamptz not null,
 status text not null default 'pending' check(status in('pending','queued','sending','sent','cancelled','failed')),
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 token_hash bytea, token_expires_at timestamptz, sent_at timestamptz,
 unique(notification_id,subscription_id)
);
create index push_deliveries_pending_idx on private.push_deliveries(next_attempt_at) where status in('pending','queued','sending','failed');
alter table private.push_config enable row level security;
alter table private.push_preferences enable row level security;
alter table private.push_subscriptions enable row level security;
alter table private.push_deliveries enable row level security;
revoke all on private.push_config,private.push_preferences,private.push_subscriptions,private.push_deliveries from public,anon,authenticated;

create function private.require_push_user() returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();
begin
 if u is null or not exists(select 1 from auth.users a join auth.sessions s on s.user_id=a.id
 where a.id=u and a.deleted_at is null and a.email_confirmed_at is not null
 and (a.banned_until is null or a.banned_until<=now()) and s.id::text=auth.jwt()->>'session_id' and (s.not_after is null or s.not_after>now())) then raise exception 'ACCESS_DENIED';end if;
 return u;
end $$;
create function private.push_default_enabled(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select role not in('barber','barber_admin','shop') from public.user_roles where user_id=p_user),false)
$$;
create function private.push_settings() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=private.require_push_user();
begin
 return jsonb_build_object('enabled',coalesce((select enabled from private.push_preferences where user_id=u),private.push_default_enabled(u)),
 'public_key',(select public_key from private.push_config where id));
end $$;
create function public.push_settings() returns jsonb language sql stable set search_path='' as $$select private.push_settings()$$;
create function private.set_push_enabled(p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_push_user();
begin
 if p_enabled is null then raise exception 'INVALID_PUSH';end if;
 insert into private.push_preferences(user_id,enabled) values(u,p_enabled)
 on conflict(user_id) do update set enabled=excluded.enabled,updated_at=now();
 if not p_enabled then delete from private.push_subscriptions where user_id=u;end if;
end $$;
create function public.set_push_enabled(p_enabled boolean) returns void language sql set search_path='' as $$select private.set_push_enabled(p_enabled)$$;
create function private.register_push_subscription(p_subscription jsonb) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_push_user(); ep text:=p_subscription->>'endpoint'; k text:=p_subscription#>>'{keys,p256dh}'; a text:=p_subscription#>>'{keys,auth}';
begin
 if ep is null or length(ep)>4096 or ep !~ '^https://(fcm\.googleapis\.com|([a-z0-9-]+\.)*push\.services\.mozilla\.com|web\.push\.apple\.com|([a-z0-9-]+\.)*notify\.windows\.com)/'
 or k is null or k !~ '^[A-Za-z0-9_-]{87}$' or a is null or a !~ '^[A-Za-z0-9_-]{22}$' then raise exception 'INVALID_PUSH';end if;
 if not exists(select 1 from private.push_config where id and public_key is not null) then raise exception 'PUSH_NOT_READY';end if;
 perform pg_advisory_xact_lock(hashtextextended('push-user:'||u::text,0));
 if not exists(select 1 from private.push_subscriptions where endpoint=ep) and (select count(*) from private.push_subscriptions where user_id=u)>=10 then raise exception 'PUSH_DEVICE_LIMIT';end if;
 insert into private.push_subscriptions(user_id,endpoint,p256dh,auth_key) values(u,ep,k,a)
 on conflict(endpoint) do update set p256dh=excluded.p256dh,auth_key=excluded.auth_key,updated_at=now()
 where private.push_subscriptions.user_id=u;
 if not found then raise exception 'PUSH_DEVICE_IN_USE';end if;
end $$;
create function public.register_push_subscription(p_subscription jsonb) returns void language sql set search_path='' as $$select private.register_push_subscription(p_subscription)$$;
create function private.unregister_push_subscription(p_endpoint text) returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.require_push_user();
begin delete from private.push_subscriptions where user_id=u and endpoint=p_endpoint;end $$;
create function public.unregister_push_subscription(p_endpoint text) returns void language sql set search_path='' as $$select private.unregister_push_subscription(p_endpoint)$$;

create function private.push_setup_allowed(p_token text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.push_config where id and public_key is null and setup_expires_at>now() and setup_hash=extensions.digest(p_token,'sha256'))
$$;
create function public.push_setup_allowed(p_token text) returns boolean language sql stable set search_path='' as $$select private.push_setup_allowed(p_token)$$;
create function private.complete_push_setup(p_token text,p_public text,p_private text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_public is null or p_private is null or p_public !~ '^[A-Za-z0-9_-]{87}$' or p_private !~ '^[A-Za-z0-9_-]{43}$' then raise exception 'INVALID_PUSH';end if;
 update private.push_config set public_key=p_public,private_key=p_private,setup_hash=null,setup_expires_at=null
 where id and public_key is null and setup_expires_at>now() and setup_hash=extensions.digest(p_token,'sha256');
 if not found then raise exception 'ACCESS_DENIED';end if;
end $$;
create function public.complete_push_setup(p_token text,p_public text,p_private text) returns void language sql set search_path='' as $$select private.complete_push_setup(p_token,p_public,p_private)$$;
create function private.request_push_setup() returns void language plpgsql security definer set search_path='' as $$
declare secret text:=gen_random_uuid()::text||gen_random_uuid()::text;
begin
 update private.push_config set setup_hash=extensions.digest(secret,'sha256'),setup_expires_at=now()+interval '10 minutes' where id and public_key is null;
 if not found then return;end if;
 perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/appointment-push',
 headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('action','setup','token',secret),timeout_milliseconds:=20000);
end $$;

create function private.queue_appointment_push() returns trigger language plpgsql security definer set search_path='' as $$
declare entry public.calendar_entries%rowtype;
begin
 if new.event_key is null or new.event_key !~ '^[0-9a-f-]{36}:(24h|1h):[0-9]+(\.[0-9]+)?$' then return new;end if;
 select * into entry from public.calendar_entries where id=split_part(new.event_key,':',1)::uuid and client_id=new.user_id and kind='appointment'
 and status='confirmed' and start_at>now() and extract(epoch from start_at)=split_part(new.event_key,':',3)::numeric;
 if not found or not coalesce((select enabled from private.push_preferences where user_id=new.user_id),private.push_default_enabled(new.user_id)) then return new;end if;
 insert into private.push_deliveries(notification_id,subscription_id,entry_id,entry_start,expires_at)
 select new.id,s.id,entry.id,entry.start_at,least(entry.start_at,now()+interval '1 hour') from private.push_subscriptions s
 where s.user_id=new.user_id on conflict do nothing;
 return new;
end $$;
create trigger queue_appointment_push after insert on public.notifications for each row execute function private.queue_appointment_push();
create function private.push_delivery_valid(p_delivery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.push_deliveries d
 join private.push_subscriptions s on s.id=d.subscription_id
 join public.notifications n on n.id=d.notification_id and n.user_id=s.user_id
 join public.calendar_entries e on e.id=d.entry_id and e.client_id=s.user_id
 join auth.users a on a.id=s.user_id
 where d.id=p_delivery and d.expires_at>now() and e.status='confirmed' and e.start_at=d.entry_start and e.start_at>now()
 and n.dismissed_at is null and a.deleted_at is null and a.email_confirmed_at is not null and(a.banned_until is null or a.banned_until<=now())
 and coalesce((select enabled from private.push_preferences where user_id=s.user_id),private.push_default_enabled(s.user_id)))
$$;
create function private.claim_appointment_push(p_delivery uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare item private.push_deliveries%rowtype; payload jsonb;
begin
 select * into item from private.push_deliveries where id=p_delivery and status='queued'
 and token_hash=extensions.digest(p_token,'sha256') and token_expires_at>now() for update;
 if not found then return null;end if;
 if not private.push_delivery_valid(item.id) then
 update private.push_deliveries set status='cancelled',token_hash=null where id=item.id;return null;end if;
 update private.push_deliveries set status='sending',next_attempt_at=now()+interval '5 minutes' where id=item.id;
 select jsonb_build_object('subscription',jsonb_build_object('endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key)),
 'public_key',c.public_key,'private_key',c.private_key,
 'payload',jsonb_build_object('title',n.title,'body',n.body,'tag','barberup-'||n.id::text,'url','https://misciandosky.github.io/BarberUp/?appointments=1'),
 'ttl',greatest(1,least(3600,extract(epoch from(item.expires_at-now()))::integer)))
 into payload from private.push_subscriptions s join public.notifications n on n.id=item.notification_id cross join private.push_config c
 where s.id=item.subscription_id and c.id and c.private_key is not null;
 return payload;
end $$;
create function public.claim_appointment_push(p_delivery uuid,p_token text) returns jsonb language sql set search_path='' as $$select private.claim_appointment_push(p_delivery,p_token)$$;
create function private.finish_appointment_push(p_delivery uuid,p_token text,p_outcome text) returns void language plpgsql security definer set search_path='' as $$
declare item private.push_deliveries%rowtype;
begin
 if p_outcome not in('sent','expired','failed') then raise exception 'INVALID_PUSH';end if;
 select * into item from private.push_deliveries where id=p_delivery and status='sending' and token_hash=extensions.digest(p_token,'sha256') for update;
 if not found then return;end if;
 if p_outcome='expired' then delete from private.push_subscriptions where id=item.subscription_id;return;end if;
 update private.push_deliveries set status=case when p_outcome='sent' then 'sent' else 'failed' end,
 sent_at=case when p_outcome='sent' then now() else null end,token_hash=null,token_expires_at=null,next_attempt_at=now()+interval '5 minutes' where id=item.id;
end $$;
create function public.finish_appointment_push(p_delivery uuid,p_token text,p_outcome text) returns void language sql set search_path='' as $$select private.finish_appointment_push(p_delivery,p_token,p_outcome)$$;
create function private.dispatch_appointment_push() returns integer language plpgsql security definer set search_path='' as $$
declare item record;secret text;amount integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barberup-appointment-push',0)) then return 0;end if;
 if not exists(select 1 from private.push_config where id and private_key is not null) then return 0;end if;
 update private.push_deliveries set status='cancelled',token_hash=null
 where status in('pending','queued','sending','failed') and (expires_at<=now() or attempts>=4 or not private.push_delivery_valid(id));
 for item in select id from private.push_deliveries where status in('pending','queued','sending','failed') and attempts<4 and next_attempt_at<=now() order by next_attempt_at limit 20 for update skip locked
 loop
  secret:=gen_random_uuid()::text||gen_random_uuid()::text;
  update private.push_deliveries set status='queued',attempts=attempts+1,token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '5 minutes',next_attempt_at=now()+interval '5 minutes' where id=item.id;
  perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/appointment-push',
  headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('action','send','delivery_id',item.id,'token',secret),timeout_milliseconds:=20000);
  amount:=amount+1;
 end loop;
 return amount;
end $$;

revoke all on function private.require_push_user(),private.push_settings(),public.push_settings(),private.set_push_enabled(boolean),public.set_push_enabled(boolean),
 private.register_push_subscription(jsonb),public.register_push_subscription(jsonb),private.unregister_push_subscription(text),public.unregister_push_subscription(text) from public,anon;
grant execute on function private.push_settings(),public.push_settings(),private.set_push_enabled(boolean),public.set_push_enabled(boolean),
 private.register_push_subscription(jsonb),public.register_push_subscription(jsonb),private.unregister_push_subscription(text),public.unregister_push_subscription(text) to authenticated;
revoke all on function private.push_default_enabled(uuid),private.queue_appointment_push(),private.push_delivery_valid(uuid),private.request_push_setup(),private.dispatch_appointment_push(),
 private.push_setup_allowed(text),public.push_setup_allowed(text),private.complete_push_setup(text,text,text),public.complete_push_setup(text,text,text),
 private.claim_appointment_push(uuid,text),public.claim_appointment_push(uuid,text),private.finish_appointment_push(uuid,text,text),public.finish_appointment_push(uuid,text,text) from public,anon,authenticated;
grant execute on function private.push_setup_allowed(text),public.push_setup_allowed(text),private.complete_push_setup(text,text,text),public.complete_push_setup(text,text,text),
 private.claim_appointment_push(uuid,text),public.claim_appointment_push(uuid,text),private.finish_appointment_push(uuid,text,text),public.finish_appointment_push(uuid,text,text) to service_role;
select cron.schedule('barberup-appointment-push','* * * * *','select private.dispatch_appointment_push()');
