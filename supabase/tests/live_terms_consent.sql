begin;
update public.app_settings set require_user_approval=false where id;
update public.terms_versions set published=false where published;
do $test$
declare u uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid();a uuid:=gen_random_uuid();term1 uuid;term2 uuid;draft uuid;payload jsonb;role_name text;n integer;
begin
 insert into auth.users(id,email,raw_user_meta_data)values
 (u,'terms-gate-user@example.invalid','{}'),(other_user,'terms-gate-other@example.invalid','{}'),(a,'terms-gate-admin@example.invalid','{}');
 update public.user_roles set role='admin'where user_id=a;
 perform public.staff_authorize_session(a,'terms-gate-admin');
 insert into public.terms_versions(version,body,published)values('TEST consent A','Termini test prima versione sufficientemente lunghi',true)returning id into term1;
 insert into public.terms_versions(version,body,published)values('TEST consent B','Termini test seconda versione sufficientemente lunghi',false)returning id into term2;
 insert into public.terms_versions(version,body,published)values('TEST consent draft','Bozza privata non pubblicata sufficientemente lunga',false)returning id into draft;
 -- Every application role is subject to the same own-account consent check.
 foreach role_name in array array['client','barber','barber_admin','shop','admin'] loop
  update public.user_roles set role=role_name where user_id=u;
  delete from public.terms_acceptances where user_id=u;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','session_id','terms-gate-user')::text,true);
  set local role authenticated;
  payload:=public.current_terms_status();
  if payload->>'accepted'<>'false' or payload->'terms'->>'id'<>term1::text then raise exception 'Consent bypass for role %',role_name;end if;
  begin perform public.accept_current_terms(draft);raise exception 'Draft accepted';exception when raise_exception then if sqlerrm<>'TERMS_CHANGED'then raise;end if;end;
  perform public.accept_current_terms(term1);
  perform public.accept_current_terms(term1);
  payload:=public.current_terms_status();
  if payload->>'accepted'<>'true'then raise exception 'Consent not applied for role %',role_name;end if;
  reset role;
  if (select count(*) from public.terms_acceptances where user_id=u and terms_id=term1)<>1 then raise exception 'Duplicate acceptance';end if;
 end loop;
 -- Publishing a draft invalidates only the previous consent, never creates consent implicitly.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated','session_id','terms-gate-admin')::text,true);
 set local role authenticated;
 perform public.publish_terms(term2);
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 set local role authenticated;
 payload:=public.current_terms_status();
 if payload->>'accepted'<>'false' or payload->'terms'->>'id'<>term2::text then raise exception 'New publication retained old acceptance';end if;
 begin perform public.accept_current_terms(term1);raise exception 'Old dialog accepted';exception when raise_exception then if sqlerrm<>'TERMS_CHANGED'then raise;end if;end;
 -- A refusal does not insert acceptance; repeating the status request remains blocked.
 if (public.current_terms_status()->>'accepted')<>'false'then raise exception 'Decline implicitly accepted';end if;
 perform public.accept_current_terms(term2);
 if (public.current_terms_status()->>'accepted')<>'true'then raise exception 'Reconsideration failed';end if;
 reset role;
 if exists(select 1 from public.terms_acceptances where user_id=other_user)then raise exception 'Other account accepted';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'role','authenticated')::text,true);
 set local role authenticated;
 if(public.current_terms_status()->>'accepted')<>'false'then raise exception 'Acceptance shared across accounts';end if;
 begin perform public.publish_terms(draft);raise exception 'Client published';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 select count(*) into n from public.terms_versions where id=draft;
 if n<>0 then raise exception 'Draft leaked';end if;
 reset role;
 update public.terms_versions set published=false where published;
 set local role authenticated;
 payload:=public.current_terms_status();
 if payload->>'accepted'<>'true' or payload->'terms'<>'null'::jsonb then raise exception 'No published terms blocked users';end if;
 reset role;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 begin perform public.current_terms_status();raise exception 'Anonymous status permitted';exception when insufficient_privilege then null;end;
 begin perform public.accept_current_terms(term2);raise exception 'Anonymous consent permitted';exception when insufficient_privilege then null;end;
 reset role;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'and schemaname='public'and tablename='terms_versions')then raise exception 'Terms realtime not enabled';end if;
end $test$;
select 'PASS all roles, publication refresh, stale dialog, refusal/reconsideration, own consent isolation, drafts and anonymous access' as result;
rollback;
