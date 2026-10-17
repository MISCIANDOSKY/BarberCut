begin;
do $test$
declare
  ad uuid := gen_random_uuid();
  ba uuid := gen_random_uuid();
  orphan uuid := gen_random_uuid();
  cl uuid := gen_random_uuid();
  automatic uuid := gen_random_uuid();
  agenda uuid;
  before_settings jsonb;
begin
  update public.app_settings set require_user_approval=true where id;
  insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
    (ad,'policy-admin@example.invalid',now(),'{}'),
    (ba,'policy-barber@example.invalid',now(),'{}'),
    (orphan,'policy-orphan@example.invalid',now(),'{}'),
    (cl,'policy-client@example.invalid',now(),'{}');
  update public.user_roles set role='admin' where user_id=ad;
  update public.user_roles set role='barber' where user_id=orphan;
  insert into public.barbers(name,user_id) values('Policy test barber',ba) returning id into agenda;
  select to_jsonb(s)-'require_user_approval' into before_settings from public.app_settings s where id;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',cl,'role','authenticated')::text,true);
  set local role authenticated;
  begin
    perform public.set_registration_policy(false);
    raise exception 'client changed registration policy';
  exception when raise_exception then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
  reset role;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',ba,'role','authenticated')::text,true);
  set local role authenticated;
  begin
    perform public.set_registration_policy(false);
    raise exception 'unverified barber changed registration policy';
  exception when raise_exception then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
  reset role;

  perform public.staff_authorize_session(ba,'policy-barber');
  perform public.staff_authorize_session(ad,'policy-admin');
  perform public.staff_authorize_session(orphan,'policy-orphan');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ba,'role','authenticated','session_id','policy-barber')::text,true);
  set local role authenticated;
  perform public.set_registration_policy(false);
  begin
    perform public.save_maintenance_with_registrations(20,20,false,false,true);
    raise exception 'barber changed full maintenance settings';
  exception when raise_exception then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
  begin
    perform public.set_registration_policy(null);
    raise exception 'null registration policy accepted';
  exception when raise_exception then
    if sqlerrm<>'INVALID_POLICY' then raise; end if;
  end;
  reset role;
  if (select require_user_approval from public.app_settings where id) then
    raise exception 'barber policy not saved';
  end if;
  if (select to_jsonb(s)-'require_user_approval' from public.app_settings s where id) is distinct from before_settings then
    raise exception 'barber changed unrelated shop settings';
  end if;
  insert into auth.users(id,email,raw_user_meta_data) values(automatic,'policy-auto@example.invalid','{}');
  if (select status from private.client_memberships where user_id=automatic)<>'approved' then
    raise exception 'new user not automatically admitted';
  end if;
  if (select status from private.client_memberships where user_id=cl)<>'pending' then
    raise exception 'existing pending user unexpectedly admitted';
  end if;

  update public.barbers set active=false where id=agenda;
  set local role authenticated;
  begin
    perform public.set_registration_policy(true);
    raise exception 'inactive barber changed policy';
  exception when raise_exception then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
  reset role;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',orphan,'role','authenticated','session_id','policy-orphan')::text,true);
  set local role authenticated;
  begin
    perform public.set_registration_policy(true);
    raise exception 'unassociated barber changed policy';
  exception when raise_exception then
    if sqlerrm<>'ACCESS_DENIED' then raise; end if;
  end;
  reset role;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','policy-admin')::text,true);
  set local role authenticated;
  perform public.set_registration_policy(true);
  reset role;
  if not (select require_user_approval from public.app_settings where id) then
    raise exception 'admin policy not saved';
  end if;
  if has_function_privilege('anon','public.set_registration_policy(boolean)','EXECUTE')
     or has_function_privilege('anon','private.set_registration_policy(boolean)','EXECUTE') then
    raise exception 'anonymous execution granted';
  end if;
end
$test$;
rollback;
