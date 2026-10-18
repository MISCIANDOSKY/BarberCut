begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare
 worker uuid:=gen_random_uuid(); customer uuid:=gen_random_uuid(); b uuid; s uuid;
 guest_entry uuid; linked_entry uuid; lead_entry uuid; d date:=(now() at time zone 'Europe/Rome')::date+3;
 start_time timestamptz; staff_before integer; customer_before integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (worker,'silent-worker@example.invalid',now(),'{"first_name":"Silent","last_name":"Worker"}'),
 (customer,'silent-client@example.invalid',now(),'{"first_name":"Silent","last_name":"Client","phone":"0999876543"}');
 insert into public.barbers(name,user_id) values('Silent worker',worker) returning id into b;
 delete from public.working_hours where barber_id=b;
 insert into public.working_hours(barber_id,weekday,opens,closes) select b,w,'09:00','18:00' from generate_series(0,6)w;
 insert into public.services(name,duration_minutes,price) values('Silent service',30,20) returning id into s;
 insert into public.barber_services(barber_id,service_id) values(b,s);
 while private.is_holiday(d) loop d:=d+1;end loop;
 start_time:=(d+time '10:00') at time zone 'Europe/Rome';
 perform public.staff_authorize_session(worker,'silent-worker');
 select count(*) into staff_before from public.notifications where user_id=worker;
 select count(*) into customer_before from public.notifications where user_id=customer;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','silent-worker')::text,true);
 set local role authenticated;
 guest_entry:=public.book_manual_appointment(b,s,start_time,'Silent','Guest','',false);
 linked_entry:=public.book_manual_appointment(b,s,start_time+interval '45 minutes','Silent','Client','0999876543',false);
 reset role;
 if (select count(*) from public.notifications where user_id=worker)<>staff_before then raise exception 'Normal barber notified about own manual insertion';end if;
 if (select count(*) from public.notifications where user_id=customer)<>customer_before then raise exception 'Manual insertion notified customer';end if;
 if not exists(select 1 from public.calendar_entries where id=linked_entry and client_id=customer) then raise exception 'Phone association lost';end if;
 update public.user_roles set role='barber_admin' where user_id=worker;
 set local role authenticated;
 lead_entry:=public.book_manual_appointment(b,s,start_time+interval '90 minutes','Silent','Lead guest','',false);
 reset role;
 if (select count(*) from public.notifications where user_id=worker)<>staff_before then raise exception 'Lead notified about own manual insertion';end if;
 -- A customer-created appointment must still notify the barber.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated')::text,true);
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by)
 values(b,'appointment',customer,s,start_time+interval '3 hours',start_time+interval '3 hours 30 minutes','Silent service',20,customer);
 if (select count(*) from public.notifications where user_id=worker)<>staff_before+1 then raise exception 'Customer booking notification lost';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','silent-worker')::text,true);
 set local role authenticated;
 perform public.reschedule_appointment(linked_entry,start_time+interval '4 hours',false);
 reset role;
 if (select count(*) from public.notifications where user_id=customer and title='Appuntamento aggiornato')<>1 then raise exception 'Move notification lost';end if;
 if (select count(*) from public.notifications where user_id=worker)<>staff_before+2 then raise exception 'Move agenda notification lost';end if;
 set local role authenticated;
 perform public.cancel_appointment(linked_entry);
 reset role;
 if (select count(*) from public.notifications where user_id=customer and title='Appuntamento cancellato')<>1 then raise exception 'Cancellation notification lost';end if;
end $test$;
rollback;
