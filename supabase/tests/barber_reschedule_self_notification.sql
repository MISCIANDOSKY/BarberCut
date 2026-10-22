begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare worker uuid:=gen_random_uuid();lead uuid:=gen_random_uuid();customer uuid:=gen_random_uuid(); uid uuid; b uuid; s uuid; booking uuid; n int; cn int; d date:=(now()at time zone 'Europe/Rome')::date+3; start_time timestamptz; second_time timestamptz;
begin
 insert into auth.users(id,email,raw_user_meta_data)values
 (worker,'move-worker@example.invalid','{}'),(lead,'move-lead@example.invalid','{}'),(customer,'move-customer@example.invalid','{}');
 insert into public.services(name,duration_minutes,price)values('TEST move notification',30,20)returning id into s;
 foreach uid in array array[worker,lead] loop
  perform set_config('request.jwt.claims','{}',true);
  insert into public.barbers(name,user_id)values('TEST move agenda',uid)returning id into b;
  if uid=lead then update public.user_roles set role='barber_admin'where user_id=uid;end if;
  insert into public.barber_services(barber_id,service_id)values(b,s)on conflict do nothing;
  start_time:=(d+time '10:00')at time zone 'Europe/Rome';
  second_time:=(d+time '11:00')at time zone 'Europe/Rome';
  insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)
  values(b,'appointment',customer,s,start_time,start_time+interval '30 minutes','TEST move notification',20)returning id into booking;
  perform public.staff_authorize_session(uid,'move-test');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',uid,'role','authenticated','session_id','move-test')::text,true);
  select count(*)into n from public.notifications where user_id=uid and title='Aggiornamento agenda';
  select count(*)into cn from public.notifications where user_id=customer and title='Appuntamento aggiornato';
  set local role authenticated;
  perform public.reschedule_appointment(booking,second_time,true);
  reset role;
  if (select count(*)from public.notifications where user_id=uid and title='Aggiornamento agenda')<>n then raise exception 'Self agenda notice created';end if;
  if (select count(*)from public.notifications where user_id=customer and title='Appuntamento aggiornato')<>cn+1 then raise exception 'Customer update notice lost';end if;
  if not exists(select 1 from private.appointment_logs where entry_id=booking and actor_id=uid and action='rescheduled')then raise exception 'Reschedule audit lost';end if;
  if not exists(select 1 from public.calendar_entries where id=booking and start_at=second_time)then raise exception 'Reschedule failed';end if;
  -- Incoming appointments still generate the normal agenda notice.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated')::text,true);
  insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)
  values(b,'appointment',customer,s,second_time+interval '2 hours',second_time+interval '2 hours 30 minutes','TEST move notification',20);
  if (select count(*)from public.notifications where user_id=uid and title='Aggiornamento agenda')<>n+1 then raise exception 'Incoming booking notice lost';end if;
 end loop;
end $test$;
select 'PASS normal and lead barber reschedule without self notice; customer update, audit and incoming booking notice preserved' result;
rollback;
