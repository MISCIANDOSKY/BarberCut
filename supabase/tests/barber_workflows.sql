
begin;
do $test$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();ad uuid:=gen_random_uuid();ba uuid;bb uuid;bad uuid;s uuid;owned uuid;guest uuid;otherguest uuid;created uuid;n int;profiles_before int;d date:=current_date+3;t timestamptz;
begin
insert into auth.users(id,email,raw_user_meta_data) values
(a,'barber-a-test@example.invalid','{"first_name":"Test","last_name":"A","phone":"000"}'),
(b,'barber-b-test@example.invalid','{"first_name":"Test","last_name":"B","phone":"000"}'),
(c,'client-test@example.invalid','{"first_name":"Test","last_name":"Client","phone":"000"}'),
(ad,'admin-test@example.invalid','{"first_name":"Test","last_name":"Admin","phone":"000"}');
update public.user_roles set role='admin' where user_id=ad;
insert into public.barbers(name,user_id) values('Test barber A',a) returning id into ba;
insert into public.barbers(name,user_id) values('Test barber B',b) returning id into bb;
insert into public.barbers(name,user_id) values('Test admin barber',ad) returning id into bad;
if(select role from public.user_roles where user_id=a)<>'barber' then raise exception 'barber role not assigned';end if;
if(select role from public.user_roles where user_id=ad)<>'admin' then raise exception 'admin role downgraded';end if;
perform public.staff_authorize_session(a,'test-a');perform public.staff_authorize_session(b,'test-b');perform public.staff_authorize_session(ad,'test-admin');
insert into public.services(name,duration_minutes,price) values('Shared test',30,20) returning id into s;
insert into public.barber_services values(ba,s),(bb,s);
insert into public.working_hours(barber_id,weekday,opens,closes) select barber_id,weekday,'09:00','18:00' from (values(ba),(bb))barbers(barber_id) cross join generate_series(0,6)weekday;
if private.is_holiday(d) then d:=d+1;end if;
t:=(d+time '10:00') at time zone 'Europe/Rome';
select count(*) into profiles_before from public.profiles;
perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id','test-a')::text,true);
set local role authenticated;
guest:=public.book_guest_appointment(ba,s,t,'Mario','Ospite','');
if not exists(select 1 from public.calendar_entries where id=guest and client_id is null and guest_first_name='Mario' and guest_last_name='Ospite' and guest_phone='') then raise exception 'guest booking failed';end if;
begin perform public.book_guest_appointment(ba,s,t+interval '2 hours','','Ospite','');raise exception 'empty guest name allowed';exception when raise_exception then if sqlerrm<>'GUEST_NAME_REQUIRED' then raise;end if;end;
begin perform public.book_guest_appointment(bb,s,t,'Altra','Agenda','');raise exception 'other barber guest booking allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
begin
insert into public.calendar_entries(barber_id,kind,start_at,end_at,created_by) values(bb,'block',t+interval '5 hours',t+interval '6 hours',a);
raise exception 'other agenda block allowed';
exception when insufficient_privilege then null;end;
insert into public.calendar_entries(barber_id,kind,start_at,end_at,created_by) values(ba,'block',t+interval '5 hours',t+interval '6 hours',a);
perform public.reschedule_appointment(guest,t+interval '1 hour');
owned:=public.save_barber_service(ba,s,'My test haircut','My description',45,25);
if owned=s then raise exception 'shared service was not isolated';end if;
if not exists(select 1 from public.services where id=s and name='Shared test' and price=20 and duration_minutes=30) then raise exception 'other barber service changed';end if;
if not exists(select 1 from public.calendar_entries where id=guest and service_id=owned and service_name='Shared test' and price=20) then raise exception 'existing appointment snapshot lost';end if;
if not exists(select 1 from public.barber_services where barber_id=bb and service_id=s) then raise exception 'other association changed';end if;
begin perform public.save_barber_service(bb,s,'Forbidden','',15,1);raise exception 'other services update allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
begin perform public.remove_barber_service(bb,s);raise exception 'other services delete allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
created:=public.save_barber_service(ba,null,'Brand new','',15,10);
if not exists(select 1 from public.barber_services where barber_id=ba and service_id=created) then raise exception 'new service not linked';end if;
perform public.remove_barber_service(ba,created);
if exists(select 1 from public.barber_services where barber_id=ba and service_id=created) then raise exception 'service not removed';end if;
perform public.cancel_appointment(guest);
begin perform public.admin_delete_resource('barber',bb);raise exception 'barber admin deletion allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
reset role;
if(select count(*) from public.profiles)<>profiles_before then raise exception 'guest created an account';end if;
perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated','session_id','test-b')::text,true);
set local role authenticated;
if exists(select 1 from public.calendar_entries where id=guest) then raise exception 'guest visible to other barber';end if;
reset role;
perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'role','authenticated','session_id','test-client')::text,true);
set local role authenticated;
begin perform public.book_guest_appointment(ba,owned,t,'Client','Forbidden','');raise exception 'client manual booking allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
if exists(select 1 from public.calendar_entries where id=guest) then raise exception 'guest data visible to client';end if;
reset role;
perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','test-admin')::text,true);
set local role authenticated;
otherguest:=public.book_guest_appointment(bb,s,t,'Other','Guest','');
begin perform public.admin_delete_resource('barber',bb);raise exception 'busy barber deleted';exception when raise_exception then if sqlerrm<>'BARBER_HAS_APPOINTMENTS' then raise;end if;end;
perform public.admin_delete_resource('service',s);
if not exists(select 1 from public.services where id=s and deleted_at is not null and not active) then raise exception 'admin service deletion failed';end if;
if not exists(select 1 from public.calendar_entries where id=otherguest and service_id=s) then raise exception 'appointment lost on service deletion';end if;
perform public.admin_delete_resource('barber',ba);
if not exists(select 1 from public.barbers where id=ba and deleted_at is not null and not active) then raise exception 'admin barber deletion failed';end if;
reset role;
end $test$;
select 'PASS: automatic roles/admin preservation; guests without accounts/phone; own agenda only; guest reschedule/cancel; service isolation/add/edit/remove; admin deletion/history protection' as result;
rollback;
