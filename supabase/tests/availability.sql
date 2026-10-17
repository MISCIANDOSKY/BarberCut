
begin;
-- These fixtures model clients already admitted to the barber shop.
update public.app_settings set require_user_approval=false where id;
do $test$
declare u uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); b uuid; s15 uuid; s30 uuid; s45 uuid; d date:=current_date+7; n int; created uuid; t timestamptz;
begin
insert into auth.users(id,email,raw_user_meta_data) values(u,'barbercut-test-a@example.invalid','{"first_name":"Test","last_name":"A","phone":"000"}'),(other,'barbercut-test-b@example.invalid','{"first_name":"Test","last_name":"B","phone":"000"}');
insert into public.barbers(name) values('TEST rollback') returning id into b;
insert into public.services(name,duration_minutes,price) values('TEST 15',15,1) returning id into s15;
insert into public.services(name,duration_minutes,price) values('TEST 30',30,1) returning id into s30;
insert into public.services(name,duration_minutes,price) values('TEST 45',45,1) returning id into s45;
insert into public.barber_services values(b,s15),(b,s30),(b,s45);
insert into public.working_hours(barber_id,weekday,opens,closes) select b,x,'09:00','13:00' from generate_series(0,6) x;
if private.is_holiday(d) then d:=d+1;end if;
select count(*) into n from public.get_available_slots(b,s15,d);if n<>16 then raise exception '15 minute slot count %',n;end if;
select count(*) into n from public.get_available_slots(b,s30,d);if n<>15 then raise exception '30 minute slot count %',n;end if;
select count(*) into n from public.get_available_slots(b,s45,d);if n<>14 then raise exception '45 minute slot count %',n;end if;
insert into public.calendar_entries(barber_id,kind,start_at,end_at) values(b,'block',(d+time '09:30') at time zone 'Europe/Rome',(d+time '10:00') at time zone 'Europe/Rome');
if exists(select 1 from public.get_available_slots(b,s45,d) where start_at=(d+time '09:00') at time zone 'Europe/Rome') then raise exception 'partial overlap not excluded';end if;
if not exists(select 1 from public.get_available_slots(b,s45,d) where start_at=(d+time '10:00') at time zone 'Europe/Rome') then raise exception 'half open boundary incorrect';end if;
begin
insert into public.calendar_entries(barber_id,kind,start_at,end_at) values(b,'block',(d+time '09:45') at time zone 'Europe/Rome',(d+time '10:15') at time zone 'Europe/Rome');
raise exception 'overlap unexpectedly allowed';
exception when exclusion_violation then null;end;
insert into public.schedule_exceptions(barber_id,day,closed) values(b,d,true);
if exists(select 1 from public.get_available_slots(b,s15,d)) then raise exception 'closed day not excluded';end if;
delete from public.schedule_exceptions where barber_id=b;
if not private.is_holiday(make_date(extract(year from now())::int,12,25)) then raise exception 'Christmas not holiday';end if;
if not private.is_holiday(date '2027-03-29') then raise exception 'Easter Monday incorrect';end if;
insert into public.schedule_exceptions(barber_id,day,opens,closes) values(b,d,'15:00','16:00');
select count(*) into n from public.get_available_slots(b,s15,d);if n<>4 then raise exception 'special opening incorrect';end if;
if exists(select 1 from public.get_available_slots(b,s15,(current_date+interval '4 months')::date)) then raise exception 'three month limit incorrect';end if;
insert into public.terms_versions(version,body,published) values('TEST availability','Termini di test non pubblici',true);
insert into public.terms_acceptances(user_id,terms_id) select u,id from public.terms_versions where version='TEST availability';
update public.app_settings set bookings_enabled=true,cancellation_hours=0;
perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','session_id','test')::text,true);
t:=(d+time '15:00') at time zone 'Europe/Rome';
created:=public.book_appointment(b,s15,t);
begin perform public.book_appointment(b,s15,t);raise exception 'duplicate accepted';exception when raise_exception then if sqlerrm<>'SLOT_TAKEN' then raise;end if;end;
-- Roll back all test fixtures, notifications and state at transaction end.
end $test$;
select 'PASS: durations 15/30/45, overlap constraint, block, closure, holiday, exception, booking and duplicate rejection' as result;
rollback;
