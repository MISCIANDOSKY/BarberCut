begin;
do $test$
declare
  admin_id uuid:=gen_random_uuid();
  barber_user uuid:=gen_random_uuid();
  barber_id uuid;
  service_id uuid;
  booking_id uuid;
  booking_day date:=current_date+3;
  booking_start timestamptz;
begin
  insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
    (admin_id,'admin-customer-test@example.invalid',now(),'{"first_name":"Admin","last_name":"Customer","phone":"3990000001"}'),
    (barber_user,'admin-customer-barber@example.invalid',now(),'{}');
  update public.user_roles set role='admin' where user_id=admin_id;
  insert into public.barbers(name,user_id) values('Admin customer test agenda',barber_user) returning id into barber_id;
  insert into public.services(name,duration_minutes,price) values('Admin customer test service',30,10) returning id into service_id;
  insert into public.barber_services values(barber_id,service_id);
  insert into public.working_hours(barber_id,weekday,opens,closes)
    select barber_id,i,'09:00','18:00' from generate_series(0,6)i;
  insert into public.terms_acceptances(user_id,terms_id)
    select admin_id,t.id from public.terms_versions t where published;
  while private.is_holiday(booking_day) loop booking_day:=booking_day+1;end loop;
  booking_start:=(booking_day+time '10:00') at time zone 'Europe/Rome';
  perform public.staff_authorize_session(admin_id,'admin-customer-test');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','session_id','admin-customer-test')::text,true);
  set local role authenticated;
  booking_id:=public.book_appointment(barber_id,service_id,booking_start);
  if not exists(select 1 from public.calendar_entries where id=booking_id and client_id=admin_id and created_by=admin_id and kind='appointment' and status='confirmed') then
    raise exception 'admin personal booking not owned by admin';
  end if;
  if not exists(select 1 from public.user_roles where user_id=admin_id and role='admin') then
    raise exception 'admin role changed by personal booking';
  end if;
  if not exists(select 1 from public.calendar_entries where id=booking_id and client_id=auth.uid() and start_at>now()) then
    raise exception 'admin personal appointment not visible';
  end if;
  reset role;
end
$test$;
select 'PASS: admin self-booking, ownership, own appointments query, admin role preserved; rollback' as result;
rollback;
