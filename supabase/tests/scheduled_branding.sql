begin;
do $test$
declare ad uuid:=gen_random_uuid();worker uuid:=gen_random_uuid();client uuid:=gen_random_uuid(); cfg jsonb;v uuid;oldv uuid;b uuid;original text;token text:=gen_random_uuid()::text||gen_random_uuid()::text;claimed jsonb;
begin
 select current_name into original from private.branding_settings where id;
 if not exists(select 1 from vault.secrets where name='branding_management_token')then
  perform vault.create_secret('test-not-a-real-token','branding_management_token');
 end if;
 insert into auth.users(id,email,raw_user_meta_data)values(ad,'brand-admin@example.invalid','{}'),(worker,'brand-worker@example.invalid','{}'),(client,'brand-client@example.invalid','{}');
 update public.user_roles set role='admin'where user_id=ad;
 insert into public.barbers(name,user_id)values('TEST brand worker',worker)returning id into b;
 perform public.staff_authorize_session(ad,'brand-admin');perform public.staff_authorize_session(worker,'brand-worker');
 foreach v in array array[client,worker] loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v,'role','authenticated','session_id','brand-worker')::text,true);
  set local role authenticated;
  begin perform public.schedule_brand_name('bARber Àlfa');raise exception 'Non-admin scheduled';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  begin perform public.branding_status();raise exception 'Non-admin pending info';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  begin perform public.claim_brand_activation(gen_random_uuid(),'wrong');raise exception 'Credential RPC exposed';exception when insufficient_privilege then null;end;
  reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','brand-admin')::text,true);
 set local role authenticated;
 begin perform public.schedule_brand_name('<script>');raise exception 'Invalid name';exception when raise_exception then if sqlerrm<>'INVALID_BRAND_NAME'then raise;end if;end;
 cfg:=public.schedule_brand_name('bARber Àlfa');
 if cfg->>'pending_name'<>'bARber Àlfa'then raise exception 'Case lost';end if;
 if extract(epoch from((cfg->>'activates_at')::timestamptz-clock_timestamp()))not between 898 and 901 then raise exception 'Not 15 minutes';end if;
 if public.app_branding()->>'name'<>original or public.pwa_manifest()->>'name'<>original then raise exception 'Published early';end if;
 if public.app_branding()?'pending_name'then raise exception 'Pending name publicly exposed';end if;
 begin update public.app_settings set shop_name='Bypass'where id;raise exception 'Delay bypass';exception when raise_exception then if sqlerrm<>'USE_SCHEDULED_BRAND_NAME'then raise;end if;end;
 reset role;
 select version into oldv from private.branding_settings where id;
 perform private.activate_brand_name(oldv);
 if public.app_branding()->>'name'<>original then raise exception 'Early job activated';end if;
 set local role authenticated;
 cfg:=public.cancel_brand_name();
 if cfg->>'pending_name'is not null then raise exception 'Cancel failed';end if;
 cfg:=public.schedule_brand_name('bARber Àlfa');
 reset role;
 perform private.activate_brand_name(oldv);
 if public.app_branding()->>'name'<>original then raise exception 'Stale job activated';end if;
 update private.branding_settings set activates_at=clock_timestamp()-interval '1 second',
 sync_token_hash=encode(extensions.digest(token,'sha256'),'hex'),sync_expires_at=clock_timestamp()+interval '3 minutes'
 where id returning version into v;
 if private.claim_brand_activation(v,'wrong')is not null then raise exception 'Wrong queue token accepted';end if;
 claimed:=private.claim_brand_activation(v,token);
 if claimed->>'name'<>'bARber Àlfa'or claimed->>'access_token'is null then raise exception 'Claim failed';end if;
 if private.claim_brand_activation(v,token)is not null then raise exception 'Token reused';end if;
 set local role authenticated;
 begin perform public.cancel_brand_name();raise exception 'Cancelled during sender update';exception when raise_exception then if sqlerrm<>'BRAND_CHANGE_PROCESSING'then raise;end if;end;
 reset role;
 if private.finish_brand_activation(v,token,false)then raise exception 'Failure published';end if;
 if public.app_branding()->>'name'<>original then raise exception 'Failed sender update changed app';end if;
 claimed:=private.claim_brand_activation(v,token);
 if not private.finish_brand_activation(v,token,true)then raise exception 'Successful update did not publish';end if;
 if public.app_branding()->>'name'<>'bARber Àlfa'or public.pwa_manifest()->>'short_name'<>'bARber Àlfa'or public.public_app_settings()->>'shop_name'<>'bARber Àlfa'then raise exception 'Names inconsistent';end if;
 if exists(select 1 from auth.users where id in(ad,worker,client)and raw_user_meta_data->>'branding_name'<>'bARber Àlfa')then raise exception 'Email metadata stale';end if;
 if exists(select 1 from cron.job where jobname='barberup-brand-name-activation')then raise exception 'One shot job retained';end if;
 set local role anon;
 if public.app_branding()->>'name'<>'bARber Àlfa'then raise exception 'Public brand unavailable';end if;
 begin perform public.schedule_brand_name('No');raise exception 'Anon schedule';exception when insufficient_privilege then null;end;
 reset role;
end $test$;
select 'PASS preserved case, admin-only 15 minute schedule, cancellation/replacement, direct bypass denied, secret isolation, expiring single-use claim, failed SMTP does not publish, coherent activation' result;
rollback;