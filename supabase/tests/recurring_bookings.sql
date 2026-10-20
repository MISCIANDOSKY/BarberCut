begin;

update public.app_settings set require_user_approval=false where id;
update public.terms_versions set published=false where published;
do $test$
declare u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();worker uuid:=gen_random_uuid();b uuid;s uuid;term uuid;anchor uuid;p uuid;ep uuid;rp uuid;d date:=(now() at time zone 'Europe/Rome')::date+2;future date;st timestamptz;n integer;rec record;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (u,'rec-client@example.invalid',now(),'{"first_name":"Test","last_name":"Ricorrenze","phone":"000"}'),
 (v,'rec-other@example.invalid',now(),'{"first_name":"Test","last_name":"Altro","phone":"001"}'),
 (worker,'rec-worker@example.invalid',now(),'{}');
 insert into public.barbers(name,user_id)values('TEST rec worker',worker)returning id into b;
 delete from public.working_hours where barber_id=b;
 insert into public.working_hours(barber_id,weekday,opens,closes)select b,i,'08:00','20:00'from generate_series(0,6)i;
 insert into public.services(name,duration_minutes,price)values('TEST rec',30,20)returning id into s;
 insert into public.barber_services(barber_id,service_id)values(b,s);
 insert into public.terms_versions(version,body,published)values('TEST rec','Termini test',true)returning id into term;
 insert into public.terms_acceptances(user_id,terms_id)values(u,term),(v,term);
 update public.app_settings set bookings_enabled=true,cancellation_hours=0;
 while private.is_holiday(d) loop d:=d+1;end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','session_id','rec-client')::text,true);
 set local role authenticated;
 anchor:=public.book_appointment(b,s,(d+time '10:00')at time zone 'Europe/Rome');
 p:=public.create_recurring_plan(anchor,28,5);
 if public.create_recurring_plan(anchor,28,5)<>p then raise exception 'plan duplicated';end if;
 begin
  perform public.create_recurring_plan(anchor,9,5);raise exception 'Invalid frequency allowed';
 exception when raise_exception then if sqlerrm<>'RECURRENCE_LOCKED' then raise;end if;end;
 begin perform public.set_recurring_policy(200,true);raise exception 'Client policy allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 -- Conflict on one date, even when outside the six-month horizon.
 future:=d+28;
 insert into public.calendar_entries(barber_id,kind,start_at,end_at)values(b,'block',(future+time '10:00')at time zone 'Europe/Rome',(future+time '10:30')at time zone 'Europe/Rome');
 set local role authenticated;
 if exists(select 1 from public.list_recurring_dates(p)where ordinal=1 and available)then raise exception 'Conflict offered';end if;
 begin perform public.save_recurring_date(p,1,(future+time '10:00')at time zone 'Europe/Rome');raise exception 'Conflict saved';exception when raise_exception then if sqlerrm<>'SLOT_TAKEN'then raise;end if;end;
 select start_at into st from public.get_recurring_slots(p,future)where start_at=(future+time '11:00')at time zone 'Europe/Rome';
 if st is null then raise exception 'Alternative missing';end if;
 ep:=public.save_recurring_date(p,1,st);
 if public.save_recurring_date(p,1,st)<>ep then raise exception 'Retry duplicated booking';end if;
 reset role;
 insert into public.schedule_exceptions(barber_id,day,closed)values(b,d+56,true);
 set local role authenticated;
 if exists(select 1 from public.list_recurring_dates(p)where ordinal=2 and available)then raise exception 'Closure offered';end if;
 perform public.save_recurring_date(p,2,null);
 reset role;
 -- Unlimited calendar horizon, including crossing summer time.
 future:=(now() at time zone 'Europe/Rome')::date+400;
 while private.is_holiday(future)loop future:=future+1;end loop;
 set local role authenticated;
 if exists(select 1 from public.get_available_slots(b,s,future))then raise exception 'Normal beyond six months';end if;
 select start_at into st from public.get_recurring_slots(p,future)where start_at=(future+time '10:00')at time zone 'Europe/Rome';
 if st is null then raise exception 'Recurring beyond six months missing';end if;
 rp:=public.save_recurring_date(p,3,st);
 reset role;
 if not exists(select 1 from public.calendar_entries where id=rp and client_id=u)then raise exception 'Wrong owner';end if;
 if private.recurring_count(u)<>2 then raise exception 'Wrong recurring total';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',v,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.list_recurring_dates(p);raise exception 'Other user read plan';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.save_recurring_date(p,4,st);raise exception 'Other user wrote plan';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin execute 'select * from private.recurring_plans';raise exception 'Direct private access';exception when insufficient_privilege then null;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 set local role authenticated;
 -- Existing periodic records do not consume the five normal slots.
 for n in 1..4 loop perform public.book_appointment(b,s,((d+time '11:00')at time zone 'Europe/Rome')+n*interval '30 minutes');end loop;
 begin perform public.book_appointment(b,s,(d+time '15:00')at time zone 'Europe/Rome');raise exception 'Sixth normal allowed';exception when raise_exception then if sqlerrm<>'LIMIT_FIVE'then raise;end if;end;
 reset role;
 -- Verify initial maximum across plans and changed settings at save time.
 update public.app_settings set recurring_max=2;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.save_recurring_date(p,4,st+interval '1 hour');raise exception 'Recurring limit bypass';exception when raise_exception then if sqlerrm<>'RECURRENCE_LIMIT'then raise;end if;end;
 perform public.cancel_appointment(ep);
 reset role;
 if private.recurring_count(u)<>1 then raise exception 'Single cancellation failed';end if;
 update public.app_settings set recurring_max=5;
 perform public.staff_authorize_session(worker,'rec-staff');
 update public.user_roles set role='barber_admin'where user_id=worker;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','rec-staff')::text,true);
 set local role authenticated;
 perform public.set_recurring_policy(5,true);
 if not public.appointment_is_recurring(rp)then raise exception 'Recurring staff marker missing';end if;
 if not exists(select 1 from public.get_reschedule_slots(rp,future))then raise exception 'Recurring staff horizon incorrectly limited';end if;
 reset role;
 if (select recurring_unlimited from public.app_settings where id)is not true then raise exception 'Lead policy failed';end if;
 update public.user_roles set role='barber'where user_id=worker;
 set local role authenticated;
 begin perform public.set_recurring_policy(5,false);raise exception 'Normal barber policy allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 -- Unlimited means no numeric business limit; results remain paginated.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 select e.id into ep from public.calendar_entries e
 where e.client_id=u and e.id<>anchor and e.status='confirmed' and not exists(select 1 from private.recurring_occurrences o where o.entry_id=e.id) limit 1;
 set local role authenticated;
 ep:=public.create_recurring_plan(ep,28,30);
 if (select count(*) from public.list_recurring_dates(ep,0))<>25
 or (select count(*) from public.list_recurring_dates(ep,25))<>5 then raise exception 'Pagination failed';end if;
 for n in 1..6 loop
  select start_at into st from public.get_recurring_slots(ep,future) where start_at=(future+time '15:00')at time zone 'Europe/Rome';
  if st is null then raise exception 'Unlimited alternative missing';end if;
  perform public.save_recurring_date(ep,n,st);
  reset role;
  future:=future+1;
  while private.is_holiday(future)loop future:=future+1;end loop;
  set local role authenticated;
 end loop;
 reset role;
 if private.recurring_count(u)<=5 then raise exception 'Unlimited count still capped';end if;
 -- Six-month normal boundary and local wall-clock recurrence across DST.
 future:=((now()at time zone 'Europe/Rome')::date+interval '5 months')::date;
 while private.is_holiday(future)loop future:=future+1;end loop;
 if not exists(select 1 from public.get_available_slots(b,s,future))then raise exception 'Five-month date unavailable';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 for rec in select * from private.list_recurring_dates(p)loop
  if (rec.expected_start at time zone 'Europe/Rome')::time<>time '10:00'then raise exception 'DST drift';end if;
 end loop;
end $test$;
select 'PASS recurring privacy, limits, horizon, local time, partial resolution, idempotency, cancellation, staff settings' as result;

rollback;
