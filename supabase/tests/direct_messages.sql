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
 sent:=public.send_direct_message('TEST first message',nonce,null,customer);
 again:=public.send_direct_message('TEST first message',nonce,null,customer);
 if sent<>again then raise exception 'Idempotency failed';end if;
 t:=(sent->>'thread_id')::uuid;firstmsg:=(sent->>'id')::bigint;
 begin perform public.send_direct_message('Different',nonce,t);raise exception 'Nonce reused';exception when raise_exception then if sqlerrm<>'INVALID_MESSAGE'then raise;end if;end;
 begin perform public.send_direct_message('  ',gen_random_uuid(),t);raise exception 'Blank accepted';exception when raise_exception then if sqlerrm<>'INVALID_MESSAGE'then raise;end if;end;
 begin perform public.send_direct_message(repeat('x',2001),gen_random_uuid(),t);raise exception 'Long accepted';exception when raise_exception then if sqlerrm<>'INVALID_MESSAGE'then raise;end if;end;
 hist:=public.message_history(t);
 if jsonb_array_length(hist->'items')<>1 then raise exception 'Duplicate message';end if;
 reset role;
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
 if hist->'payload'->>'kind'<>'message' or (select status from private.message_push_deliveries where id=delivery)<>'sending'then raise exception 'Message claim failed';end if;
 perform public.finish_message_push(delivery,secret,'sent');
 if (select status from private.message_push_deliveries where id=delivery)<>'sent'then raise exception 'Finish failed';end if;
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
 -- Shop role and revoked/missing sessions cannot use messaging.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',shop,'role','authenticated','session_id',ss)::text,true);
 set local role authenticated;
 begin perform public.message_inbox();raise exception 'Shop allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 delete from auth.sessions where id=sc;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',sc)::text,true);
 set local role authenticated;
 begin perform public.message_inbox();raise exception 'Revoked session allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 delete from public.profiles where id=customer;
 if exists(select 1 from private.message_threads where client_id=customer) or exists(select 1 from private.direct_messages where thread_id=t)then raise exception 'Deletion cascade missing';end if;
end $test$;
select 'PASS: messaging permissions, midnight/DST, idempotency, push preferences, tokens and deletion' as result;
rollback;