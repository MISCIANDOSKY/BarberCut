alter table public.profiles add column deletion_requested_at timestamptz;
revoke update on public.profiles from authenticated;
grant update(first_name,last_name,phone) on public.profiles to authenticated;
create policy service_only on private.staff_sessions for all to service_role using(true) with check(true);
create or replace function private.book_appointment(p_barber uuid,p_service uuid,p_start timestamptz,p_client uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare c uuid:=coalesce(p_client,auth.uid()); svc public.services; result uuid; staff boolean:=private.can_manage(p_barber);
begin
if auth.uid() is null or(c<>auth.uid() and not staff) then raise exception 'ACCESS_DENIED'; end if;
if not staff and not (select bookings_enabled from public.app_settings where id) then raise exception 'BOOKINGS_DISABLED'; end if;
perform pg_advisory_xact_lock(hashtextextended(c::text,1));
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
if not exists(select 1 from public.profiles where id=c and deletion_requested_at is null and length(trim(first_name))>0 and length(trim(last_name))>0 and length(trim(phone))>0) then raise exception 'PROFILE_REQUIRED'; end if;
if exists(select 1 from public.terms_versions where published) and not exists(select 1 from public.terms_acceptances a join public.terms_versions t on t.id=a.terms_id where a.user_id=c and t.published) then raise exception 'TERMS_REQUIRED'; end if;
if(select count(*) from public.calendar_entries where client_id=c and kind='appointment' and status='confirmed' and start_at>now())>=5 then raise exception 'LIMIT_FIVE'; end if;
if not exists(select 1 from public.get_available_slots(p_barber,p_service,(p_start at time zone 'Europe/Rome')::date) a where a.start_at=p_start) then raise exception 'SLOT_TAKEN'; end if;
select * into strict svc from public.services where id=p_service;
insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by) values(p_barber,'appointment',c,p_service,p_start,p_start+make_interval(mins=>svc.duration_minutes),svc.name,svc.price,auth.uid()) returning id into result;
return result;
end $$;
create or replace function public.prepare_account_deletion(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
if not(select account_deletion_enabled from public.app_settings where id) then raise exception 'DELETION_NOT_CONFIGURED';end if;
perform pg_advisory_xact_lock(7348622);
if exists(select 1 from public.user_roles where user_id=p_user and role='admin') and(select count(*) from public.user_roles where role='admin')<=1 then raise exception 'LAST_ADMIN';end if;
perform pg_advisory_xact_lock(hashtextextended(p_user::text,1));
update public.profiles set deletion_requested_at=now() where id=p_user;
update public.calendar_entries set status='cancelled',updated_at=now() where status='confirmed' and start_at>now() and(client_id=p_user or barber_id in(select id from public.barbers where user_id=p_user));
update public.calendar_entries set client_id=null,notes='',anonymized_at=now() where client_id=p_user;
update public.barbers set active=false,name='Barbiere disattivato' where user_id=p_user;
end $$;
