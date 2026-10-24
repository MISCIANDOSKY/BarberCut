-- Separate push preference for messages; appointment reminder settings are unchanged.
alter table private.push_preferences add column messages_enabled boolean not null default true;

create or replace function private.set_message_push_enabled(p_enabled boolean)
returns void language plpgsql security definer set search_path=''
as $function$
declare u uuid:=private.require_push_user();
begin
 if p_enabled is null then raise exception 'INVALID_PUSH';end if;
 insert into private.push_preferences(user_id,enabled,messages_enabled)
 values(u,private.push_default_enabled(u),p_enabled)
 on conflict(user_id)do update set messages_enabled=excluded.messages_enabled,updated_at=now();
 if not p_enabled then
   update private.message_push_deliveries d set status='cancelled',token_hash=null,token_expires_at=null
   from private.push_subscriptions s where s.id=d.subscription_id and s.user_id=u and d.status in('pending','queued');
 end if;
end $function$;
create or replace function public.set_message_push_enabled(p_enabled boolean)
returns void language sql security invoker set search_path=''
as $function$select private.set_message_push_enabled(p_enabled)$function$;
revoke all on function private.set_message_push_enabled(boolean) from public,anon,authenticated;
revoke all on function public.set_message_push_enabled(boolean) from public,anon,authenticated;
grant execute on function private.set_message_push_enabled(boolean),public.set_message_push_enabled(boolean) to authenticated;

CREATE OR REPLACE FUNCTION private.push_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=private.require_push_user();
begin
 return jsonb_build_object('enabled',coalesce((select enabled from private.push_preferences where user_id=u),private.push_default_enabled(u)),
 'messages_enabled',coalesce((select messages_enabled from private.push_preferences where user_id=u),true),
 'public_key',(select public_key from private.push_config where id));
end $function$;

CREATE OR REPLACE FUNCTION private.send_direct_message(p_body text, p_nonce uuid, p_thread uuid DEFAULT NULL::uuid, p_client uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=private.message_actor();t private.message_threads;m private.direct_messages;recipient uuid;n uuid;stamp timestamptz;owner_id uuid;peer_id uuid;
begin
 if p_body is null or char_length(btrim(p_body)) not between 1 and 2000 or p_nonce is null then raise exception 'INVALID_MESSAGE';end if;
 perform pg_advisory_xact_lock(hashtextextended('message-sender:'||u::text,0));
 if p_thread is null then
   if not private.message_is_staff(u) or p_client is null or p_client=u then raise exception 'ACCESS_DENIED';end if;
   if not exists(select 1 from public.profiles p join public.user_roles r on r.user_id=p.id
    join auth.users a on a.id=p.id
    where p.id=p_client and a.deleted_at is null and (a.banned_until is null or a.banned_until<=now())
    and ((r.role='client' and exists(select 1 from private.client_memberships cm where cm.user_id=p.id))
      or private.message_admin_barber_pair(u,p_client))) then raise exception 'MESSAGE_CLIENT_UNAVAILABLE';end if;
   -- Admin is the stable first participant for internal staff conversations,
   -- whichever party writes first. Legacy parameter p_client means recipient.
   owner_id:=u;peer_id:=p_client;
   if private.message_admin_barber_pair(u,p_client) and exists(select 1 from public.user_roles where user_id=p_client and role='admin')then
     owner_id:=p_client;peer_id:=u;
   end if;
   insert into private.message_threads(staff_id,client_id)values(owner_id,peer_id)on conflict(staff_id,client_id)do nothing;
   select * into t from private.message_threads where staff_id=owner_id and client_id=peer_id for update;
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
 if private.message_admin_barber_pair(t.staff_id,t.client_id)then
   recipient:=case when u=t.staff_id then t.client_id else t.staff_id end;
 elsif u=t.staff_id then
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
 if coalesce((select enabled from private.push_preferences where user_id=recipient),private.push_default_enabled(recipient))
 and coalesce((select messages_enabled from private.push_preferences where user_id=recipient),true) then
 insert into private.message_push_deliveries(message_id,notification_id,subscription_id)
 select m.id,n,s.id from private.push_subscriptions s where s.user_id=recipient on conflict do nothing;
 end if;
 return jsonb_build_object('thread_id',t.id,'id',m.id::text);
end $function$;

CREATE OR REPLACE FUNCTION private.message_push_valid(p_delivery uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from private.message_push_deliveries d
 join private.direct_messages m on m.id=d.message_id
 join private.message_threads t on t.id=m.thread_id
 join private.push_subscriptions s on s.id=d.subscription_id
 join public.notifications n on n.id=d.notification_id and n.user_id=s.user_id
 join auth.users a on a.id=s.user_id
 where d.id=p_delivery and d.expires_at>now() and s.user_id in(t.staff_id,t.client_id) and s.user_id<>m.sender_id
 and m.id>case when s.user_id=t.staff_id then t.staff_read_id else t.client_read_id end
 and n.dismissed_at is null and a.deleted_at is null and a.email_confirmed_at is not null and(a.banned_until is null or a.banned_until<=now())
 and coalesce((select enabled from private.push_preferences where user_id=s.user_id),private.push_default_enabled(s.user_id))
 and coalesce((select messages_enabled from private.push_preferences where user_id=s.user_id),true));
$function$;
