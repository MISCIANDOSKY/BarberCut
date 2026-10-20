begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare customer uuid:=gen_random_uuid(); other_customer uuid:=gen_random_uuid(); worker uuid:=gen_random_uuid();
 session_customer uuid:=gen_random_uuid(); session_other uuid:=gen_random_uuid();
 b uuid; svc uuid; ap uuid; job uuid; offsets integer[];
 sub jsonb:=jsonb_build_object('endpoint','https://fcm.googleapis.com/fcm/send/'||gen_random_uuid()::text,'keys',jsonb_build_object('p256dh',repeat('A',87),'auth',repeat('A',22)));
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values(customer,customer::text||'@reminder.invalid',now(),'{}'),(other_customer,other_customer::text||'@reminder.invalid',now(),'{}'),(worker,worker::text||'@reminder.invalid',now(),'{}');
 insert into auth.sessions(id,user_id) values(session_customer,customer),(session_other,other_customer);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',session_customer)::text,true);
 set local role authenticated;
 if public.reminder_settings()->'offsets'<>'[60,1440]'::jsonb then raise exception 'Wrong defaults';end if;
 perform public.register_push_subscription(sub);
 begin perform public.save_reminder_settings(array[0]);raise exception 'Zero offset accepted';exception when raise_exception then if sqlerrm<>'INVALID_REMINDERS' then raise;end if;end;
 begin perform public.save_reminder_settings(array[30]);raise exception 'Custom minutes accepted';exception when raise_exception then if sqlerrm<>'INVALID_REMINDERS' then raise;end if;end;
 begin perform public.save_reminder_settings(array[525660]);raise exception 'Excess offset accepted';exception when raise_exception then if sqlerrm<>'INVALID_REMINDERS' then raise;end if;end;
 begin perform public.save_reminder_settings(array[60,null]);raise exception 'Null offset accepted';exception when raise_exception then if sqlerrm<>'INVALID_REMINDERS' then raise;end if;end;
 begin perform 1 from private.reminder_preferences;raise exception 'Direct preference read allowed';exception when insufficient_privilege then null;end;
 begin perform public.save_reminder_settings(array(select g*60 from generate_series(2,14)g));raise exception 'Too many custom reminders accepted';exception when raise_exception then if sqlerrm<>'REMINDER_LIMIT' then raise;end if;end;
 reset role;
 insert into public.barbers(name,user_id) values('Reminder test worker',worker) returning id into b;
 insert into public.services(name,duration_minutes,price) values('Reminder test service',15,10) returning id into svc;
 foreach offsets slice 1 in array array[[59,74],[1439,1454],[2879,2894],[14,29],[119,134]]
 loop
  insert into public.calendar_entries(barber_id,kind,service_id,client_id,start_at,end_at,service_name,price)
  values(b,'appointment',svc,customer,now()+offsets[1]*interval '1 minute',now()+offsets[2]*interval '1 minute','Reminder test service',10);
 end loop;
 perform private.appointment_reminders();perform private.appointment_reminders();
 if (select count(*) from public.notifications where user_id=customer and event_key is not null)<>2 then raise exception 'Default timing or dedup wrong';end if;
 if (select count(*) from private.push_deliveries d join private.push_subscriptions s on s.id=d.subscription_id where s.user_id=customer)<>2 then raise exception 'Default push timings wrong';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',session_customer)::text,true);
 set local role authenticated;
 perform public.save_reminder_settings(array[15,2880,120,120]);
 if public.reminder_settings()->'offsets'<>'[15,120,2880]'::jsonb then raise exception 'Preference save/dedup failed';end if;
 reset role;
 if exists(select 1 from private.push_deliveries d join private.push_subscriptions s on s.id=d.subscription_id where s.user_id=customer and d.status<>'cancelled') then raise exception 'Disabled timings queued';end if;
 perform private.appointment_reminders();perform private.appointment_reminders();
 if (select count(*) from public.notifications where user_id=customer and event_key is not null)<>5 then raise exception 'New timings missing or duplicated';end if;
 if not exists(select 1 from public.notifications where user_id=customer and event_key like '%:48h:%') or not exists(select 1 from public.notifications where user_id=customer and event_key like '%:15m:%') or not exists(select 1 from public.notifications where user_id=customer and event_key like '%:120m:%') then raise exception '48h/15m/custom hour reminders missing';end if;
 if (select count(*) from private.push_deliveries d join private.push_subscriptions s on s.id=d.subscription_id where s.user_id=customer and d.status='pending')<>3 then raise exception 'New timings not queued for push';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',session_customer)::text,true);
 set local role authenticated;
 perform public.save_reminder_settings(array[4320]);
 reset role;
 insert into public.calendar_entries(barber_id,kind,service_id,client_id,start_at,end_at,service_name,price)
 values(b,'appointment',svc,customer,now()+interval '4319 minutes',now()+interval '4334 minutes','Custom days test',10);
 perform private.appointment_reminders();
 if not exists(select 1 from public.notifications where user_id=customer and event_key like '%:4320m:%' and title like '%3 giorni') then raise exception 'Custom days reminder missing';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_customer,'role','authenticated','session_id',session_other)::text,true);
 set local role authenticated;
 if public.reminder_settings()->'offsets'<>'[60,1440]'::jsonb then raise exception 'Other account preferences leaked';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated','session_id',session_customer)::text,true);
 set local role authenticated;
 perform public.save_reminder_settings('{}'::integer[]);
 if public.reminder_settings()->'offsets'<>'[]'::jsonb then raise exception 'All reminders cannot be disabled';end if;
 reset role;
 if exists(select 1 from private.push_deliveries d join private.push_subscriptions s on s.id=d.subscription_id where s.user_id=customer and d.status<>'cancelled') then raise exception 'Disable left pending delivery';end if;
 perform set_config('request.jwt.claims','{}',true);
 set local role anon;
 begin perform public.reminder_settings();raise exception 'Anonymous settings read allowed';exception when insufficient_privilege then null;end;
 reset role;
end $test$;
select 'personal_reminder_settings_test_passed' as result;
rollback;
