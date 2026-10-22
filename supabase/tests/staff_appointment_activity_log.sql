begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare
 ad uuid:=gen_random_uuid(); worker uuid:=gen_random_uuid(); lead uuid:=gen_random_uuid();
 customer uuid:=gen_random_uuid(); shop uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
 bw uuid;bl uuid;s uuid;booking uuid;block_id uuid;uid uuid;permission boolean;payload jsonb;n int;idx int;
 session_key uuid:=gen_random_uuid();d date:=(now()at time zone 'Europe/Rome')::date;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (ad,'audit-admin@example.invalid',now(),'{"first_name":"TEST","last_name":"Admin"}'),
 (worker,'audit-worker@example.invalid',now(),'{"first_name":"TEST","last_name":"Worker"}'),
 (lead,'audit-lead@example.invalid',now(),'{"first_name":"TEST","last_name":"Lead"}'),
 (customer,'audit-client@example.invalid',now(),'{"first_name":"UnicoClienteAudit","last_name":"Ricerca"}'),
 (shop,'audit-shop@example.invalid',now(),'{"first_name":"TEST","last_name":"Barberia"}'),
 (outsider,'audit-outsider@example.invalid',now(),'{}');
 update public.user_roles set role='admin' where user_id=ad;
 update public.user_roles set role='shop' where user_id=shop;
 insert into public.barbers(name,user_id) values('TEST audit worker',worker) returning id into bw;
 insert into public.barbers(name,user_id) values('TEST audit lead',lead) returning id into bl;
 update public.user_roles set role='barber_admin' where user_id=lead;
 insert into public.services(name,duration_minutes,price) values('TEST audit service',30,20) returning id into s;
 insert into auth.sessions(id,user_id,created_at,updated_at) values(session_key,shop,now(),now());
 perform public.staff_authorize_session(ad,'audit-admin');
 perform public.staff_authorize_session(worker,'audit-worker');
 perform public.staff_authorize_session(lead,'audit-lead');
 -- Database capture is independent of front-end events and retains deletions.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','audit-worker')::text,true);
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by)
 values(bw,'appointment',customer,s,now()+interval '5 days',now()+interval '5 days 30 minutes','TEST audit service',20,worker) returning id into booking;
 update public.calendar_entries set start_at=start_at+interval '1 hour',end_at=end_at+interval '1 hour' where id=booking;
 perform public.cancel_appointment(booking);
 perform public.cancel_appointment(booking); -- repeated cancellation does not create another event
 update public.calendar_entries set status='confirmed' where id=booking;
 update public.calendar_entries set price=25,notes='TEST audit note' where id=booking;
 update public.calendar_entries set updated_at=now() where id=booking;
 if (select count(*) from private.appointment_logs where entry_id=booking)<>5 then raise exception 'Missing events or duplicate no-op';end if;
 if not exists(select 1 from private.appointment_logs where entry_id=booking and action='rescheduled' and before_state->>'start_at' is distinct from after_state->>'start_at') then raise exception 'Move details missing';end if;
 if exists(select 1 from private.appointment_logs where entry_id=booking and (before_state::text||coalesce(after_state::text,''))like '%UnicoClienteAudit%') then raise exception 'Customer data duplicated';end if;
 -- Shop mutations are captured too, normal login session, without a staff OTP.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',shop,'role','authenticated','session_id',session_key)::text,true);
 perform public.cancel_appointment(booking);
 if not exists(select 1 from private.appointment_logs where entry_id=booking and actor_id=shop and action='cancelled')then raise exception 'Shop action missing';end if;
 -- All viewing is permission-controlled, no anonymous access, direct writes or caller-supplied actor.
 foreach uid in array array[worker,customer,shop,outsider] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated','session_id',case when uid=shop then session_key::text else 'audit-worker' end)::text,true);
  set local role authenticated;
  if public.can_view_appointment_log() then raise exception 'Unexpected initial access';end if;
  begin perform public.appointment_activity_log(d);raise exception 'Read allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  begin perform public.search_appointment_activity_log('audit');raise exception 'Search allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  begin perform public.appointment_log_access_users();raise exception 'List allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  begin perform public.set_appointment_log_access(worker,true);raise exception 'Grant allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','unverified')::text,true);
 set local role authenticated;
 if public.can_view_appointment_log() then raise exception 'Unverified lead access';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','audit-lead')::text,true);
 set local role authenticated;
 if not public.can_view_appointment_log() then raise exception 'Lead default denied';end if;
 payload:=public.search_appointment_activity_log('UnicoClienteAudit ha spostato un appuntamento');
 if jsonb_array_length(payload->'entries')<>1 then raise exception 'Search name and event failed';end if;
 if exists(select 1 from jsonb_array_elements(public.appointment_activity_log(d+1)->'entries') x where (x->>'entry_id')::uuid=booking)then raise exception 'Wrong operation date';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','audit-admin')::text,true);
 set local role authenticated;
 if exists(select 1 from public.appointment_log_access_users()where user_id=customer)then raise exception 'Client listed';end if;
 begin perform public.set_appointment_log_access(customer,true);raise exception 'Client granted';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 perform public.set_appointment_log_access(worker,true);
 perform public.set_appointment_log_access(shop,true);
 perform public.set_appointment_log_access(lead,false);
 if not public.can_view_appointment_log()then raise exception 'Admin disabled';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','audit-worker')::text,true);
 set local role authenticated;
 if not public.can_view_appointment_log()then raise exception 'Worker grant ineffective';end if;
 perform public.appointment_activity_log(d);
 begin perform 1 from private.appointment_logs;raise exception 'Direct table exposed';exception when insufficient_privilege then null;end;
 begin perform public.search_appointment_activity_log('a');raise exception 'Short search';exception when raise_exception then if sqlerrm<>'INVALID_SEARCH'then raise;end if;end;
 reset role;
 -- Pagination with a stable cursor, physical deletion preserved.
 for idx in 1..55 loop update public.calendar_entries set price=100+idx where id=booking;end loop;
 delete from public.calendar_entries where id=booking;
 if not exists(select 1 from private.appointment_logs where entry_id=booking and action='deleted'and after_state is null)then raise exception 'Delete history lost';end if;
 set local role authenticated;
 payload:=public.search_appointment_activity_log('unicoclienteaudit');
 if jsonb_array_length(payload->'entries')<>50 or not(payload->>'has_more')::boolean then raise exception 'Pagination first page';end if;
 payload:=public.search_appointment_activity_log('unicoclienteaudit',(payload->'entries'->49->>'id')::bigint);
 if jsonb_array_length(payload->'entries')<>12 or (payload->>'has_more')::boolean then raise exception 'Pagination second page';end if;
 reset role;
 -- System/client/Admin activity must not be captured.
 perform set_config('request.jwt.claims','{}',true);
 insert into public.calendar_entries(barber_id,kind,start_at,end_at,notes)values(bw,'block',now()+interval '9 days',now()+interval '9 days 1 hour','TEST block')returning id into block_id;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated')::text,true);
 update public.calendar_entries set notes='TEST client'where id=block_id;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','audit-admin')::text,true);
 update public.calendar_entries set notes='TEST Admin'where id=block_id;
 if exists(select 1 from private.appointment_logs where entry_id=block_id)then raise exception 'Excluded actor logged';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','audit-lead')::text,true);
 update public.calendar_entries set notes='TEST lead'where id=block_id;
 if not exists(select 1 from private.appointment_logs where entry_id=block_id and actor_role='barber_admin')then raise exception 'Lead mutation not logged after viewing revoked';end if;
 set local role authenticated;
 if public.can_view_appointment_log()then raise exception 'Lead revocation ineffective';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',shop,'role','authenticated','session_id',session_key)::text,true);
 set local role authenticated;
 if not public.can_view_appointment_log()then raise exception 'Shop grant ineffective';end if;
 reset role;
 if has_function_privilege('anon','public.appointment_activity_log(date,bigint)','execute')
 or has_function_privilege('anon','public.search_appointment_activity_log(text,bigint)','execute')
 or has_function_privilege('authenticated','private.capture_appointment_log()','execute') then raise exception 'Unexpected grants';end if;
end $test$;
select 'PASS capture, role filters, cancelled/deleted history, default access, admin grants/revocation, client exclusion, search and cursor pagination' result;
rollback;
