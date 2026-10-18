begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare
 worker uuid:=gen_random_uuid(); other_worker uuid:=gen_random_uuid(); customer uuid:=gen_random_uuid();
 b uuid; other_b uuid; s uuid; ap uuid; conflict uuid; blocker uuid; booked_time timestamptz;
 d date:=(now() at time zone 'Europe/Rome')::date+3; midnight timestamptz; n integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (worker,'move-worker@example.invalid',now(),'{}'),(other_worker,'move-other@example.invalid',now(),'{}'),(customer,'move-client@example.invalid',now(),'{}');
 insert into public.barbers(name,user_id) values('Move worker',worker) returning id into b;
 insert into public.barbers(name,user_id) values('Move other',other_worker) returning id into other_b;
 delete from public.working_hours where barber_id in(b,other_b);
 insert into public.working_hours(barber_id,weekday,opens,closes) select b,w,'09:00','17:00' from generate_series(0,6)w;
 insert into public.services(name,duration_minutes,price) values('Move original',45,25) returning id into s;
 insert into public.barber_services(barber_id,service_id) values(b,s),(other_b,s);
 while private.is_holiday(d) loop d:=d+1;end loop;
 midnight:=d::timestamp at time zone 'Europe/Rome';
 booked_time:=midnight+interval '10 hours';
 insert into public.calendar_entries(barber_id,kind,service_id,client_id,start_at,end_at,service_name,price)
 values(b,'appointment',s,customer,booked_time,booked_time+interval '45 minutes','Move snapshot',25) returning id into ap;
 insert into public.calendar_entries(barber_id,kind,start_at,end_at,notes) values(b,'block',midnight+interval '12 hours',midnight+interval '13 hours','Move block') returning id into blocker;
 insert into public.calendar_entries(barber_id,kind,service_id,client_id,start_at,end_at,service_name,price)
 values(b,'appointment',s,customer,midnight+interval '14 hours',midnight+interval '15 hours','Move conflict',25) returning id into conflict;
 perform public.staff_authorize_session(worker,'move-worker');
 perform public.staff_authorize_session(other_worker,'move-other');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','move-worker')::text,true);
 set local role authenticated;
 if not exists(select 1 from public.get_reschedule_slots(ap,d) where start_at=booked_time+interval '15 minutes' and not requires_confirmation) then raise exception 'Own appointment incorrectly blocks shift';end if;
 if exists(select 1 from public.get_reschedule_slots(ap,d) where start_at in(midnight+interval '11 hours 30 minutes',midnight+interval '14 hours 30 minutes')) then raise exception 'Overlapping slot offered';end if;
 if not exists(select 1 from public.get_reschedule_slots(ap,d) where start_at=midnight+interval '13 hours' and not requires_confirmation) then raise exception 'Adjacent interval unavailable';end if;
 begin perform public.reschedule_appointment(ap,midnight+interval '12 hours',true);raise exception 'Block overlap saved';exception when raise_exception then if sqlerrm<>'SLOT_TAKEN' then raise;end if;end;
 if not exists(select 1 from public.calendar_entries where id=ap and start_at=booked_time and status='confirmed') then raise exception 'Failed move altered original';end if;
 reset role;
 -- Simulate a displayed free slot becoming occupied before confirmation.
 insert into public.calendar_entries(barber_id,kind,start_at,end_at,notes)
 values(b,'block',midnight+interval '13 hours 15 minutes',midnight+interval '13 hours 30 minutes','Late conflict');
 set local role authenticated;
 begin perform public.reschedule_appointment(ap,midnight+interval '13 hours',false);raise exception 'Stale available slot saved';exception when raise_exception then if sqlerrm<>'SLOT_TAKEN' then raise;end if;end;
 reset role;
 delete from public.calendar_entries where barber_id=b and notes='Late conflict';
 set local role authenticated;
 perform public.reschedule_appointment(ap,booked_time+interval '15 minutes',false);
 reset role;
 -- Editing current catalog duration must not change the existing booking duration.
 update public.services set duration_minutes=15,price=99 where id=s;
 select count(*) into n from public.notifications where user_id=customer and title='Appuntamento aggiornato';
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','move-worker')::text,true);
 set local role authenticated;
 perform public.reschedule_appointment(ap,midnight+interval '11 hours',false);
 if not exists(select 1 from public.calendar_entries where id=ap and end_at-start_at=interval '45 minutes' and service_name='Move snapshot' and price=25 and client_id=customer) then raise exception 'Snapshot or duration changed';end if;
 reset role;
 if (select count(*) from public.notifications where user_id=customer and title='Appuntamento aggiornato')<>n+1 then raise exception 'Update notification missing';end if;
 set local role authenticated;
 if not exists(select 1 from public.get_reschedule_slots(ap,d) where start_at=midnight and requires_confirmation) then raise exception 'Outside hours confirmation missing';end if;
 begin perform public.reschedule_appointment(ap,midnight);raise exception 'Legacy bypasses closed confirmation';exception when raise_exception then if sqlerrm<>'CLOSED_DAY_CONFIRM_REQUIRED' then raise;end if;end;
 perform public.reschedule_appointment(ap,midnight,true);
 reset role;
 insert into public.schedule_exceptions(barber_id,day,closed) values(b,d+1,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','move-worker')::text,true);
 set local role authenticated;
 if exists(select 1 from public.get_reschedule_slots(ap,d+1) where not requires_confirmation) then raise exception 'Closure ignored';end if;
 if exists(select 1 from public.get_reschedule_slots(ap,d-100)) then raise exception 'Past date offered';end if;
 begin perform public.get_reschedule_slots(blocker,d);raise exception 'Block accepted as appointment';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_worker,'role','authenticated','session_id','move-other')::text,true);
 set local role authenticated;
 begin perform public.get_reschedule_slots(ap,d);raise exception 'Other agenda read allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.reschedule_appointment(ap,midnight+interval '16 hours',true);raise exception 'Other agenda move allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 update public.user_roles set role='barber_admin' where user_id=worker;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','move-worker')::text,true);
 set local role authenticated;
 perform public.reschedule_appointment(ap,midnight+interval '16 hours',false);
 reset role;
 update public.barber_services set active=false,staff_enabled=false where barber_id=b and service_id=s;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','move-worker')::text,true);
 set local role authenticated;
 if exists(select 1 from public.get_reschedule_slots(ap,d)) then raise exception 'Blocked service offered';end if;
 reset role;
 update public.calendar_entries set status='cancelled' where id=ap;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','move-worker')::text,true);
 set local role authenticated;
 begin perform public.reschedule_appointment(ap,midnight+interval '16 hours',true);raise exception 'Cancelled appointment revived';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.get_reschedule_slots(conflict,d);raise exception 'Client staff slots access';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 if has_function_privilege('anon','public.get_reschedule_slots(uuid,date)','execute') or has_function_privilege('anon','public.reschedule_appointment(uuid,timestamptz,boolean)','execute') then raise exception 'Anonymous grant';end if;
end $test$;
rollback;
