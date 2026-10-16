
begin;
do $test$
declare u uuid:=gen_random_uuid(); b uuid; s uuid; a uuid; n int;
begin
insert into auth.users(id,email,raw_user_meta_data) values(u,'deletion-test@example.invalid','{"first_name":"Test","last_name":"Deletion","phone":"000"}');
insert into public.barbers(name) values('TEST deletion') returning id into b;
insert into public.services(name,duration_minutes,price) values('TEST deletion',15,1) returning id into s;
insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,created_by,notes) values(b,'appointment',u,s,now()+interval '5 days',now()+interval '5 days 15 minutes',u,'test private note') returning id into a;
update public.app_settings set account_deletion_enabled=true;
perform public.prepare_account_deletion(u);
if not exists(select 1 from public.calendar_entries where id=a and client_id is null and notes='' and status='cancelled' and anonymized_at is not null) then raise exception 'anonymization failed';end if;
delete from auth.users where id=u;
if exists(select 1 from public.profiles where id=u) then raise exception 'profile not removed';end if;
if not exists(select 1 from public.calendar_entries where id=a and created_by is null) then raise exception 'history not retained';end if;
end $test$;
select 'PASS: verified-deletion preparation cancels future booking, removes identifiers, preserves anonymized history and permits Auth/profile cascade' as result;
rollback;