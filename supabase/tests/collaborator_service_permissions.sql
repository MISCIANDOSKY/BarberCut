begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare
 owner_user uuid:=gen_random_uuid(); worker_user uuid:=gen_random_uuid(); client_user uuid:=gen_random_uuid(); admin_user uuid:=gen_random_uuid();
 owner_agenda uuid; worker_agenda uuid; service uuid; extra_service uuid; cloned uuid; d date:=(now() at time zone 'Europe/Rome')::date+3;
begin
 insert into auth.users(id,email,raw_user_meta_data) values
 (owner_user,'collaborator-lead@example.invalid','{"first_name":"Test","last_name":"Lead","phone":"000"}'),
 (worker_user,'collaborator-worker@example.invalid','{"first_name":"Test","last_name":"Worker","phone":"001"}'),
 (client_user,'collaborator-client@example.invalid','{"first_name":"Test","last_name":"Client","phone":"002"}'),
 (admin_user,'collaborator-admin@example.invalid','{"first_name":"Test","last_name":"Admin","phone":"003"}');
 insert into public.barbers(name,user_id) values('Collaborator lead',owner_user) returning id into owner_agenda;
 insert into public.barbers(name,user_id) values('Collaborator worker',worker_user) returning id into worker_agenda;
 update public.user_roles set role='barber_admin' where user_id=owner_user;
 update public.user_roles set role='admin' where user_id=admin_user;
 insert into public.services(name,duration_minutes,price) values('Collaborator shared',30,20) returning id into service;
 insert into public.services(name,duration_minutes,price) values('Collaborator new',15,10) returning id into extra_service;
 insert into public.barber_services(barber_id,service_id) values(owner_agenda,service),(worker_agenda,service),(owner_agenda,extra_service);
 insert into public.working_hours(barber_id,weekday,opens,closes) select worker_agenda,w,'09:00','17:00' from generate_series(0,6)w;
 while private.is_holiday(d) loop d:=d+1;end loop;
 perform public.staff_authorize_session(owner_user,'collaborator-lead');
 perform public.staff_authorize_session(worker_user,'collaborator-worker');
 perform public.staff_authorize_session(admin_user,'collaborator-admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker_user,'role','authenticated','session_id','collaborator-worker')::text,true);
 set local role authenticated;
 perform public.set_barber_service_active(worker_agenda,service,false);
 if not exists(select 1 from public.barber_services where barber_id=worker_agenda and service_id=service and not active and staff_enabled) then raise exception 'Personal disable lost';end if;
 perform public.set_barber_service_active(worker_agenda,service,true);
 if not exists(select 1 from public.barber_services where barber_id=worker_agenda and service_id=service and active) then raise exception 'Personal reactivation failed';end if;
 begin perform public.service_collaborators(worker_agenda,service);raise exception 'Worker listed collaborators';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.set_collaborator_service(worker_agenda,service,owner_agenda,false);raise exception 'Worker controls lead';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated','session_id','collaborator-lead')::text,true);
 set local role authenticated;
 if not exists(select 1 from public.service_collaborators(owner_agenda,service) where barber_id=worker_agenda and enabled) then raise exception 'Collaborator missing';end if;
 begin perform public.service_collaborators(worker_agenda,service);raise exception 'Forged source accepted';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 perform public.set_collaborator_service(owner_agenda,service,worker_agenda,false);
 if exists(select 1 from public.get_available_slots(worker_agenda,service,d)) then raise exception 'Blocked service bookable';end if;
 if not exists(select 1 from public.barber_services where barber_id=owner_agenda and service_id=service and active) then raise exception 'Owner service changed';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker_user,'role','authenticated','session_id','collaborator-worker')::text,true);
 set local role authenticated;
 begin perform public.set_barber_service_active(worker_agenda,service,true);raise exception 'Worker bypassed owner restriction';exception when raise_exception then if sqlerrm<>'SERVICE_REACTIVATION_BLOCKED' then raise;end if;end;
 if exists(select 1 from public.get_manual_booking_slots(worker_agenda,service,d)) then raise exception 'Manual bypass of restriction';end if;
 update public.barber_services set active=true,staff_enabled=true where barber_id=worker_agenda and service_id=service;
 if exists(select 1 from public.barber_services where barber_id=worker_agenda and service_id=service and staff_enabled) then raise exception 'Direct bypass accepted';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated','session_id','collaborator-lead')::text,true);
 set local role authenticated;
 perform public.set_collaborator_service(owner_agenda,service,worker_agenda,true);
 perform public.set_collaborator_service(owner_agenda,extra_service,worker_agenda,true);
 if not exists(select 1 from public.barber_services where barber_id=worker_agenda and service_id=extra_service and active and staff_enabled) then raise exception 'Missing service not associated';end if;
 perform public.set_collaborator_service(owner_agenda,extra_service,worker_agenda,false);
 reset role;
 -- Global admin restrictions must also stop a personal reactivation.
 update public.services set active=false where id=service;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker_user,'role','authenticated','session_id','collaborator-worker')::text,true);
 set local role authenticated;
 begin perform public.set_barber_service_active(worker_agenda,service,true);raise exception 'Global restriction bypassed';exception when raise_exception then if sqlerrm<>'SERVICE_REACTIVATION_BLOCKED' then raise;end if;end;
 reset role;
 update public.services set active=true where id=service;
 -- Copy-on-write preserves a restriction imposed on a lead by another lead/admin.
 update public.barber_services set active=false,staff_enabled=false where barber_id=owner_agenda and service_id=service;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_user,'role','authenticated','session_id','collaborator-lead')::text,true);
 set local role authenticated;
 cloned:=public.save_barber_service(owner_agenda,service,'Collaborator variant','',30,25);
 if cloned=service or not exists(select 1 from public.barber_services where barber_id=owner_agenda and service_id=cloned and not active and not staff_enabled) then raise exception 'Clone lost restriction';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_user,'role','authenticated','session_id','collaborator-admin')::text,true);
 set local role authenticated;
 perform public.set_collaborator_service(worker_agenda,service,owner_agenda,true);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',client_user,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.service_collaborators(owner_agenda,service);raise exception 'Client access';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.set_collaborator_service(owner_agenda,service,worker_agenda,false);raise exception 'Client mutation';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 if has_function_privilege('anon','public.set_collaborator_service(uuid,uuid,uuid,boolean)','execute') or has_function_privilege('anon','public.service_collaborators(uuid,uuid)','execute') then raise exception 'Anonymous grant';end if;
end $test$;
rollback;
