begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare
 client uuid:=gen_random_uuid(); worker uuid:=gen_random_uuid(); ad uuid:=gen_random_uuid();
 own_notice uuid; other_notice uuid; ap uuid; b uuid; service uuid; reminder uuid; removed integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (client,'delete-notification-client@example.invalid',now(),'{}'),
 (worker,'delete-notification-worker@example.invalid',now(),'{}'),
 (ad,'delete-notification-admin@example.invalid',now(),'{}');
 update public.user_roles set role='admin' where user_id=ad;
 insert into public.barbers(name,user_id) values('Notifications worker',worker) returning id into b;
 insert into public.services(name,duration_minutes,price) values('Notification test',15,10) returning id into service;
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)
 values(b,'appointment',client,service,now()+interval '30 minutes',now()+interval '45 minutes','Notification test',10) returning id into ap;
 perform private.appointment_reminders();
 select id into strict reminder from public.notifications where event_key like ap::text||':1h:%';
 insert into public.notifications(user_id,title,body) values(client,'Own notification','Test') returning id into own_notice;
 insert into public.notifications(user_id,title,body) values(worker,'Other notification','Test') returning id into other_notice;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',client,'role','authenticated')::text,true);
 set local role authenticated;
 removed:=public.dismiss_notifications(other_notice);
 if removed<>0 then raise exception 'Foreign notification dismissed';end if;
 removed:=public.dismiss_notifications(own_notice);
 if removed<>1 or exists(select 1 from public.notifications where id=own_notice) then raise exception 'Single dismissal failed';end if;
 if not exists(select 1 from public.notifications where id=reminder) then raise exception 'Other own notification disappeared';end if;
 -- The protected column cannot be changed directly or used to restore a dismissal.
 begin update public.notifications set dismissed_at=null where id=own_notice;raise exception 'Client changed protected column';exception when insufficient_privilege then null;end;
 reset role;
 insert into public.notifications(user_id,title,body) select client,'Many notifications','Test' from generate_series(1,150);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',client,'role','authenticated')::text,true);
 set local role authenticated;
 removed:=public.dismiss_notifications();
 if removed<>151 then raise exception 'Delete-all missed notifications beyond UI limit: %',removed;end if;
 if exists(select 1 from public.notifications where user_id=client) then raise exception 'Deleted notifications still visible';end if;
 if public.dismiss_notifications()<>0 then raise exception 'Repeat all dismissal not idempotent';end if;
 reset role;
 perform private.appointment_reminders();
 if (select count(*) from public.notifications where event_key like ap::text||':1h:%')<>1
   or not exists(select 1 from public.notifications where id=reminder and dismissed_at is not null and read_at is not null) then raise exception 'Dismissed reminder recreated';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 set local role authenticated;
 if not exists(select 1 from public.notifications where id=other_notice) then raise exception 'Other account affected';end if;
 perform public.dismiss_notifications(other_notice);
 perform public.dismiss_notifications();
 reset role;
 update public.user_roles set role='barber_admin' where user_id=worker;
 insert into public.notifications(user_id,title,body) values(worker,'Lead notification','Test');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated')::text,true);
 set local role authenticated;
 if public.dismiss_notifications()<>1 then raise exception 'Lead dismissal failed';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated')::text,true);
 set local role authenticated;
 if public.dismiss_notifications(other_notice)<>0 then raise exception 'Personal RPC allowed admin to dismiss other account';end if;
 reset role;
 if has_function_privilege('anon','public.dismiss_notifications(uuid)','execute') then raise exception 'Anonymous execution granted';end if;
end $test$;
rollback;
