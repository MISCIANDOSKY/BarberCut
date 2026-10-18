begin;
update public.app_settings set require_user_approval=true where id;
do $test$
declare
 lead uuid:=gen_random_uuid(); worker uuid:=gen_random_uuid(); ad uuid:=gen_random_uuid();
 candidate uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); rejected uuid:=gen_random_uuid();
 lead_agenda uuid; worker_agenda uuid; hired_agenda uuid; created_agenda uuid;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (lead,'power-lead@example.invalid',now(),'{"first_name":"Power","last_name":"Lead","phone":"0993000001"}'),
 (worker,'power-worker@example.invalid',now(),'{"first_name":"Power","last_name":"Worker","phone":"0993000002"}'),
 (ad,'power-admin@example.invalid',now(),'{"first_name":"Power","last_name":"Admin","phone":"0993000003"}'),
 (candidate,'power-candidate@example.invalid',now(),'{"first_name":"Power","last_name":"Hired","phone":"0993000004"}'),
 (client,'power-client@example.invalid',now(),'{"first_name":"Power","last_name":"Client","phone":"0993000005"}'),
 (rejected,'power-rejected@example.invalid',now(),'{"first_name":"Power","last_name":"Rejected","phone":"0993000006"}');
 update public.user_roles set role='admin' where user_id=ad;
 insert into public.barbers(name,user_id) values('Power lead',lead) returning id into lead_agenda;
 insert into public.barbers(name,user_id) values('Power worker',worker) returning id into worker_agenda;
 update public.user_roles set role='barber_admin' where user_id=lead;
 if exists(select 1 from public.barbers where id in(lead_agenda,worker_agenda) and can_approve_clients) then raise exception 'Default approval power granted';end if;
 perform public.staff_authorize_session(lead,'power-lead');
 perform public.staff_authorize_session(worker,'power-worker');
 perform public.staff_authorize_session(ad,'power-admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','power-worker')::text,true);
 set local role authenticated;
 if public.can_review_registrations() then raise exception 'Unflagged worker allowed';end if;
 begin perform public.list_registration_requests('pending');raise exception 'Worker read without flag';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.review_registration(client,'approved');raise exception 'Worker approved without flag';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.set_registration_approver(worker_agenda,true);raise exception 'Worker self grant';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 update public.barbers set can_approve_clients=true where id=worker_agenda;
 if public.can_review_registrations() then raise exception 'Direct flag bypass';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','power-lead')::text,true);
 set local role authenticated;
 if public.can_review_registrations() then raise exception 'Unflagged lead can review';end if;
 perform public.set_registration_policy(false);
 perform public.set_registration_policy(true);
 if not exists(select 1 from public.list_registration_approvers() where barber_id=worker_agenda and not can_approve) then raise exception 'Worker missing';end if;
 hired_agenda:=public.hire_barber('power-candidate@example.invalid','0993000004','Power hired');
 if exists(select 1 from public.barbers where id=hired_agenda and can_approve_clients) then raise exception 'Hire defaults enabled';end if;
 perform public.set_registration_approver(worker_agenda,true);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','power-worker')::text,true);
 set local role authenticated;
 if not public.can_review_registrations() then raise exception 'Enabled worker blocked';end if;
 perform public.review_registration(client,'approved');
 perform public.review_registration(rejected,'rejected');
 if not exists(select 1 from jsonb_array_elements(public.list_registration_requests('approved')) v where v->>'user_id'=client::text and v->>'reviewed_by_name'='Power Worker') then raise exception 'Attribution lost';end if;
 begin perform public.list_registration_approvers();raise exception 'Worker manages approvers';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.set_registration_policy(false);raise exception 'Worker manages shop';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','power-lead')::text,true);
 set local role authenticated;
 perform public.set_registration_approver(lead_agenda,true);
 perform public.set_registration_approver(lead_agenda,false);
 perform public.set_registration_approver(worker_agenda,false);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','power-worker')::text,true);
 set local role authenticated;
 if public.can_review_registrations() then raise exception 'Revocation ineffective';end if;
 begin perform public.list_registration_requests('approved');raise exception 'Revoked worker still reads';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','power-admin')::text,true);
 set local role authenticated;
 if not public.can_review_registrations() then raise exception 'Admin blocked';end if;
 insert into public.barbers(name) values('Power admin-created') returning id into created_agenda;
 if exists(select 1 from public.barbers where id=created_agenda and can_approve_clients) then raise exception 'Admin-created defaults enabled';end if;
 perform public.set_registration_approver(worker_agenda,true);
 reset role;
 update public.barbers set active=false where id=worker_agenda;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','power-worker')::text,true);
 set local role authenticated;
 if public.can_review_registrations() then raise exception 'Inactive agenda review allowed';end if;
 reset role;
 update public.barbers set deleted_at=now() where id=worker_agenda;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','power-lead')::text,true);
 set local role authenticated;
 hired_agenda:=public.hire_barber('power-worker@example.invalid','0993000002','Power rehired');
 if exists(select 1 from public.barbers where id=hired_agenda and can_approve_clients) then raise exception 'Rehire retained permission';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',client,'role','authenticated')::text,true);
 set local role authenticated;
 if public.can_review_registrations() then raise exception 'Client can review';end if;
 begin perform public.list_registration_approvers();raise exception 'Client manages reviewers';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 if has_function_privilege('anon','public.set_registration_approver(uuid,boolean)','execute') or has_function_privilege('anon','public.list_registration_approvers()','execute') or has_function_privilege('anon','public.can_review_registrations()','execute') then raise exception 'Anonymous grant';end if;
end $test$;
rollback;
