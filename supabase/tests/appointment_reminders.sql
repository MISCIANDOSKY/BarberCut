begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare owner_user uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); staff_user uuid:=gen_random_uuid();
 barber uuid; service uuid; day_notice uuid; hour_notice uuid; excluded_ids uuid[]; item uuid; note_count integer;
begin
 insert into auth.users(id,email,raw_user_meta_data) values
 (owner_user,'reminder-owner@example.invalid','{}'),
 (other_user,'reminder-other@example.invalid','{}'),
 (staff_user,'reminder-staff@example.invalid','{}');
 insert into public.barbers(name,user_id) values('Reminder test agenda',staff_user) returning id into barber;
 insert into public.services(name,duration_minutes,price) values('Test promemoria',15,10) returning id into service;
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)
 values(barber,'appointment',owner_user,service,now()+interval '23 hours 58 minutes',now()+interval '24 hours 13 minutes','Test promemoria',10) returning id into day_notice;
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)
 values(barber,'appointment',owner_user,service,now()+interval '45 minutes',now()+interval '60 minutes','Test promemoria',10) returning id into hour_notice;
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)
 values(barber,'appointment',other_user,service,now()+interval '25 hours',now()+interval '25 hours 15 minutes','Too early',10) returning id into item;
 excluded_ids:=array[item];
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)
 values(barber,'appointment',owner_user,service,now()-interval '30 minutes',now()-interval '15 minutes','Past',10) returning id into item;
 excluded_ids:=array_append(excluded_ids,item);
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,status)
 values(barber,'appointment',owner_user,service,now()+interval '46 minutes',now()+interval '61 minutes','Cancelled',10,'cancelled') returning id into item;
 excluded_ids:=array_append(excluded_ids,item);
 insert into public.calendar_entries(barber_id,kind,service_id,start_at,end_at,service_name,price,guest_first_name,guest_last_name)
 values(barber,'appointment',service,now()+interval '25 minutes',now()+interval '40 minutes','Guest',10,'Guest','Test') returning id into item;
 excluded_ids:=array_append(excluded_ids,item);
 insert into public.calendar_entries(barber_id,kind,start_at,end_at)
 values(barber,'block',now()+interval '5 minutes',now()+interval '20 minutes') returning id into item;
 excluded_ids:=array_append(excluded_ids,item);
 perform private.appointment_reminders();
 perform private.appointment_reminders();
 if(select count(*) from public.notifications where event_key like day_notice::text||':24h:%')<>1 then raise exception '24h missing or duplicated';end if;
 if(select count(*) from public.notifications where event_key like hour_notice::text||':1h:%')<>1 then raise exception '1h missing or duplicated';end if;
 if exists(select 1 from public.notifications n where split_part(n.event_key,':',1)=any(select unnest(excluded_ids)::text)) then raise exception 'excluded appointment got reminder';end if;
 if exists(select 1 from public.notifications where (event_key like day_notice::text||':%' or event_key like hour_notice::text||':%') and
   (user_id<>owner_user or body not like 'Ricordati del tuo appuntamento! Hai prenotato Test promemoria per il % alle %. Ti aspettiamo in barberia.')) then raise exception 'wrong recipient or text';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated')::text,true);
 set local role authenticated;
 if(select count(*) from public.notifications where event_key like day_notice::text||':%' or event_key like hour_notice::text||':%')<>2 then raise exception 'owner cannot see reminders';end if;
 update public.notifications set read_at=now() where event_key like hour_notice::text||':1h:%';
 begin perform private.appointment_reminders();raise exception 'client can invoke scheduler';
 exception when insufficient_privilege then null;end;
 reset role;
 if not exists(select 1 from public.notifications where event_key like hour_notice::text||':1h:%' and read_at is not null) then raise exception 'owner read state not saved';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'role','authenticated')::text,true);
 set local role authenticated;
 if exists(select 1 from public.notifications where event_key like day_notice::text||':%' or event_key like hour_notice::text||':%') then raise exception 'other client sees reminders';end if;
 reset role;
 if not exists(select 1 from cron.job where jobname='barbercut-appointment-reminders' and active and schedule='*/5 * * * *') then raise exception 'reminder schedule missing';end if;
end $test$;
select 'PASS: 24h and 1h reminder text, deduplication, exclusions, owner visibility/read state, cron active; rollback' as result;
rollback;
