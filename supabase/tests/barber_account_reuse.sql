begin;
do $test$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();ad uuid:=gen_random_uuid();first_barber uuid;second_barber uuid;another uuid;admin_barber uuid;sv uuid;appointment uuid;
begin
 insert into auth.users(id,email,raw_user_meta_data) values
 (a,'barber-reuse-a@example.invalid','{}'),(b,'barber-reuse-b@example.invalid','{}'),(ad,'barber-reuse-admin@example.invalid','{}');
 update public.user_roles set role='admin' where user_id=ad;
 insert into public.barbers(name,user_id) values('First test',a) returning id into first_barber;
 perform public.staff_authorize_session(a,'reuse-a');
 insert into public.services(name,duration_minutes,price) values('Historical test',30,10) returning id into sv;
 insert into public.calendar_entries(barber_id,kind,service_id,client_id,start_at,end_at,service_name,price)
 values(first_barber,'appointment',sv,b,now()-interval '2 hours',now()-interval '90 minutes','Historical test',10) returning id into appointment;
 update public.barbers set active=false,deleted_at=now() where id=first_barber;
 if (select role from public.user_roles where user_id=a)<>'client' then raise exception 'deleted barber not demoted';end if;
 if exists(select 1 from private.staff_sessions where user_id=a) then raise exception 'stale staff permission retained';end if;
 if not exists(select 1 from public.calendar_entries where id=appointment and barber_id=first_barber) then raise exception 'history modified';end if;
 insert into public.barbers(name,user_id) values('Second test',a) returning id into second_barber;
 if (select role from public.user_roles where user_id=a)<>'barber' then raise exception 'recreated barber not promoted';end if;
 begin insert into public.barbers(name,user_id) values('Duplicate live test',a);raise exception 'duplicate association accepted';exception when unique_violation then null;end;
 insert into public.barbers(name,user_id) values('Another test',b) returning id into another;
 update public.barbers set active=false where id=another;
 if (select role from public.user_roles where user_id=b)<>'barber' then raise exception 'temporary deactivation demoted role';end if;
 update public.barbers set active=true where id=another;
 update public.barbers set user_id=null where id=another;
 if (select role from public.user_roles where user_id=b)<>'client' then raise exception 'unlinked barber not demoted';end if;
 update public.barbers set user_id=b where id=another;
 insert into public.barbers(name,user_id) values('Admin test',ad) returning id into admin_barber;
 update public.barbers set active=false,deleted_at=now() where id=admin_barber;
 if (select role from public.user_roles where user_id=ad)<>'admin' then raise exception 'admin role demoted';end if;
 delete from public.barbers where id=another;
 if (select role from public.user_roles where user_id=b)<>'client' then raise exception 'physical delete not demoted';end if;
 perform public.staff_authorize_session(ad,'reuse-admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','reuse-admin')::text,true);
 set local role authenticated;
 perform public.admin_delete_resource('barber',second_barber);
 reset role;
 if (select role from public.user_roles where user_id=a)<>'client' then raise exception 'admin deletion did not demote';end if;
end $test$;
rollback;
