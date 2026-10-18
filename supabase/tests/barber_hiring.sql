begin;
do $test$
declare
 lead uuid:=gen_random_uuid(); regular uuid:=gen_random_uuid(); candidate uuid:=gen_random_uuid(); other_client uuid:=gen_random_uuid();
 unverified uuid:=gen_random_uuid(); orphan uuid:=gen_random_uuid(); ad uuid:=gen_random_uuid();
 source_b uuid; regular_b uuid; hired_b uuid; s uuid; disabled_s uuid; expected uuid[]; actual uuid[];
 users_before integer; phone text:='0990000011';
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (lead,'hire-lead@example.invalid',now(),'{"first_name":"Hire","last_name":"Lead","phone":"0990000001"}'),
 (regular,'hire-regular@example.invalid',now(),'{"first_name":"Hire","last_name":"Regular","phone":"0990000002"}'),
 (candidate,'hire-candidate@example.invalid',now(),'{"first_name":"Hire","last_name":"Candidate","phone":"0990000011"}'),
 (other_client,'hire-other@example.invalid',now(),'{"first_name":"Hire","last_name":"Other","phone":"0990000012"}'),
 (unverified,'hire-unverified@example.invalid',null,'{"first_name":"Hire","last_name":"Unverified","phone":"0990000013"}'),
 (orphan,'hire-orphan@example.invalid',now(),'{"first_name":"Hire","last_name":"Orphan","phone":"0990000014"}'),
 (ad,'hire-admin@example.invalid',now(),'{"first_name":"Hire","last_name":"Admin","phone":"0990000015"}');
 insert into public.barbers(name,user_id) values('Hire source',lead) returning id into source_b;
 insert into public.barbers(name,user_id) values('Hire regular',regular) returning id into regular_b;
 update public.user_roles set role='barber_admin' where user_id in(lead,orphan);
 update public.user_roles set role='admin' where user_id=ad;
 insert into public.services(name,duration_minutes,price) values('Hire active service',30,20) returning id into s;
 insert into public.services(name,duration_minutes,price) values('Hire disabled association',30,20) returning id into disabled_s;
 insert into public.barber_services(barber_id,service_id,active) values(source_b,s,true),(source_b,disabled_s,false);
 select count(*) into users_before from auth.users;
 perform public.staff_authorize_session(lead,'hire-lead-session');
 perform public.staff_authorize_session(regular,'hire-regular-session');
 perform public.staff_authorize_session(orphan,'hire-orphan-session');
 perform public.staff_authorize_session(ad,'hire-admin-session');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',regular,'role','authenticated','session_id','hire-regular-session')::text,true);
 set local role authenticated;
 begin perform public.check_barber_hire_candidate('hire-candidate@example.invalid',phone);raise exception 'Regular lookup allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.hire_barber('hire-candidate@example.invalid',phone,'Forbidden');raise exception 'Regular hire allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',candidate,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.hire_barber('hire-other@example.invalid','0990000012','Forbidden');raise exception 'Client hire allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',orphan,'role','authenticated','session_id','hire-orphan-session')::text,true);
 set local role authenticated;
 begin perform public.check_barber_hire_candidate('hire-candidate@example.invalid',phone);raise exception 'Orphan staff allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.check_barber_hire_candidate('hire-candidate@example.invalid',phone);raise exception 'Unverified session allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','hire-lead-session')::text,true);
 set local role authenticated;
 if public.check_barber_hire_candidate(' HIRE-CANDIDATE@EXAMPLE.INVALID ','+39 099 000 0011') is distinct from true then raise exception 'Pair rejected';end if;
 begin perform public.check_barber_hire_candidate('hire-candidate@example.invalid','0990000012');raise exception 'Mismatched phone accepted';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 begin perform public.check_barber_hire_candidate('hire-other@example.invalid',phone);raise exception 'Mismatched email accepted';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 begin perform public.check_barber_hire_candidate('unknown@example.invalid',phone);raise exception 'Unknown account accepted';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 if not public.check_barber_hire_candidate('hire-unverified@example.invalid','0990000013') then raise exception 'Registered client not found';end if;
 begin perform public.check_barber_hire_candidate('hire-admin@example.invalid','0990000015');raise exception 'Admin candidate accepted';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 begin perform public.check_barber_hire_candidate('hire-regular@example.invalid','0990000002');raise exception 'Already assigned staff accepted';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 begin perform public.hire_barber('hire-candidate@example.invalid',phone,'  ');raise exception 'Blank agenda name accepted';exception when raise_exception then if sqlerrm<>'INVALID_BARBER_NAME' then raise;end if;end;
 reset role;
 update public.profiles set phone='0990000099' where id=candidate;
 set local role authenticated;
 begin perform public.hire_barber('hire-candidate@example.invalid',phone,'Changed');raise exception 'Changed phone accepted';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 reset role;
 update public.profiles set phone='0990000011' where id=candidate;
 update auth.users set banned_until=now()+interval '1 day' where id=candidate;
 set local role authenticated;
 begin perform public.check_barber_hire_candidate('hire-candidate@example.invalid',phone);raise exception 'Banned candidate accepted';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 reset role;
 update auth.users set banned_until=null where id=candidate;
 select array_agg(distinct x.service_id order by x.service_id) into expected
 from public.barber_services x join public.barbers b on b.id=x.barber_id join public.services svc on svc.id=x.service_id
 where x.active and b.active and b.deleted_at is null and svc.active and svc.deleted_at is null;
 set local role authenticated;
 -- No front-end proof or user ID is trusted: the final RPC repeats the match.
 hired_b:=public.hire_barber('hire-candidate@example.invalid','0039 099 000 0011','  Nome scelto dal responsabile  ');
 begin perform public.hire_barber('hire-candidate@example.invalid',phone,'Duplicate');raise exception 'Duplicate hire allowed';exception when raise_exception then if sqlerrm<>'HIRE_ACCOUNT_UNAVAILABLE' then raise;end if;end;
 begin insert into public.barbers(name,user_id) values('Bypass',other_client);raise exception 'Direct staff insert allowed';exception when insufficient_privilege then null;end;
 reset role;
 if (select role from public.user_roles where user_id=candidate)<>'barber' then raise exception 'Hired role incorrect';end if;
 if not exists(select 1 from public.barbers where id=hired_b and name='Nome scelto dal responsabile' and user_id=candidate and active) then raise exception 'Agenda not created';end if;
 select array_agg(service_id order by service_id) into actual from public.barber_services where barber_id=hired_b and active;
 if actual is distinct from expected then raise exception 'Inherited services incorrect';end if;
 if exists(select 1 from public.barber_services where barber_id=hired_b and service_id=disabled_s) then raise exception 'Disabled association inherited';end if;
 if (select count(*) from auth.users)<>users_before then raise exception 'Created Auth account';end if;
 perform public.staff_authorize_session(candidate,'hire-new-session');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',candidate,'role','authenticated','session_id','hire-new-session')::text,true);
 set local role authenticated;
 perform public.set_barber_service_active(hired_b,s,false);
 begin perform public.save_barber_service(hired_b,s,'Forbidden','',30,25);raise exception 'New barber can edit';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.remove_barber_service(hired_b,s);raise exception 'New barber can delete';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.hire_barber('hire-other@example.invalid','0990000012','Forbidden');raise exception 'Hired barber can hire';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
 if not exists(select 1 from public.barber_services where barber_id=source_b and service_id=s and active) then raise exception 'Source disabled';end if;
 if has_function_privilege('anon','public.hire_barber(text,text,text)','execute') or has_function_privilege('anon','public.check_barber_hire_candidate(text,text)','execute') or has_function_privilege('authenticated','private.resolve_barber_hire_candidate(text,text)','execute') then raise exception 'Unsafe grants';end if;
end $test$;
rollback;