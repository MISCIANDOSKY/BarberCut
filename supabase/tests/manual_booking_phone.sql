begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare
  staff uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); other_client uuid:=gen_random_uuid();
  duplicate uuid:=gen_random_uuid(); barber uuid; service uuid; appointment uuid; guest uuid;
  d date:=current_date+3; t timestamptz; test_phone text:='399'||lpad((floor(random()*10000000)::int)::text,7,'0');
  users_before integer; profiles_before integer;
begin
  if private.is_holiday(d) then d:=d+1;end if;
  t:=(d+time '09:00') at time zone 'Europe/Rome';
  insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
    (staff,'manual-staff@example.invalid',now(),'{}'),
    (client,'manual-client@example.invalid',now(),'{"first_name":"Registered","last_name":"Client"}'),
    (other_client,'manual-other@example.invalid',now(),'{}');
  update public.profiles set phone='+39 '||substring(test_phone from 1 for 3)||' '||substring(test_phone from 4) where id=client;
  insert into public.barbers(name,user_id) values('Manual test',staff) returning id into barber;
  insert into public.services(name,duration_minutes,price) values('Manual test_phone test',30,10) returning id into service;
  insert into public.barber_services values(barber,service);
  insert into public.working_hours(barber_id,weekday,opens,closes) select barber,i,'08:00','19:00' from generate_series(0,6)i;
  perform public.staff_authorize_session(staff,'manual-staff');
  select count(*) into users_before from auth.users;
  select count(*) into profiles_before from public.profiles;
  if private.booking_phone_key(test_phone) is distinct from private.booking_phone_key('+39 '||test_phone)
    or private.booking_phone_key(test_phone) is distinct from private.booking_phone_key('0039 '||test_phone)
    or private.booking_phone_key('abc') is not null
    or private.booking_phone_key('') is not null then raise exception 'test_phone normalization wrong';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',staff,'role','authenticated','session_id','manual-staff')::text,true);
  set local role authenticated;
  appointment:=public.book_guest_appointment(barber,service,t,'Manual','Client',test_phone);
  if not exists(select 1 from public.calendar_entries where id=appointment and client_id=client and guest_first_name='Manual') then raise exception 'registered client not linked';end if;
  guest:=public.book_guest_appointment(barber,service,t+interval '1 hour','No','Phone','');
  if not exists(select 1 from public.calendar_entries where id=guest and client_id is null) then raise exception 'empty test_phone incorrectly linked';end if;
  guest:=public.book_guest_appointment(barber,service,t+interval '2 hours','Unknown','Phone','+44 7700 900123');
  if not exists(select 1 from public.calendar_entries where id=guest and client_id is null) then raise exception 'unknown test_phone incorrectly linked';end if;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',client,'role','authenticated')::text,true);
  set local role authenticated;
  if not exists(select 1 from public.calendar_entries where id=appointment and client_id=client and kind='appointment' and status='confirmed' and start_at>now()) then raise exception 'client cannot see own manual appointment';end if;
  if exists(select 1 from public.calendar_entries where id=guest) then raise exception 'client sees unrelated guest';end if;
  begin perform public.book_guest_appointment(barber,service,t+interval '3 hours','Unauthorized','Client',test_phone);
    raise exception 'client allowed manual booking';
  exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',other_client,'role','authenticated')::text,true);
  set local role authenticated;
  if exists(select 1 from public.calendar_entries where id=appointment) then raise exception 'other client sees appointment';end if;
  reset role;
  if(select count(*) from auth.users)<>users_before or (select count(*) from public.profiles)<>profiles_before then raise exception 'manual booking created account';end if;
  insert into auth.users(id,email,raw_user_meta_data) values(duplicate,'manual-duplicate@example.invalid','{}');
  update public.profiles set phone='0039 '||test_phone where id=duplicate;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',staff,'role','authenticated','session_id','manual-staff')::text,true);
  set local role authenticated;
  begin perform public.book_guest_appointment(barber,service,t+interval '3 hours','Duplicate','Phone',test_phone);
    raise exception 'duplicate test_phone arbitrarily linked';
  exception when raise_exception then if sqlerrm<>'PHONE_MATCH_AMBIGUOUS' then raise;end if;end;
  reset role;
  update public.profiles set phone='' where id=duplicate;
  update private.client_memberships set status='pending' where user_id=client;
  set local role authenticated;
  begin perform public.book_guest_appointment(barber,service,t+interval '3 hours','Pending','Client',test_phone);
    raise exception 'pending account bypassed';
  exception when raise_exception then if sqlerrm<>'USER_APPROVAL_REQUIRED' then raise;end if;end;
  reset role;
  update private.client_memberships set status='approved' where user_id=client;
  set local role authenticated;
  for i in 1..4 loop
    perform public.book_guest_appointment(barber,service,t+interval '3 hours'+i*interval '30 minutes','Registered','Client','0039 '||test_phone);
  end loop;
  begin perform public.book_guest_appointment(barber,service,t+interval '6 hours','Limit','Client',test_phone);
    raise exception 'five appointment limit bypassed';
  exception when raise_exception then if sqlerrm<>'LIMIT_FIVE' then raise;end if;end;
  reset role;
end
$test$;
select 'PASS: exact canonical test_phone link, client RLS visibility, guests, duplicates, staff authorization, approval, booking limit; rollback' as result;
rollback;
