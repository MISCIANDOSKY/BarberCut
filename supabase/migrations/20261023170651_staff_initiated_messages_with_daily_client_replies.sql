
create table private.message_threads(
 id uuid primary key default gen_random_uuid(),
 staff_id uuid not null references public.profiles(id) on delete cascade,
 client_id uuid not null references public.profiles(id) on delete cascade,
 last_staff_at timestamptz,
 updated_at timestamptz not null default now(),
 staff_read_id bigint not null default 0,
 client_read_id bigint not null default 0,
 unique(staff_id,client_id),check(staff_id<>client_id)
);
create table private.direct_messages(
 id bigint generated always as identity primary key,
 thread_id uuid not null references private.message_threads(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 client_nonce uuid not null,
 body text not null check(char_length(body) between 1 and 2000 and body=btrim(body)),
 created_at timestamptz not null default clock_timestamp(),
 unique(sender_id,client_nonce)
);
create index message_threads_client_recent on private.message_threads(client_id,updated_at desc,id);
create index message_threads_staff_recent on private.message_threads(staff_id,updated_at desc,id);
create index direct_messages_history on private.direct_messages(thread_id,id desc);
create index direct_messages_rate on private.direct_messages(sender_id,created_at desc);
alter table private.message_threads enable row level security;
alter table private.direct_messages enable row level security;
revoke all on private.message_threads,private.direct_messages from public,anon,authenticated;

create function private.message_is_staff(p_user uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.user_roles r where r.user_id=p_user and
 (r.role='admin' or (r.role in('barber','barber_admin') and exists(select 1 from public.barbers b where b.user_id=p_user and b.active and b.deleted_at is null))));
$$;
create function private.message_actor() returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid:=private.require_push_user();r text;
begin
 if not coalesce((private.current_terms_status()->>'accepted')::boolean,false) then raise exception 'TERMS_REQUIRED';end if;
 select role into r from public.user_roles where user_id=u;
 if r='shop' or r is null then raise exception 'ACCESS_DENIED';end if;
 if r<>'client' and (not private.message_is_staff(u) or not private.staff_ok()) then raise exception 'ACCESS_DENIED';end if;
 return u;
end $$;
create function private.message_name(p_user uuid) returns text language sql stable security definer set search_path='' as $$
 select coalesce(nullif(btrim(concat_ws(' ',p.first_name,p.last_name)),''),'Utente') from public.profiles p where p.id=p_user;
$$;
create function private.message_reply_allowed(p_last_staff_at timestamptz,p_now timestamptz)
returns boolean language sql immutable set search_path='' as $$
 select coalesce((p_last_staff_at at time zone 'Europe/Rome')::date=(p_now at time zone 'Europe/Rome')::date,false);
$$;

create function private.message_recipients(p_query text default '',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=private.message_actor();
begin
 if not private.message_is_staff(u) then raise exception 'ACCESS_DENIED';end if;
 if p_offset is null or p_offset<0 or p_offset>100000 or char_length(coalesce(p_query,''))>100 then raise exception 'INVALID_MESSAGE';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from (
 select p.id,private.message_name(p.id) name from public.profiles p
 join public.user_roles r on r.user_id=p.id and r.role='client'
 join private.client_memberships cm on cm.user_id=p.id
 join auth.users a on a.id=p.id and a.deleted_at is null and (a.banned_until is null or a.banned_until<=now())
 where char_length(btrim(coalesce(p_query,'')))>=2 and
 (strpos(lower(p.first_name||' '||p.last_name),lower(btrim(p_query)))>0 or strpos(p.phone,btrim(p_query))>0)
 order by lower(p.first_name),lower(p.last_name),p.id limit 30 offset p_offset
 )q),'[]'::jsonb);
end $$;

