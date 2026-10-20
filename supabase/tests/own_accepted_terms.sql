begin;
do $test$
declare customer uuid:=gen_random_uuid(); other_customer uuid:=gen_random_uuid(); accepted uuid:=gen_random_uuid(); other_accepted uuid:=gen_random_uuid(); draft uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,raw_user_meta_data) values(customer,customer::text||'@terms.invalid','{}'),(other_customer,other_customer::text||'@terms.invalid','{}');
 insert into public.terms_versions(version,body,published) values('test-own-'||accepted::text,'Test accepted terms',false) returning id into accepted;
 insert into public.terms_versions(version,body,published) values('test-other-'||other_accepted::text,'Other accepted terms',false) returning id into other_accepted;
 insert into public.terms_versions(version,body,published) values('test-draft-'||draft::text,'Private draft',false) returning id into draft;
 insert into public.terms_acceptances(user_id,terms_id) values(customer,accepted),(other_customer,other_accepted);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',customer,'role','authenticated')::text,true);
 set local role authenticated;
 if not exists(select 1 from public.terms_versions where id=accepted) then raise exception 'Own accepted terms hidden';end if;
 if exists(select 1 from public.terms_versions where id in(other_accepted,draft)) then raise exception 'Unaccepted unpublished terms visible';end if;
 if exists(select 1 from public.terms_acceptances where user_id=other_customer) then raise exception 'Other acceptance visible';end if;
 begin insert into public.terms_acceptances(user_id,terms_id) values(customer,draft);raise exception 'Unpublished terms accepted';exception when insufficient_privilege then null;end;
 reset role;
 perform set_config('request.jwt.claims','{}',true);
 set local role anon;
 if exists(select 1 from public.terms_versions where id=accepted) then raise exception 'Anonymous history visible';end if;
 reset role;
end $test$;
select 'own_accepted_terms_test_passed' as result;
rollback;
