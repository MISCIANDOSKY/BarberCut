begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare
 staff_user uuid:=gen_random_uuid(); other_staff uuid:=gen_random_uuid(); client_user uuid:=gen_random_uuid();
 own_barber uuid; other_barber uuid; service_id uuid; created uuid;
 holiday date; vacation date:=current_date+3; normal_day date; no_hours date;
 t timestamptz; prior_count integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (staff_user,'closed-staff@example.invalid',now(),'{}'),
 (other_staff,'closed-other@example.invalid',now(),'{}'),
 (client_user,'closed-client@example.invalid',now(),'{}');
 insert into public.barbers(name,user_id) values('Closed day test',staff_user) returning id into own_barber;
 insert into public.barbers(name,user_id) values('Other closed test',other_staff) returning id into other_barber;
 insert into public.services(name,duration_minutes,price) values('Closed day test service',30,10) returning id into service_id;
 insert into public.barber_services values(own_barber,service_id),(other_barber,service_id);
 insert into public.working_hours(barber_id,weekday,opens,closes) select own_barber,i,'09:00','18:00' from generate_series(0,6)i;
 select d::date into holiday from generate_series(current_date+1,current_date+80,interval '1 day') d where private.is_holiday(d::date) order by d limit 1;
 if holiday is null then raise exception 'no holiday fixture';end if;
 while private.is_holiday(vacation) loop vacation:=vacation+1;end loop;
 normal_day:=vacation+1;
 while private.is_holiday(normal_day) loop normal_day:=normal_day+1;end loop;
 insert into public.schedule_exceptions(barber_id,day,closed) values(own_barber,vacation,true);
 perform public.staff_authorize_session(staff_user,'closed-staff');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',staff_user,'role','authenticated','session_id','closed-staff')::text,true);
 set local role authenticated;
 if exists(select 1 from public.get_available_slots(own_barber,service_id,holiday)) then raise exception 'customer holiday opened';end if;
 if not exists(select 1 from public.get_manual_booking_slots(own_barber,service_id,holiday) where requires_confirmation) then raise exception 'holiday manual slots missing';end if;
 t:=(holiday+time '10:00') at time zone 'Europe/Rome';
 begin perform public.book_manual_appointment(own_barber,service_id,t,'Test','Holiday','',false);
 raise exception 'holiday booked without confirmation';
 exception when raise_exception then if sqlerrm<>'CLOSED_DAY_CONFIRM_REQUIRED' then raise;end if;end;
 begin perform public.book_guest_appointment(own_barber,service_id,t,'Test','Legacy','');
 raise exception 'legacy call bypassed confirmation';
 exception when raise_exception then if sqlerrm<>'CLOSED_DAY_CONFIRM_REQUIRED' then raise;end if;end;
 created:=public.book_manual_appointment(own_barber,service_id,t,'Test','Holiday','',true);
 if not exists(select 1 from public.calendar_entries where id=created and created_by=staff_user) then raise exception 'holiday save failed';end if;
 begin perform public.book_manual_appointment(own_barber,service_id,t,'Test','Conflict','',true);
 raise exception 'overlapping holiday booking allowed';
 exception when raise_exception then if sqlerrm<>'SLOT_TAKEN' then raise;end if;end;
 insert into public.calendar_entries(barber_id,kind,start_at,end_at,created_by)
 values(own_barber,'block',t+interval '1 hour',t+interval '2 hours',staff_user);
 if exists(select 1 from public.get_manual_booking_slots(own_barber,service_id,holiday) s where s.start_at=t+interval '1 hour') then raise exception 'blocked slot offered';end if;
 begin perform public.book_manual_appointment(own_barber,service_id,t+interval '1 hour','Test','Block','',true);
 raise exception 'calendar block bypassed';
 exception when raise_exception then if sqlerrm<>'SLOT_TAKEN' then raise;end if;end;
 t:=(vacation+time '10:00') at time zone 'Europe/Rome';
 if exists(select 1 from public.get_available_slots(own_barber,service_id,vacation)) then raise exception 'customer vacation opened';end if;
 begin perform public.book_manual_appointment(own_barber,service_id,t,'Test','Vacation','');
 raise exception 'vacation booked without yes';
 exception when raise_exception then if sqlerrm<>'CLOSED_DAY_CONFIRM_REQUIRED' then raise;end if;end;
 perform public.book_manual_appointment(own_barber,service_id,t,'Test','Vacation','',true);
 if exists(select 1 from public.get_manual_booking_slots(own_barber,service_id,normal_day) where requires_confirmation) then raise exception 'regular day unnecessarily flagged';end if;
 if exists(select 1 from public.get_manual_booking_slots(own_barber,service_id,normal_day) where (start_at at time zone 'Europe/Rome')::time<time '09:00') then raise exception 'regular hours widened';end if;
 perform public.book_manual_appointment(own_barber,service_id,(normal_day+time '10:00') at time zone 'Europe/Rome','Test','Normal','',false);
 begin perform public.get_manual_booking_slots(other_barber,service_id,holiday);
 raise exception 'other agenda manual slots exposed';
 exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 if exists(select 1 from public.get_manual_booking_slots(own_barber,service_id,current_date-1))
 or exists(select 1 from public.get_manual_booking_slots(own_barber,service_id,current_date+120)) then raise exception 'date horizon bypassed';end if;
 reset role;
 no_hours:=normal_day+7;
 while private.is_holiday(no_hours) loop no_hours:=no_hours+1;end loop;
 delete from public.working_hours where barber_id=own_barber and weekday=extract(dow from no_hours);
 set local role authenticated;
 if not exists(select 1 from public.get_manual_booking_slots(own_barber,service_id,no_hours) where requires_confirmation) then raise exception 'weekly closure unavailable';end if;
 perform public.book_manual_appointment(own_barber,service_id,(no_hours+time '10:00') at time zone 'Europe/Rome','Test','Weekly','',true);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',client_user,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.get_manual_booking_slots(own_barber,service_id,holiday);raise exception 'client got manual slots';
 exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.book_manual_appointment(own_barber,service_id,(holiday+time '13:00') at time zone 'Europe/Rome','Test','Forged','',true);raise exception 'client forged yes';
 exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 if has_function_privilege('anon','public.get_manual_booking_slots(uuid,uuid,date)','execute') or
 has_function_privilege('anon','public.book_manual_appointment(uuid,uuid,timestamptz,text,text,text,boolean)','execute') then raise exception 'anonymous grant';end if;
end $test$;
select 'PASS: holiday/vacation/weekly closure require yes; normal hours unchanged; conflicts/blocks/roles/horizon preserved; rollback' as result;
rollback;
