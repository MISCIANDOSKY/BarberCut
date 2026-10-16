begin;
do $test$
declare old_user uuid:=gen_random_uuid();active_user uuid:=gen_random_uuid();staff_user uuid:=gen_random_uuid();admin_user uuid:=gen_random_uuid();future_user uuid:=gen_random_uuid();ba uuid;sv uuid;old_ap uuid;boundary_ap uuid;recent_ap uuid;future_ap uuid;block_id uuid;cutoff timestamptz;output jsonb;
begin
 insert into auth.users(id,email,created_at,last_sign_in_at,raw_user_meta_data) values
 (old_user,'maintenance-old@example.invalid',now()-interval '200 days',now()-interval '121 days','{"first_name":"Old","last_name":"Test"}'),
 (active_user,'maintenance-active@example.invalid',now()-interval '200 days',now()-interval '121 days','{}'),
 (staff_user,'maintenance-barber@example.invalid',now()-interval '200 days',now()-interval '121 days','{}'),
 (admin_user,'maintenance-admin@example.invalid',now()-interval '200 days',now()-interval '121 days','{}'),
 (future_user,'maintenance-future@example.invalid',now()-interval '200 days',now()-interval '121 days','{}');
 update public.user_roles set role='admin' where user_id=admin_user;
 insert into public.barbers(name,user_id) values('Maintenance test barber',staff_user) returning id into ba;
 insert into public.services(name,duration_minutes,price) values('Maintenance test service',30,10) returning id into sv;
 insert into private.user_activity values(active_user,now());
 cutoff:=(((now() at time zone 'Europe/Rome')::date-40)::timestamp at time zone 'Europe/Rome');
 insert into public.calendar_entries(barber_id,service_id,kind,client_id,start_at,end_at,service_name,price) values(ba,sv,'appointment',old_user,cutoff-interval '2 hours',cutoff-interval '1 hour','Old',10) returning id into old_ap;
 insert into public.calendar_entries(barber_id,service_id,kind,client_id,start_at,end_at,service_name,price) values(ba,sv,'appointment',active_user,cutoff-interval '30 minutes',cutoff,'Boundary',10) returning id into boundary_ap;
 insert into public.calendar_entries(barber_id,service_id,kind,client_id,start_at,end_at,service_name,price) values(ba,sv,'appointment',active_user,now()-interval '2 hours',now()-interval '1 hour','Recent',10) returning id into recent_ap;
 insert into public.calendar_entries(barber_id,service_id,kind,client_id,start_at,end_at,service_name,price) values(ba,sv,'appointment',future_user,now()+interval '2 days',now()+interval '2 days 30 minutes','Future',10) returning id into future_ap;
 insert into public.calendar_entries(barber_id,kind,start_at,end_at) values(ba,'block',cutoff-interval '4 hours',cutoff-interval '3 hours') returning id into block_id;
 insert into private.inactivity_cycles(user_id,activity_at,inactive_days,disable_after) values(old_user,now()-interval '121 days',120,now()-interval '1 day');
 insert into private.inactivity_notices(cycle_id,lead_days,status,sent_at) select id,7,'sent',now()-interval '8 days' from private.inactivity_cycles where user_id=old_user;
 output:=private.run_daily_maintenance();
 if (select banned_until is null or banned_until<=now() from auth.users where id=old_user) then raise exception 'inactive user not disabled';end if;
 if exists(select 1 from auth.users where id in(active_user,staff_user,admin_user,future_user) and banned_until>now()) then raise exception 'protected/recent/future user disabled';end if;
 if exists(select 1 from public.calendar_entries where id=old_ap) then raise exception 'old appointment not deleted';end if;
 if (select count(*) from public.calendar_entries where id in(boundary_ap,recent_ap,future_ap,block_id))<>4 then raise exception 'boundary/recent/future/block removed';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',active_user,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.maintenance_status();raise exception 'client status allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform public.save_maintenance_settings(1,1,true,true);raise exception 'client save allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 begin perform private.run_daily_maintenance();raise exception 'client worker allowed';exception when insufficient_privilege then null;end;
 perform public.record_activity();
 reset role;
 perform public.staff_authorize_session(admin_user,'maintenance-test-session');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_user,'role','authenticated','session_id','maintenance-test-session')::text,true);
 set local role authenticated;
 begin perform public.save_maintenance_settings(0,40,true,true);raise exception 'zero days accepted';exception when raise_exception then if sqlerrm<>'INVALID_MAINTENANCE_DAYS' then raise;end if;end;
 perform public.save_maintenance_settings(120,40,true,true);
 if (public.maintenance_status()->'settings'->>'inactive_days')::integer<>120 then raise exception 'settings not saved';end if;
 perform public.reactivate_inactive_account(old_user);
 reset role;
 if exists(select 1 from private.inactive_accounts where user_id=old_user) or exists(select 1 from auth.users where id=old_user and banned_until>now()) then raise exception 'reactivation failed';end if;
 perform private.run_daily_maintenance();
 if exists(select 1 from private.inactive_accounts where user_id=old_user) then raise exception 'reactivated user disabled again';end if;
end $test$;
rollback;
