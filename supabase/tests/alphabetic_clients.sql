begin;
update public.app_settings set require_user_approval=true where id;
do $test$
declare ad uuid:=gen_random_uuid();worker uuid:=gen_random_uuid();lead uuid:=gen_random_uuid();viewer uuid:=gen_random_uuid();ordinary uuid:=gen_random_uuid();
 b uuid;bl uuid;u uuid;ids uuid[]:='{}';e uuid;a uuid;z uuid;symbol uuid;xs jsonb;ys jsonb;sample jsonb;n integer;total integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)values
 (ad,'clients-admin@example.invalid',now(),'{}'),(worker,'clients-barber@example.invalid',now(),'{}'),
 (lead,'clients-lead@example.invalid',now(),'{}'),(viewer,'clients-shop@example.invalid',now(),'{}'),
 (ordinary,'clients-ordinary@example.invalid',now(),'{}');
 update public.user_roles set role='admin'where user_id=ad;
 update public.user_roles set role='shop'where user_id=viewer;
 insert into public.barbers(name,user_id)values('Clients barber',worker)returning id into b;
 insert into public.barbers(name,user_id)values('Clients lead',lead)returning id into bl;
 update public.user_roles set role='barber_admin'where user_id=lead;
 update public.barbers set can_approve_clients=true where id in(b,bl);
 for n in 1..205 loop
  u:=gen_random_uuid();ids:=array_append(ids,u);
  insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)values(u,'client-list-'||n||'@example.invalid',now(),jsonb_build_object('first_name','AAAA_TEST_'||lpad(n::text,4,'0'),'last_name','Test','phone','000'));
  update private.client_memberships set status=case n%3 when 0 then 'pending'when 1 then 'approved'else 'rejected'end where user_id=u;
 end loop;
 a:=gen_random_uuid();e:=gen_random_uuid();z:=gen_random_uuid();symbol:=gen_random_uuid();
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)values
 (a,'client-list-alice@example.invalid',now(),'{"first_name":"Alice","last_name":"Test"}'),
 (e,'client-list-emile@example.invalid',now(),'{"first_name":"Émile","last_name":"Test"}'),
 (z,'client-list-zeta@example.invalid',now(),'{"first_name":"Zeta","last_name":"Test"}'),
 (symbol,'client-list-symbol@example.invalid',now(),'{"first_name":"123","last_name":"Test"}');
 ids:=ids||array[a,e,z,symbol];
 perform public.staff_authorize_session(ad,'client-list-admin');
 perform public.staff_authorize_session(worker,'client-list-barber');
 perform public.staff_authorize_session(lead,'client-list-lead');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','client-list-barber')::text,true);
 set local role authenticated;
 xs:=public.list_clients('all',0,null);ys:=public.list_clients('all',200,null);
 if jsonb_array_length(xs->'items')<>200 or not (xs->>'has_more')::boolean then raise exception 'First page incorrect';end if;
 select count(distinct x->>'user_id') into total from jsonb_array_elements((xs->'items')||(ys->'items'))x where (x->>'user_id')::uuid=any(ids);
 if total<>209 then raise exception 'All clients missing across statuses/pages %',total;end if;
 if exists(select 1 from jsonb_array_elements(xs->'items')x join jsonb_array_elements(ys->'items')y on x->>'user_id'=y->>'user_id')then raise exception 'Duplicate page records';end if;
 if exists(select 1 from jsonb_array_elements((xs->'items')||(ys->'items'))x where (x->>'user_id')::uuid in(ad,worker,lead,viewer))then raise exception 'Non-client exposed';end if;
 if (xs->'items'->0->>'first_name')<>'AAAA_TEST_0001' or (xs->'items'->1->>'first_name')<>'AAAA_TEST_0002' then raise exception 'Alphabetic order incorrect';end if;
 if not ((xs->'letters')?'A'and(xs->'letters')?'E'and(xs->'letters')?'Z'and(xs->'letters')?'#')then raise exception 'Letter index incomplete';end if;
 sample:=public.list_clients('all',0,'E');
 if exists(select 1 from jsonb_array_elements(sample->'items')x where x->>'letter' in('A','B','C','D'))then raise exception 'Letter jump includes earlier records';end if;
 if not exists(select 1 from jsonb_array_elements(sample->'items')x where x->>'user_id'=e::text and x->>'letter'='E')then raise exception 'Accented name not indexed';end if;
 for n in 1..3 loop
  sample:=public.list_clients(case n when 1 then 'pending'when 2 then 'approved'else 'rejected'end,0,null);
  if exists(select 1 from jsonb_array_elements(sample->'items')x where x->>'status'<>case n when 1 then 'pending'when 2 then 'approved'else 'rejected'end)then raise exception 'Status filtering failed';end if;
 end loop;
 begin perform public.list_clients('wrong',0,null);raise exception 'Invalid filter accepted';exception when raise_exception then if sqlerrm<>'INVALID_STATUS'then raise;end if;end;
 begin perform public.list_clients('all',-1,null);raise exception 'Invalid page accepted';exception when raise_exception then if sqlerrm<>'INVALID_STATUS'then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',lead,'role','authenticated','session_id','client-list-lead')::text,true);
 set local role authenticated;perform public.list_clients('all',0,'Z');reset role;
 update public.barbers set can_approve_clients=false where id=b;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',worker,'role','authenticated','session_id','client-list-barber')::text,true);
 set local role authenticated;
 begin perform public.list_clients('all');raise exception 'Revoked barber lists clients';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ordinary,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.list_clients('all');raise exception 'Client lists users';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.list_clients('all');raise exception 'Shop lists users';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','client-list-admin')::text,true);
 set local role authenticated;perform public.list_clients('all',0,null);reset role;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);set local role anon;
 begin perform public.list_clients('all');raise exception 'Anon lists users';exception when insufficient_privilege then null;end;reset role;
end $test$;
select 'PASS all statuses, 209 alphabetized clients over multiple pages, A-Z/# jumps and accents, existing review permissions and isolation' result;
rollback;