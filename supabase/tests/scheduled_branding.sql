begin;
do $test$
declare ad uuid:=gen_random_uuid();worker uuid:=gen_random_uuid();client uuid:=gen_random_uuid();cfg jsonb;v uuid;oldv uuid;b uuid;original text;due timestamptz;vault_count bigint;
begin
 select current_name into original from private.branding_settings where id;
 select count(*)into vault_count from vault.secrets;
 insert into auth.users(id,email,raw_user_meta_data)values
 (ad,'brand-admin@example.invalid','{}'),(worker,'brand-worker@example.invalid','{}'),(client,'brand-client@example.invalid','{}');
 update public.user_roles set role='admin'where user_id=ad;
 insert into public.barbers(name,user_id)values('TEST brand worker',worker)returning id into b;
 perform public.staff_authorize_session(ad,'brand-admin');
 perform public.staff_authorize_session(worker,'brand-worker');
 foreach v in array array[client,worker]loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v,'role','authenticated','session_id','brand-worker')::text,true);
  set local role authenticated;
  begin perform public.schedule_brand_name('bARber Àlfa');raise exception 'Non-admin schedule';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  begin perform public.branding_status();raise exception 'Non-admin status';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
  reset role;
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','brand-admin')::text,true);
 set local role authenticated;
 if (public.branding_status()->>'setup_required')::boolean then raise exception 'Credential still required';end if;
 begin perform public.schedule_brand_name('<script>');raise exception 'Invalid name';exception when raise_exception then if sqlerrm<>'INVALID_BRAND_NAME'then raise;end if;end;
 cfg:=public.schedule_brand_name('bARber Àlfa');
 if cfg->>'pending_name'<>'bARber Àlfa'then raise exception 'Case lost';end if;
 if extract(epoch from((cfg->>'activates_at')::timestamptz-clock_timestamp()))not between 898 and 901 then raise exception 'Not 15 minutes';end if;
 if public.app_branding()->>'name'<>original or public.pwa_manifest()->>'name'<>original then raise exception 'Published early';end if;
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
 -- Accelerated boundary only inside this rolled-back test transaction.
 due:=clock_timestamp()+interval '0.2 second';
 update private.branding_settings set activates_at=due where id returning version into v;
 perform private.activate_brand_name(v);
 if clock_timestamp()<due then raise exception 'Activation before deadline';end if;
 if public.app_branding()->>'name'<>'bARber Àlfa'or public.public_app_settings()->>'shop_name'<>'bARber Àlfa'or public.pwa_manifest()->>'name'<>'bARber Àlfa'then raise exception 'Inconsistent name';end if;
 if exists(select 1 from auth.users where id in(ad,worker,client)and raw_user_meta_data->>'branding_name'<>'bARber Àlfa')then raise exception 'Email name stale';end if;
 if (select count(*)from vault.secrets)<>vault_count then raise exception 'Credentials changed';end if;
 if exists(select 1 from cron.job where jobname='barberup-brand-name-activation')then raise exception 'Job retained';end if;
 if to_regprocedure('public.claim_brand_activation(uuid,text)')is not null or to_regprocedure('public.finish_brand_activation(uuid,text,boolean)')is not null then raise exception 'Obsolete sender APIs retained';end if;
 set local role anon;
 if public.app_branding()->>'name'<>'bARber Àlfa'then raise exception 'Public brand unavailable';end if;
 begin perform public.schedule_brand_name('No');raise exception 'Anon schedule';exception when insufficient_privilege then null;end;
 reset role;
end $test$;
select 'PASS 15 minute schedule without credentials, preserved case, admin-only access, cancel/replace, exact boundary guard, consistent app/manifest/email text and no sender API' result;
rollback;