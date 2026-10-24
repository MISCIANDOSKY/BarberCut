create or replace function private.message_admin_barber_pair(p_left uuid,p_right uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
 select p_left<>p_right and private.message_is_staff(p_left) and private.message_is_staff(p_right)
 and exists(select 1 from public.user_roles a join public.user_roles b on b.user_id=p_right
 where a.user_id=p_left and ((a.role='admin' and b.role in('barber','barber_admin')) or (b.role='admin' and a.role in('barber','barber_admin'))));
$function$;
revoke all on function private.message_admin_barber_pair(uuid,uuid) from public,anon,authenticated;

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
 if coalesce((select enabled from private.push_preferences where user_id=recipient),private.push_default_enabled(recipient)) then
 insert into private.message_push_deliveries(message_id,notification_id,subscription_id)
 select m.id,n,s.id from private.push_subscriptions s where s.user_id=recipient on conflict do nothing;
 end if;
 return jsonb_build_object('thread_id',t.id,'id',m.id::text);
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
 'can_send',allowed,'can_start',private.message_is_staff(u),'server_time',now(),
 'reply_until',case when private.message_admin_barber_pair(t.staff_id,t.client_id) or t.last_staff_at is null then null else (((t.last_staff_at at time zone 'Europe/Rome')::date+1)::timestamp at time zone 'Europe/Rome')end,
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',m.id::text,'body',m.body,'own',m.sender_id=u,'created_at',m.created_at) order by m.id)
 from(select * from private.direct_messages where thread_id=t.id and(p_before is null or id<p_before) order by id desc limit 100)m),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION private.message_inbox(p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=private.message_actor();
begin
 if p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'INVALID_MESSAGE';end if;
 return jsonb_build_object('can_start',private.message_is_staff(u),'server_time',now(),'items',coalesce((
 select jsonb_agg(jsonb_build_object('id',t.id,'client_id',case when t.staff_id=u then t.client_id else t.staff_id end,
 'name',private.message_name(case when t.staff_id=u then t.client_id else t.staff_id end),
 'last_body',left(m.body,120),'last_at',m.created_at,
 'unread',(select count(*) from private.direct_messages d where d.thread_id=t.id and d.sender_id<>u and
 d.id>case when t.staff_id=u then t.staff_read_id else t.client_read_id end)))
 from (select * from private.message_threads where staff_id=u or client_id=u order by updated_at desc,id limit 100 offset p_offset)t
 join lateral(select body,created_at from private.direct_messages where thread_id=t.id order by id desc limit 1)m on true
 ),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION private.message_recipients(p_query text DEFAULT ''::text, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=private.message_actor();
begin
 if not private.message_is_staff(u) then raise exception 'ACCESS_DENIED';end if;
 if p_offset is null or p_offset<0 or p_offset>100000 or char_length(coalesce(p_query,''))>100 then raise exception 'INVALID_MESSAGE';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from (
 select p.id,private.message_name(p.id) name from public.profiles p
 join public.user_roles r on r.user_id=p.id
 join auth.users a on a.id=p.id and a.deleted_at is null and (a.banned_until is null or a.banned_until<=now())
 where p.id<>u and ((r.role='client' and exists(select 1 from private.client_memberships cm where cm.user_id=p.id))
 or private.message_admin_barber_pair(u,p.id)) and char_length(btrim(coalesce(p_query,'')))>=2 and
 (strpos(lower(p.first_name||' '||p.last_name),lower(btrim(p_query)))>0 or strpos(p.phone,btrim(p_query))>0)
 order by lower(p.first_name),lower(p.last_name),p.id limit 30 offset p_offset
 )q),'[]'::jsonb);
end $function$;