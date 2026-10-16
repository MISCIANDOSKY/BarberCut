
begin;
do $test$
declare u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); b uuid; s uuid; term uuid; d date:=current_date+8; n int; victim uuid; x int;
begin
insert into auth.users(id,email,raw_user_meta_data) values(u,'barbercut-role-a@example.invalid','{"first_name":"Test","last_name":"A","phone":"000"}'),(v,'barbercut-role-b@example.invalid','{"first_name":"Test","last_name":"B","phone":"000"}');
insert into public.barbers(name) values('TEST rollback roles') returning id into b;
insert into public.services(name,duration_minutes,price) values('TEST',15,1) returning id into s;
insert into public.barber_services values(b,s);
insert into public.working_hours(barber_id,weekday,opens,closes) select b,i,'09:00','18:00' from generate_series(0,6) i;
insert into public.terms_versions(version,body,published) values('TEST rollback','Termini di test non destinati alla pubblicazione',true) returning id into term;
insert into public.terms_acceptances(user_id,terms_id) values(u,term),(v,term);
update public.app_settings set bookings_enabled=true,cancellation_hours=0;
insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at) values(b,'appointment',v,s,(d+time '15:00') at time zone 'Europe/Rome',(d+time '15:15') at time zone 'Europe/Rome') returning id into victim;
perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','session_id','test')::text,true);
set local role authenticated;
for x in 0..4 loop perform public.book_appointment(b,s,((d+time '09:00') at time zone 'Europe/Rome')+x*interval '15 minutes');end loop;
begin perform public.book_appointment(b,s,(d+time '11:00') at time zone 'Europe/Rome');raise exception 'sixth allowed';exception when raise_exception then if sqlerrm<>'LIMIT_FIVE' then raise;end if;end;
select count(*) into n from public.profiles;if n<>1 then raise exception 'profile RLS failure %',n;end if;
select count(*) into n from public.user_roles;if n<>1 then raise exception 'role RLS failure';end if;
select count(*) into n from public.calendar_entries;if n<>5 then raise exception 'appointments RLS failure %',n;end if;
update public.user_roles set role='admin' where user_id=u;get diagnostics n=row_count;if n<>0 then raise exception 'role escalation';end if;
begin perform public.cancel_appointment(victim);raise exception 'other cancellation allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
begin perform public.publish_terms(term);raise exception 'client published terms';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
begin
insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at) values(b,'appointment',u,s,(d+time '17:00') at time zone 'Europe/Rome',(d+time '17:15') at time zone 'Europe/Rome');
raise exception 'direct insert bypass allowed';
exception when insufficient_privilege then null;end;
reset role;
end $test$;
select 'PASS: maximum five, profile/role/appointment isolation, no escalation, no cross-client cancellation, no client admin access, no direct booking insert' as result;
rollback;