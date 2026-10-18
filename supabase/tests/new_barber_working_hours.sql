begin;
update public.app_settings set require_user_approval=false where id;
-- Keep the test independent from real schedules, all changes are rolled back.
update public.barbers set active=false where active;
do $test$
declare
 lead uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid(); candidate uuid:=gen_random_uuid();
 source_agenda uuid; admin_created uuid; hired uuid; service uuid;
begin
 insert into auth.users(id,email,raw_user_meta_data) values
 (lead,'schedule-lead@example.invalid','{"first_name":"Test","last_name":"Lead","phone":"390000000001"}'),
 (admin_id,'schedule-admin@example.invalid','{"first_name":"Test","last_name":"Admin","phone":"390000000002"}'),
 (candidate,'schedule-candidate@example.invalid','{"first_name":"Test","last_name":"Hire","phone":"390000000003"}');
 update public.user_roles set role='admin' where user_id=admin_id;
 insert into public.barbers(name,user_id) values('Schedule lead',lead) returning id into source_agenda;
 if exists(select 1 from public.working_hours where barber_id=source_agenda) then raise exception 'First agenda inherited inactive hours';end if;
 update public.user_roles set role='barber_admin' where user_id=lead;
 insert into public.working_hours(barber_id,weekday,opens,closes) values
 (source_agenda,2,'08:00','20:00'),(source_agenda,3,'08:00','14:00'),(source_agenda,3,'16:00','20:00');
 insert into public.schedule_exceptions(barber_id,day,closed) values(source_agenda,(now() at time zone 'Europe/Rome')::date+20,true);
 insert into public.services(name,duration_minutes,price) values('Schedule inherited service',30,20) returning id into service;
 insert into public.barber_services(barber_id,service_id) values(source_agenda,service);
 perform public.staff_authorize_session(admin_id,'schedule-admin');
 perform public.staff_authorize_session(lead,'schedule-lead');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','session_id','schedule-admin')::text,true);
 set local role authenticated;
 insert into public.barbers(name) values('Schedule admin-created') returning id into admin_created;
 reset role;
 if exists((select weekday,opens,closes from public.working_hours where barber_id=source_agenda except select weekday,opens,closes from public.working_hours where barber_id=admin_created) union all (select weekday,opens,closes from public.working_hours where barber_id=admin_created except select weekday,opens,closes from public.working_hours where barber_id=source_agenda)) then raise exception 'Admin schedule differs';end if;
 if not exists(select 1 from public.barber_services where barber_id=admin_created and service_id=service and active) then raise exception 'Services no longer copied';end if;
 -- A different normal agenda must not merge with the selected source.
 insert into public.working_hours(barber_id,weekday,opens,closes) values(admin_created,1,'01:00','02:00');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','schedule-lead')::text,true);
 set local role authenticated;
 hired:=public.hire_barber('schedule-candidate@example.invalid','390000000003','Schedule hired');
 reset role;
 if (select role from public.user_roles where user_id=candidate)<>'barber' then raise exception 'Hired role changed';end if;
 if (select count(*) from public.working_hours where barber_id=hired)<>3 then raise exception 'Hire schedule not exact';end if;
 if exists(select 1 from public.working_hours where barber_id=hired and weekday in(0,1,4,5,6)) then raise exception 'Closed days not preserved';end if;
 if exists(select 1 from public.schedule_exceptions where barber_id=hired) then raise exception 'Personal holidays copied';end if;
 if not exists(select 1 from public.barber_services where barber_id=hired and service_id=service and active) then raise exception 'Hire services missing';end if;
 update public.barbers set name='Schedule renamed' where id=hired;
 if (select count(*) from public.working_hours where barber_id=hired)<>3 then raise exception 'Update seeded duplicate hours';end if;
 delete from public.working_hours where barber_id=hired and weekday=2;
 if not exists(select 1 from public.working_hours where barber_id=source_agenda and weekday=2) then raise exception 'Schedules remain linked';end if;
 if has_function_privilege('authenticated','private.seed_new_barber_working_hours()','execute') or has_function_privilege('anon','private.seed_new_barber_working_hours()','execute') then raise exception 'Trigger exposed';end if;
end $test$;
rollback;