create function private.message_inbox(p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=private.message_actor();
begin
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'INVALID_MESSAGE';end if;
 return jsonb_build_object('can_start',private.message_is_staff(u),'server_time',now(),'items',coalesce((
 select jsonb_agg(jsonb_build_object('id',t.id,'client_id',t.client_id,
 'name',private.message_name(case when t.staff_id=u then t.client_id else t.staff_id end),
 'last_body',left(m.body,120),'last_at',m.created_at,
 'unread',(select count(*) from private.direct_messages d where d.thread_id=t.id and d.sender_id<>u and
 d.id>case when t.staff_id=u then t.staff_read_id else t.client_read_id end)))
 from (select * from private.message_threads where staff_id=u or client_id=u order by updated_at desc,id limit 100 offset p_offset)t
 join lateral(select body,created_at from private.direct_messages where thread_id=t.id order by id desc limit 1)m on true
 ),'[]'::jsonb));
end $$;

create function private.message_history(p_thread uuid,p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=private.message_actor();t private.message_threads;allowed boolean;
begin
 select * into t from private.message_threads where id=p_thread and u in(staff_id,client_id);
 if not found then raise exception 'ACCESS_DENIED';end if;
 allowed:=u=t.staff_id or (private.message_is_staff(t.staff_id) and private.message_reply_allowed(t.last_staff_at,now()));
 return jsonb_build_object('thread_id',t.id,'client_id',t.client_id,
 'name',private.message_name(case when t.staff_id=u then t.client_id else t.staff_id end),
 'can_send',allowed,'can_start',private.message_is_staff(u),'server_time',now(),
 'reply_until',case when t.last_staff_at is null then null else (((t.last_staff_at at time zone 'Europe/Rome')::date+1)::timestamp at time zone 'Europe/Rome')end,
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',m.id::text,'body',m.body,'own',m.sender_id=u,'created_at',m.created_at) order by m.id)
 from(select * from private.direct_messages where thread_id=t.id and(p_before is null or id<p_before) order by id desc limit 100)m),'[]'::jsonb));
end $$;

create function private.read_message_thread(p_thread uuid,p_through bigint)
returns void language plpgsql security definer set search_path='' as $$
declare u uuid:=private.message_actor();t private.message_threads;
begin
 select * into t from private.message_threads where id=p_thread and u in(staff_id,client_id) for update;
 if not found then raise exception 'ACCESS_DENIED';end if;
 if p_through is null or not exists(select 1 from private.direct_messages where thread_id=t.id and id=p_through) then raise exception 'INVALID_MESSAGE';end if;
 update private.message_threads set staff_read_id=case when staff_id=u then greatest(staff_read_id,p_through)else staff_read_id end,
 client_read_id=case when client_id=u then greatest(client_read_id,p_through)else client_read_id end where id=t.id;
 update public.notifications set read_at=coalesce(read_at,now()) where user_id=u and event_key in
 (select 'message:'||id::text from private.direct_messages where thread_id=t.id and id<=p_through);
end $$;

create table private.message_push_deliveries(
 id uuid primary key default gen_random_uuid(),
 message_id bigint not null references private.direct_messages(id) on delete cascade,
 notification_id uuid not null references public.notifications(id) on delete cascade,
 subscription_id uuid not null references private.push_subscriptions(id) on delete cascade,
 expires_at timestamptz not null default now()+interval '1 hour',
 status text not null default 'pending' check(status in('pending','queued','sending','sent','cancelled','failed')),
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 token_hash bytea,token_expires_at timestamptz,sent_at timestamptz,
 unique(message_id,subscription_id)
);
alter table private.message_push_deliveries enable row level security;
revoke all on private.message_push_deliveries from public,anon,authenticated;
create index message_push_pending on private.message_push_deliveries(next_attempt_at) where status in('pending','queued','sending','failed');

