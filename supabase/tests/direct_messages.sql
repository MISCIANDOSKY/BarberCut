begin;
do $test$
declare
 worker uuid:=gen_random_uuid();lead uuid:=gen_random_uuid();ad uuid:=gen_random_uuid();customer uuid:=gen_random_uuid();other_client uuid:=gen_random_uuid();shop uuid:=gen_random_uuid();
 sw uuid:=gen_random_uuid();sl uuid:=gen_random_uuid();sa uuid:=gen_random_uuid();sc uuid:=gen_random_uuid();so uuid:=gen_random_uuid();ss uuid:=gen_random_uuid();
 b uuid;t uuid;nonce uuid:=gen_random_uuid();sent jsonb;again jsonb;reply jsonb;hist jsonb;firstmsg bigint;latest bigint;sub uuid;delivery uuid;secret text:=gen_random_uuid()::text||gen_random_uuid()::text;ts timestamptz;uid uuid;sid uuid;count_before bigint;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)values
 (worker,'message-worker@example.invalid',now(),'{"first_name":"TEST","last_name":"Worker"}'),
 (lead,'message-lead@example.invalid',now(),'{"first_name":"TEST","last_name":"Lead"}'),
 (ad,'message-admin@example.invalid',now(),'{"first_name":"TEST","last_name":"Admin"}'),
 (customer,'message-client@example.invalid',now(),'{"first_name":"TEST","last_name":"Client"}'),
 (other_client,'message-outsider@example.invalid',now(),'{"first_name":"TEST","last_name":"Other"}'),
 (shop,'message-shop@example.invalid',now(),'{}');
 update public.user_roles set role='admin'where user_id=ad;
 update public.user_roles set role='shop'where user_id=shop;
 insert into public.barbers(name,user_id)values('TEST Messages Worker',worker)returning id into b;
 insert into public.barbers(name,user_id)values('TEST Messages Lead',lead);
 update public.user_roles set role='barber_admin'where user_id=lead;
 insert into auth.sessions(id,user_id,created_at,updated_at)values
 (sw,worker,now(),now()),(sl,lead,now(),now()),(sa,ad,now(),now()),(sc,customer,now(),now()),(so,other_client,now(),now()),(ss,shop,now(),now());
 insert into public.terms_acceptances(user_id,terms_id)
 select x,terms.id from unnest(array[worker,lead,ad,customer,other_client,shop])x cross join public.terms_versions terms where terms.published on conflict do nothing;
 perform public.staff_authorize_session(worker,sw::text);
 perform public.staff_authorize_session(lead,sl::text);
 perform public.staff_authorize_session(ad,sa::text);
 if has_table_privilege('authenticated','private.direct_messages','SELECT,INSERT,UPDATE,DELETE') or has_table_privilege('anon','private.message_threads','SELECT') then raise exception 'Direct client access';end if;
 if has_function_privilege('authenticated','public.claim_message_push(uuid,text)','EXECUTE') or has_function_privilege('anon','public.send_direct_message(text,uuid,uuid,uuid)','EXECUTE') then raise exception 'Unexpected execute';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 begin perform public.send_direct_message('Start forbidden',gen_random_uuid(),null,worker);raise exception 'Client started';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.message_recipients('TEST');raise exception 'Client searched';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 -- Queue only fake subscriptions within this rolled-back transaction, never dispatch.
 insert into private.push_preferences(user_id,enabled)values(customer,true)on conflict(user_id)do update set enabled=true;
 insert into private.push_subscriptions(user_id,endpoint,p256dh,auth_key)values(customer,'https://fcm.googleapis.com/fcm/send/message-test-'||customer::text,'test-key','test-auth')returning id into sub;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id',sw)::text,true);
 set local role authenticated;
 if not (public.message_inbox()->>'can_start')::boolean then raise exception 'Staff cannot initiate';end if;
 sent:=public.send_direct_message(E'TEST anteprima 😀\nseconda riga '||repeat('testo ',50),nonce,null,customer);
 again:=public.send_direct_message(E'TEST anteprima 😀\nseconda riga '||repeat('testo ',50),nonce,null,customer);
 if sent<>again then raise exception 'Idempotency failed';end if;
 t:=(sent->>'thread_id')::uuid;firstmsg:=(sent->>'id')::bigint;
 begin perform public.send_direct_message('Different',nonce,t);raise exception 'Nonce reused';exception when raise_exception then if sqlerrm<>'INVALID_MESSAGE'then raise;end if;end;
 begin perform public.send_direct_message('  ',gen_random_uuid(),t);raise exception 'Blank accepted';exception when raise_exception then if sqlerrm<>'INVALID_MESSAGE'then raise;end if;end;
 begin perform public.send_direct_message(repeat('x',2001),gen_random_uuid(),t);raise exception 'Long accepted';exception when raise_exception then if sqlerrm<>'INVALID_MESSAGE'then raise;end if;end;
 hist:=public.message_history(t);
 if jsonb_array_length(hist->'items')<>1 then raise exception 'Duplicate message';end if;
 reset role;
 if not exists(select 1 from public.notifications n join private.direct_messages m on n.event_key='message:'||m.id::text where m.id=firstmsg and n.body=left(regexp_replace(m.body,'[[:space:]]+',' ','g'),180) and char_length(n.body)=180 and strpos(n.body,E'\n')=0)then raise exception 'Notification preview invalid';end if;
 select id into delivery from private.message_push_deliveries where message_id=firstmsg and subscription_id=sub;
 if delivery is null or not private.message_push_valid(delivery)then raise exception 'Push not queued';end if;
 select last_staff_at into ts from private.message_threads where id=t;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 hist:=public.message_history(t);
 if not (hist->>'can_send')::boolean then raise exception 'Same-day reply closed';end if;
 reply:=public.send_direct_message('TEST client reply',gen_random_uuid(),t);
 perform public.read_message_thread(t,(reply->>'id')::bigint);
 reset role;
 if (select last_staff_at from private.message_threads where id=t)<>ts then raise exception 'Client extended reply window';end if;
 if private.message_push_valid(delivery)then raise exception 'Read message still pushable';end if;
 if not exists(select 1 from public.notifications where user_id=worker and event_key='message:'||(reply->>'id')) then raise exception 'Reply notification missing';end if;
 update private.message_threads set last_staff_at=now()-interval '1 day'where id=t;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 if (public.message_history(t)->>'can_send')::boolean then raise exception 'Expired composer open';end if;
 begin perform public.send_direct_message('Late reply',gen_random_uuid(),t);raise exception 'Expired reply allowed';exception when raise_exception then if sqlerrm<>'MESSAGE_REPLY_CLOSED'then raise;end if;end;
 reset role;
 -- Italian midnight boundaries, including daylight saving transitions.
 if private.message_reply_allowed('2026-10-23T21:59:00Z','2026-10-23T22:00:00Z')then raise exception 'Summer midnight failed';end if;
 if not private.message_reply_allowed('2026-10-25T00:00:00Z','2026-10-25T22:59:59Z')then raise exception 'DST same day failed';end if;
 if private.message_reply_allowed('2026-10-25T22:59:59Z','2026-10-25T23:00:00Z')then raise exception 'Winter midnight failed';end if;
 -- Outsider cannot read, reply, or mark another customer's conversation.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_client,'role','authenticated','session_id',so)::text,true);
 set local role authenticated;
 if jsonb_array_length(public.message_inbox()->'items')<>0 then raise exception 'Leaked inbox';end if;
 begin perform public.message_history(t);raise exception 'Other history read';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.read_message_thread(t,firstmsg);raise exception 'Other marked read';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.send_direct_message('Spoof',gen_random_uuid(),t);raise exception 'Other replied';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id',sw)::text,true);
 set local role authenticated;
 sent:=public.send_direct_message('TEST reopen',gen_random_uuid(),t);
 reset role;
 -- Push claim uses a short-lived token and never accepts an arbitrary recipient.
 latest:=(sent->>'id')::bigint;
 select id into delivery from private.message_push_deliveries where message_id=latest and subscription_id=sub;
 update private.message_push_deliveries set status='queued',token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '5 minutes'where id=delivery;
 if public.claim_message_push(delivery,'incorrect') is not null then raise exception 'Bad token accepted';end if;
 hist:=public.claim_message_push(delivery,secret);
 if hist->'payload'->>'body'<>'TEST reopen' then raise exception 'Push text preview missing';end if;
 if hist->'payload'->>'kind'<>'message' or (select status from private.message_push_deliveries where id=delivery)<>'sending'then raise exception 'Message claim failed';end if;
 perform public.finish_message_push(delivery,secret,'sent');
 if (select status from private.message_push_deliveries where id=delivery)<>'sent'then raise exception 'Finish failed';end if;

 -- Message-only opt-out must leave global push/subscription/reminders available.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 if not(public.push_settings()->>'messages_enabled')::boolean then raise exception 'Message default not enabled';end if;
 perform public.set_message_push_enabled(false);
 hist:=public.push_settings();
 if (hist->>'messages_enabled')::boolean or not(hist->>'enabled')::boolean then raise exception 'Message opt-out altered global preference';end if;
 begin perform public.set_message_push_enabled(null);raise exception 'Null preference accepted';exception when raise_exception then if sqlerrm<>'INVALID_PUSH'then raise;end if;end;
 reset role;
 if not exists(select 1 from private.push_subscriptions where id=sub)then raise exception 'Message opt-out removed subscription';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id',sw)::text,true);
 set local role authenticated;
 sent:=public.send_direct_message('TEST only message push off',gen_random_uuid(),t);
 reset role;
 if exists(select 1 from private.message_push_deliveries where message_id=(sent->>'id')::bigint)then raise exception 'Message opt-out queued push';end if;
 if not exists(select 1 from public.notifications where user_id=customer and event_key='message:'||(sent->>'id'))then raise exception 'Message opt-out removed in-app notification';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 perform public.set_message_push_enabled(true);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id',sw)::text,true);
 set local role authenticated;
 sent:=public.send_direct_message('TEST message push restored',gen_random_uuid(),t);
 reset role;
 select id into delivery from private.message_push_deliveries where message_id=(sent->>'id')::bigint and subscription_id=sub;
 if delivery is null or not private.message_push_valid(delivery)then raise exception 'Message preference not restored';end if;
 -- Queued but unsent messages are suppressed immediately when disabled.
 update private.message_push_deliveries set status='queued',token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '5 minutes' where id=delivery;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 perform public.set_message_push_enabled(false);
 reset role;
 if private.message_push_valid(delivery) or (select status from private.message_push_deliveries where id=delivery)<>'cancelled' then raise exception 'Queued push survived opt-out';end if;
 if public.claim_message_push(delivery,secret) is not null then raise exception 'Cancelled push claimed';end if;
 -- No preference row: changing message preference must preserve staff default (global off).
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id',sl)::text,true);
 set local role authenticated;
 perform public.set_message_push_enabled(false);
 if(public.push_settings()->>'enabled')::boolean then raise exception 'Message toggle enabled staff push';end if;
 perform public.set_message_push_enabled(true);
 if(public.push_settings()->>'enabled')::boolean then raise exception 'Message re-enable altered global off';end if;
 reset role;
 if has_function_privilege('anon','public.set_message_push_enabled(boolean)','EXECUTE') then raise exception 'Anonymous preference access';end if;

 -- Global push opt-out leaves messages/in-app notifications but no new push.
 update private.push_preferences set enabled=false where user_id=customer;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id',sw)::text,true);
 set local role authenticated;
 sent:=public.send_direct_message('TEST push disabled',gen_random_uuid(),t);
 reset role;
 if exists(select 1 from private.message_push_deliveries where message_id=(sent->>'id')::bigint) then raise exception 'Push opt-out ignored';end if;
 if not exists(select 1 from private.direct_messages where id=(sent->>'id')::bigint)then raise exception 'Opt-out deleted message';end if;
 -- Admin and lead initiate independently; another barber cannot see the worker thread.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id',sl)::text,true);
 set local role authenticated;
 begin perform public.message_history(t);raise exception 'Other staff read';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 sent:=public.send_direct_message('TEST lead',gen_random_uuid(),null,customer);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id',sa)::text,true);
 set local role authenticated;
 sent:=public.send_direct_message('TEST admin',gen_random_uuid(),null,customer);
 reset role;

 -- Admin and both barber roles can initiate and respond in either direction.
 -- The Admin is the canonical first participant, so reverse initiation reuses the same thread.
 foreach uid in array array[worker,lead] loop
   sid:=case when uid=worker then sw else sl end;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated','session_id',sid)::text,true);
   set local role authenticated;
   if not exists(select 1 from jsonb_array_elements(public.message_recipients('TEST'))x where x->>'id'=ad::text)then raise exception 'Admin not searchable by barber';end if;
   sent:=public.send_direct_message('TEST barber to admin',gen_random_uuid(),null,ad);
   hist:=public.message_history((sent->>'thread_id')::uuid);
   if not(hist->>'can_send')::boolean or hist->'reply_until'<>'null'::jsonb then raise exception 'Staff composer restricted';end if;
   if hist->>'client_id'<>ad::text then raise exception 'Barber peer metadata wrong';end if;
   if not exists(select 1 from jsonb_array_elements(public.message_inbox()->'items')x where x->>'id'=sent->>'thread_id' and x->>'client_id'=ad::text)then raise exception 'Barber inbox peer wrong';end if;
   reset role;
   if not exists(select 1 from public.notifications where user_id=ad and event_key='message:'||(sent->>'id'))then raise exception 'Admin notification missing';end if;
   update private.message_threads set last_staff_at=now()-interval '2 days' where id=(sent->>'thread_id')::uuid;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id',sa)::text,true);
   set local role authenticated;
   if not exists(select 1 from jsonb_array_elements(public.message_recipients('TEST'))x where x->>'id'=uid::text)then raise exception 'Barber not searchable by admin';end if;
   again:=public.send_direct_message('TEST admin to barber',gen_random_uuid(),null,uid);
   if sent->>'thread_id'<>again->>'thread_id'then raise exception 'Duplicate staff conversation';end if;
   perform public.send_direct_message('TEST admin reply',gen_random_uuid(),(sent->>'thread_id')::uuid);
   reset role;
   if not exists(select 1 from public.notifications where user_id=uid and event_key='message:'||(again->>'id'))then raise exception 'Barber notification missing';end if;
   update private.message_threads set last_staff_at=now()-interval '2 days' where id=(sent->>'thread_id')::uuid;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated','session_id',sid)::text,true);
   set local role authenticated;
   if not(public.message_history((sent->>'thread_id')::uuid)->>'can_send')::boolean then raise exception 'Staff reply expired';end if;
   perform public.send_direct_message('TEST barber late reply',gen_random_uuid(),(sent->>'thread_id')::uuid);
   reset role;
   -- A different barber is not a participant in this Admin conversation.
   perform set_config('request.jwt.claims',jsonb_build_object('sub',case when uid=worker then lead else worker end,'role','authenticated','session_id',case when uid=worker then sl else sw end)::text,true);
   set local role authenticated;
   begin perform public.message_history((sent->>'thread_id')::uuid);raise exception 'Staff conversation leaked';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
   reset role;
 end loop;
 -- Admin-first creation after removing only test internal threads; both barber roles can reply.
 delete from private.message_threads where staff_id=ad and client_id in(worker,lead);
 foreach uid in array array[worker,lead] loop
   perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id',sa)::text,true);
   set local role authenticated;
   sent:=public.send_direct_message('TEST admin starts',gen_random_uuid(),null,uid);
   reset role;
   sid:=case when uid=worker then sw else sl end;
   perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated','session_id',sid)::text,true);
   set local role authenticated;
   again:=public.send_direct_message('TEST barber responds',gen_random_uuid(),null,ad);
   if sent->>'thread_id'<>again->>'thread_id'then raise exception 'Admin-first duplicated';end if;
   reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 begin perform public.send_direct_message('Client cannot initiate to admin',gen_random_uuid(),null,ad);raise exception 'Client initiated to admin';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.message_history((sent->>'thread_id')::uuid);raise exception 'Client read staff conversation';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;


 -- Local removal is private and never deletes message content.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 begin perform public.hide_message_threads();raise exception 'Client bulk removal allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 perform public.hide_message_threads(t);
 if jsonb_array_length(public.message_history(t)->'items')<>0 then raise exception 'Hidden history still visible';end if;
 if exists(select 1 from jsonb_array_elements(public.message_inbox()->'items')x where x->>'id'=t::text)then raise exception 'Hidden chat still listed';end if;
 begin perform public.save_maintenance_message_settings(120,550,true,true,3);raise exception 'Client changed retention';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 if not exists(select 1 from private.direct_messages where id=firstmsg)then raise exception 'Local removal deleted server content';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_client,'role','authenticated','session_id',so)::text,true);
 set local role authenticated;
 begin perform public.hide_message_threads(t);raise exception 'Outsider removed chat';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id',sw)::text,true);
 set local role authenticated;
 if jsonb_array_length(public.message_history(t)->'items')=0 then raise exception 'Peer history removed';end if;
 sent:=public.send_direct_message('TEST new message after removal',gen_random_uuid(),t);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 hist:=public.message_history(t);
 if jsonb_array_length(hist->'items')<>1 or hist->'items'->0->>'id'<>sent->>'id'then raise exception 'Old history reappeared';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id',sw)::text,true);
 set local role authenticated;
 perform public.hide_message_threads();
 if jsonb_array_length(public.message_inbox()->'items')<>0 then raise exception 'Staff bulk removal failed';end if;
 reset role;
 -- Retention uses months since sending; admin setting is validated and daily cleanup removes only old content.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id',sa)::text,true);
 set local role authenticated;
 begin perform public.save_maintenance_message_settings(120,550,false,false,0);raise exception 'Invalid months accepted';exception when raise_exception then if sqlerrm<>'INVALID_MESSAGE_RETENTION'then raise;end if;end;
 perform public.save_maintenance_message_settings(120,550,false,false,1);
 if (public.maintenance_status()->'settings'->>'message_months')::integer<>1 then raise exception 'Retention not saved';end if;
 reset role;
 update private.direct_messages set created_at=now()-interval '2 months' where id=firstmsg;
 hist:=private.run_daily_maintenance();
 if (hist->>'deleted_messages')::integer<1 or exists(select 1 from private.direct_messages where id=firstmsg)then raise exception 'Daily cleanup failed';end if;
 if exists(select 1 from public.notifications where event_key='message:'||firstmsg::text)then raise exception 'Old message notification retained';end if;
 if not exists(select 1 from private.direct_messages where id=(sent->>'id')::bigint)then raise exception 'Recent message deleted';end if;
 if has_function_privilege('authenticated','private.purge_old_messages()','EXECUTE') or has_function_privilege('anon','public.hide_message_threads(uuid)','EXECUTE') then raise exception 'Cleanup privileges exposed';end if;

 -- Shop role and revoked/missing sessions cannot use messaging.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',shop,'role','authenticated','session_id',ss)::text,true);
 set local role authenticated;
 begin perform public.message_inbox();raise exception 'Shop allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 delete from auth.sessions where id=sc;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 begin perform public.set_message_push_enabled(true);raise exception 'Revoked session changed preference';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.message_inbox();raise exception 'Revoked session allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 delete from public.profiles where id=customer;
 if exists(select 1 from private.message_threads where client_id=customer) or exists(select 1 from private.direct_messages where thread_id=t)then raise exception 'Deletion cascade missing';end if;
end $test$;
select 'PASS: messaging permissions, midnight/DST, idempotency, push preferences, tokens and deletion' as result;
rollback;