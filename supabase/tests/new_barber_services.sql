begin;
do $test$
declare
  admin_id uuid:=gen_random_uuid(); barber_user uuid:=gen_random_uuid(); client_id uuid:=gen_random_uuid();
  source_id uuid; inactive_id uuid; deleted_id uuid; target_id uuid;
  shared_id uuid; disabled_id uuid; archived_id uuid; unlinked_id uuid; inactive_only uuid; deleted_only uuid; saved_id uuid;
  expected_ids uuid[]; actual_ids uuid[];
begin
  insert into auth.users(id,email,raw_user_meta_data) values
    (admin_id,'seed-admin@example.invalid','{"first_name":"Seed","last_name":"Admin"}'),
    (barber_user,'seed-barber@example.invalid','{"first_name":"Seed","last_name":"Barber"}'),
    (client_id,'seed-client@example.invalid','{"first_name":"Seed","last_name":"Client"}');
  update public.user_roles set role='admin' where user_id=admin_id;
  perform public.staff_authorize_session(admin_id,'seed-admin-session');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated','session_id','seed-admin-session')::text,true);
  set local role authenticated;
  insert into public.barbers(name) values('Seed source') returning id into source_id;
  insert into public.barbers(name,active) values('Seed inactive',false) returning id into inactive_id;
  insert into public.barbers(name,active,deleted_at) values('Seed deleted',false,now()) returning id into deleted_id;
  insert into public.services(name,duration_minutes,price) values('Seed shared',30,20) returning id into shared_id;
  insert into public.services(name,duration_minutes,price,active) values('Seed disabled',30,20,false) returning id into disabled_id;
  insert into public.services(name,duration_minutes,price,active,deleted_at) values('Seed archived',30,20,false,now()) returning id into archived_id;
  insert into public.services(name,duration_minutes,price) values('Seed unlinked',30,20) returning id into unlinked_id;
  insert into public.services(name,duration_minutes,price) values('Seed inactive only',30,20) returning id into inactive_only;
  insert into public.services(name,duration_minutes,price) values('Seed deleted only',30,20) returning id into deleted_only;
  insert into public.barber_services values(source_id,shared_id),(source_id,disabled_id),(source_id,archived_id),(inactive_id,inactive_only),(deleted_id,deleted_only);
  select array_agg(distinct s.id order by s.id) into expected_ids
  from public.barber_services bs join public.barbers b on b.id=bs.barber_id join public.services s on s.id=bs.service_id
  where b.active and b.deleted_at is null and bs.active and s.active and s.deleted_at is null;
  insert into public.barbers(name,user_id) values('Seed target',barber_user) returning id into target_id;
  select array_agg(service_id order by service_id) into actual_ids from public.barber_services where barber_id=target_id;
  if actual_ids is distinct from expected_ids then raise exception 'Incorrect initial services'; end if;
  if exists(select 1 from public.barber_services where barber_id=target_id and service_id in(disabled_id,archived_id,unlinked_id,inactive_only,deleted_only)) then raise exception 'Ineligible service inherited'; end if;
  delete from public.barber_services where barber_id=target_id and service_id=shared_id;
  update public.barbers set name='Seed renamed' where id=target_id;
  if exists(select 1 from public.barber_services where barber_id=target_id and service_id=shared_id) then raise exception 'Update restored removed service'; end if;
  insert into public.barber_services values(target_id,shared_id);
  reset role;
  if (select role from public.user_roles where user_id=barber_user)<>'barber' then raise exception 'Role not assigned'; end if;
  update public.user_roles set role='barber_admin' where user_id=barber_user;
  perform public.staff_authorize_session(barber_user,'seed-barber-session');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',barber_user,'role','authenticated','session_id','seed-barber-session')::text,true);
  set local role authenticated;
  saved_id:=public.save_barber_service(target_id,shared_id,'Seed personal','Personal description',45,25);
  if saved_id=shared_id then raise exception 'Shared service not isolated'; end if;
  if not exists(select 1 from public.services where id=shared_id and name='Seed shared' and price=20 and duration_minutes=30) then raise exception 'Source service changed'; end if;
  if not exists(select 1 from public.barber_services where barber_id=source_id and service_id=shared_id) then raise exception 'Source association lost'; end if;
  perform public.remove_barber_service(target_id,saved_id);
  saved_id:=public.save_barber_service(target_id,null,'Seed new personal','',15,10);
  if not exists(select 1 from public.barber_services where barber_id=target_id and service_id=saved_id) then raise exception 'Cannot add personal service'; end if;
  begin insert into public.barbers(name) values('Unauthorized barber'); raise exception 'Barber created another barber'; exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',client_id,'role','authenticated','session_id','seed-client-session')::text,true);
  set local role authenticated;
  begin insert into public.barbers(name) values('Unauthorized client'); raise exception 'Client created barber'; exception when insufficient_privilege then null; end;
  reset role;
  if has_function_privilege('authenticated','private.seed_new_barber_services()','execute') or has_function_privilege('anon','private.seed_new_barber_services()','execute') then raise exception 'Trigger function callable'; end if;
end $test$;
rollback;