create function private.send_direct_message(p_body text,p_nonce uuid,p_thread uuid default null,p_client uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=private.message_actor();t private.message_threads;m private.direct_messages;recipient uuid;n uuid;stamp timestamptz;
begin
 if p_body is null or char_length(btrim(p_body)) not between 1 and 2000 or p_nonce is null then raise exception 'INVALID_MESSAGE';end if;
 perform pg_advisory_xact_lock(hashtextextended('message-sender:'||u::text,0));
 if p_thread is null then
   if not private.message_is_staff(u) or p_client is null or p_client=u then raise exception 'ACCESS_DENIED';end if;
   if not exists(select 1 from public.profiles p join public.user_roles r on r.user_id=p.id and r.role='client'
    join private.client_memberships cm on cm.user_id=p.id join auth.users a on a.id=p.id
    where p.id=p_client and a.deleted_at is null and (a.banned_until is null or a.banned_until<=now())) then raise exception 'MESSAGE_CLIENT_UNAVAILABLE';end if;
   insert into private.message_threads(staff_id,client_id)values(u,p_client)on conflict(staff_id,client_id)do nothing;
   select * into t from private.message_threads where staff_id=u and client_id=p_client for update;
 else
   select * into t from private.message_threads where id=p_thread and u in(staff_id,client_id) for update;
   if not found or p_client is not null then raise exception 'ACCESS_DENIED';end if;
 end if;
 select * into m from private.direct_messages where sender_id=u and client_nonce=p_nonce;
 if found then
   if m.thread_id<>t.id or m.body<>btrim(p_body) then raise exception 'INVALID_MESSAGE';end if;
   return jsonb_build_object('thread_id',t.id,'id',m.id::text);
 end if;
 stamp:=clock_timestamp();
 if u=t.staff_id then
   if not private.message_is_staff(u) then raise exception 'ACCESS_DENIED';end if;
   recipient:=t.client_id;
 else
   if not exists(select 1 from public.user_roles where user_id=u and role='client')
     or not private.message_is_staff(t.staff_id) or not private.message_reply_allowed(t.last_staff_at,stamp)
   then raise exception 'MESSAGE_REPLY_CLOSED';end if;
   recipient:=t.staff_id;
 end if;
 if not exists(select 1 from auth.users a where a.id=recipient and a.deleted_at is null and(a.banned_until is null or a.banned_until<=stamp)) then raise exception 'MESSAGE_CLIENT_UNAVAILABLE';end if;
 if(select count(*) from private.direct_messages where sender_id=u and created_at>stamp-interval '1 minute')>=20 then raise exception 'MESSAGE_RATE_LIMIT';end if;
 insert into private.direct_messages(thread_id,sender_id,client_nonce,body,created_at)values(t.id,u,p_nonce,btrim(p_body),stamp)returning * into m;
 update private.message_threads set last_staff_at=case when u=staff_id then stamp else last_staff_at end,updated_at=stamp,
 staff_read_id=case when staff_id=u then m.id else staff_read_id end,
 client_read_id=case when client_id=u then m.id else client_read_id end where id=t.id;
 insert into public.notifications(user_id,title,body,event_key) values(recipient,
 case when u=t.staff_id then 'Nuovo messaggio' else 'Nuova risposta' end,
 'Hai ricevuto un messaggio nella barberia. Apri Messaggi per leggerlo.','message:'||m.id::text)returning id into n;
 if coalesce((select enabled from private.push_preferences where user_id=recipient),private.push_default_enabled(recipient)) then
 insert into private.message_push_deliveries(message_id,notification_id,subscription_id)
 select m.id,n,s.id from private.push_subscriptions s where s.user_id=recipient on conflict do nothing;
 end if;
 return jsonb_build_object('thread_id',t.id,'id',m.id::text);
end $$;

create function private.message_push_valid(p_delivery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.message_push_deliveries d
 join private.direct_messages m on m.id=d.message_id
 join private.message_threads t on t.id=m.thread_id
 join private.push_subscriptions s on s.id=d.subscription_id
 join public.notifications n on n.id=d.notification_id and n.user_id=s.user_id
 join auth.users a on a.id=s.user_id
 where d.id=p_delivery and d.expires_at>now() and s.user_id in(t.staff_id,t.client_id) and s.user_id<>m.sender_id
 and m.id>case when s.user_id=t.staff_id then t.staff_read_id else t.client_read_id end
 and n.dismissed_at is null and a.deleted_at is null and a.email_confirmed_at is not null and(a.banned_until is null or a.banned_until<=now())
 and coalesce((select enabled from private.push_preferences where user_id=s.user_id),private.push_default_enabled(s.user_id)));
$$;

create function private.claim_message_push(p_delivery uuid,p_token text)returns jsonb language plpgsql security definer set search_path='' as $$
declare item private.message_push_deliveries;payload jsonb;
begin
 select * into item from private.message_push_deliveries where id=p_delivery and status='queued'
 and token_hash=extensions.digest(p_token,'sha256') and token_expires_at>now() for update;
 if not found then return null;end if;
 if not private.message_push_valid(item.id)then update private.message_push_deliveries set status='cancelled',token_hash=null where id=item.id;return null;end if;
 update private.message_push_deliveries set status='sending',next_attempt_at=now()+interval '5 minutes' where id=item.id;
 select jsonb_build_object('subscription',jsonb_build_object('endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key)),
 'public_key',c.public_key,'private_key',c.private_key,
 'payload',jsonb_build_object('title',n.title,'body',n.body,'tag','barberup-message-'||item.message_id::text,'kind','message'),
 'ttl',greatest(1,least(3600,extract(epoch from(item.expires_at-now()))::integer)))
 into payload from private.push_subscriptions s join public.notifications n on n.id=item.notification_id cross join private.push_config c
 where s.id=item.subscription_id and c.id and c.private_key is not null;
 return payload;
end $$;

create function private.finish_message_push(p_delivery uuid,p_token text,p_outcome text)returns void language plpgsql security definer set search_path='' as $$
declare item private.message_push_deliveries;
begin
 if p_outcome not in('sent','expired','failed')then raise exception 'INVALID_PUSH';end if;
 select * into item from private.message_push_deliveries where id=p_delivery and status='sending'
 and token_hash=extensions.digest(p_token,'sha256') for update;
 if not found then return;end if;
 if p_outcome='expired'then delete from private.push_subscriptions where id=item.subscription_id;return;end if;
 update private.message_push_deliveries set status=case when p_outcome='sent'then 'sent'else 'failed'end,
 sent_at=case when p_outcome='sent'then now()else null end,token_hash=null,token_expires_at=null,next_attempt_at=now()+interval '5 minutes' where id=item.id;
end $$;

create function private.dispatch_message_push()returns integer language plpgsql security definer set search_path='' as $$
declare item record;secret text;amount integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barberup-message-push',0))then return 0;end if;
 if not exists(select 1 from private.push_config where id and private_key is not null)then return 0;end if;
 update private.message_push_deliveries set status='cancelled',token_hash=null
 where status in('pending','queued','sending','failed') and (expires_at<=now() or attempts>=4 or not private.message_push_valid(id));
 for item in select id from private.message_push_deliveries
 where status in('pending','queued','sending','failed') and attempts<4 and next_attempt_at<=now()
 order by next_attempt_at limit 20 for update skip locked loop
 secret:=gen_random_uuid()::text||gen_random_uuid()::text;
 update private.message_push_deliveries set status='queued',attempts=attempts+1,token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '5 minutes',next_attempt_at=now()+interval '5 minutes' where id=item.id;
 perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/appointment-push',
 headers:='{"Content-Type":"application/json"}'::jsonb,
 body:=jsonb_build_object('action','send','kind','message','delivery_id',item.id,'token',secret),timeout_milliseconds:=20000);
 amount:=amount+1;
 end loop;
 return amount;
end $$;

-- Internal helpers never become arbitrary client endpoints.
do $$
declare f record;
begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname in('message_is_staff','message_actor','message_name','message_reply_allowed','message_recipients','message_inbox','message_history','read_message_thread','send_direct_message','message_push_valid','claim_message_push','finish_message_push','dispatch_message_push')
 loop execute format('revoke all on function %s from public,anon,authenticated',f.signature);end loop;
end $$;

create function public.message_recipients(p_query text default '',p_offset integer default 0)returns jsonb language sql stable security invoker set search_path='' as $$select private.message_recipients(p_query,p_offset)$$;
create function public.message_inbox(p_offset integer default 0)returns jsonb language sql stable security invoker set search_path='' as $$select private.message_inbox(p_offset)$$;
create function public.message_history(p_thread uuid,p_before bigint default null)returns jsonb language sql stable security invoker set search_path='' as $$select private.message_history(p_thread,p_before)$$;
create function public.read_message_thread(p_thread uuid,p_through bigint)returns void language sql security invoker set search_path='' as $$select private.read_message_thread(p_thread,p_through)$$;
create function public.send_direct_message(p_body text,p_nonce uuid,p_thread uuid default null,p_client uuid default null)returns jsonb language sql security invoker set search_path='' as $$select private.send_direct_message(p_body,p_nonce,p_thread,p_client)$$;
create function public.claim_message_push(p_delivery uuid,p_token text)returns jsonb language sql security invoker set search_path='' as $$select private.claim_message_push(p_delivery,p_token)$$;
create function public.finish_message_push(p_delivery uuid,p_token text,p_outcome text)returns void language sql security invoker set search_path='' as $$select private.finish_message_push(p_delivery,p_token,p_outcome)$$;
revoke all on function public.message_recipients(text,integer),public.message_inbox(integer),public.message_history(uuid,bigint),public.read_message_thread(uuid,bigint),public.send_direct_message(text,uuid,uuid,uuid),public.claim_message_push(uuid,text),public.finish_message_push(uuid,text,text) from public,anon,authenticated;
grant execute on function public.message_recipients(text,integer),public.message_inbox(integer),public.message_history(uuid,bigint),public.read_message_thread(uuid,bigint),public.send_direct_message(text,uuid,uuid,uuid),private.message_recipients(text,integer),private.message_inbox(integer),private.message_history(uuid,bigint),private.read_message_thread(uuid,bigint),private.send_direct_message(text,uuid,uuid,uuid)to authenticated;
grant execute on function public.claim_message_push(uuid,text),public.finish_message_push(uuid,text,text),private.claim_message_push(uuid,text),private.finish_message_push(uuid,text,text)to service_role;
select cron.schedule('barberup-message-push','* * * * *','select private.dispatch_message_push();');
