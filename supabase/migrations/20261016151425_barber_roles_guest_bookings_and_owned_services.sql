
-- Manual guest bookings remain appointments, without creating Auth users or a client directory.
alter table public.calendar_entries add column guest_first_name text not null default '', add column guest_last_name text not null default '', add column guest_phone text not null default '';
alter table public.calendar_entries drop constraint appointment_client_required;
alter table public.calendar_entries add constraint appointment_client_required check(kind='block' or(service_id is not null and(client_id is not null or anonymized_at is not null or(length(trim(guest_first_name))>0 and length(trim(guest_last_name))>0))));
alter table public.services add column deleted_at timestamptz;
alter table public.barbers add column deleted_at timestamptz;

create or replace function private.can_manage(b uuid) returns boolean language sql stable security definer set search_path='' as $$
select private.has_role('admin') or(private.has_role('barber') and exists(select 1 from public.barbers where id=b and user_id=auth.uid() and active and deleted_at is null))
$$;
create function private.assign_barber_role() returns trigger language plpgsql security definer set search_path='' as $$
begin
if new.user_id is not null and new.active and new.deleted_at is null then
insert into public.user_roles(user_id,role) values(new.user_id,'barber') on conflict(user_id) do update set role='barber' where public.user_roles.role<>'admin';
end if;
return new;end $$;
revoke all on function private.assign_barber_role() from public,anon,authenticated;
create trigger assign_linked_barber_role after insert or update of user_id,active on public.barbers for each row execute function private.assign_barber_role();
insert into public.user_roles(user_id,role) select user_id,'barber' from public.barbers where user_id is not null and active on conflict(user_id) do update set role='barber' where public.user_roles.role<>'admin';
alter policy public_services on public.services using(active and deleted_at is null);
alter policy public_barbers on public.barbers using(active and deleted_at is null);
create policy own_associated_services on public.services for select to authenticated using(deleted_at is null and exists(select 1 from public.barber_services bs where bs.service_id=services.id and private.can_manage(bs.barber_id)));

create function private.book_guest_appointment(p_barber uuid,p_service uuid,p_start timestamptz,p_first_name text,p_last_name text,p_phone text default '') returns uuid language plpgsql security definer set search_path='' as $$
declare svc public.services; result uuid;
begin
if not private.can_manage(p_barber) then raise exception 'ACCESS_DENIED';end if;
if p_first_name is null or p_last_name is null or length(trim(p_first_name)) not between 1 and 120 or length(trim(p_last_name)) not between 1 and 120 or length(coalesce(p_phone,''))>40 then raise exception 'GUEST_NAME_REQUIRED';end if;
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
select * into strict svc from public.services where id=p_service and deleted_at is null for share;
if not exists(select 1 from public.get_available_slots(p_barber,p_service,(p_start at time zone 'Europe/Rome')::date) a where a.start_at=p_start) then raise exception 'SLOT_TAKEN';end if;
insert into public.calendar_entries(barber_id,kind,service_id,start_at,end_at,service_name,price,created_by,guest_first_name,guest_last_name,guest_phone) values(p_barber,'appointment',p_service,p_start,p_start+make_interval(mins=>svc.duration_minutes),svc.name,svc.price,auth.uid(),trim(p_first_name),trim(p_last_name),trim(coalesce(p_phone,''))) returning id into result;
return result;end $$;
create function public.book_guest_appointment(p_barber uuid,p_service uuid,p_start timestamptz,p_first_name text,p_last_name text,p_phone text default '') returns uuid language sql security invoker set search_path='' as $$select private.book_guest_appointment(p_barber,p_service,p_start,p_first_name,p_last_name,p_phone)$$;
revoke all on function private.book_guest_appointment(uuid,uuid,timestamptz,text,text,text),public.book_guest_appointment(uuid,uuid,timestamptz,text,text,text) from public,anon;
grant execute on function private.book_guest_appointment(uuid,uuid,timestamptz,text,text,text),public.book_guest_appointment(uuid,uuid,timestamptz,text,text,text) to authenticated;

create function private.save_barber_service(p_barber uuid,p_service uuid,p_name text,p_description text,p_duration int,p_price numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare saved uuid;shared boolean; previous_flag text;
begin
if not private.can_manage(p_barber) then raise exception 'ACCESS_DENIED';end if;
if p_name is null or length(trim(p_name)) not between 1 and 160 or p_duration is null or p_duration<15 or p_duration>480 or p_duration%15<>0 or p_price is null or p_price<0 or p_price>999999.99 then raise exception 'INVALID_SERVICE';end if;
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
if p_service is null then
insert into public.services(name,description,duration_minutes,price) values(trim(p_name),coalesce(p_description,''),p_duration,p_price) returning id into saved;
insert into public.barber_services(barber_id,service_id) values(p_barber,saved);
else
perform 1 from public.services where id=p_service and deleted_at is null for update;
if not found or not exists(select 1 from public.barber_services where barber_id=p_barber and service_id=p_service) then raise exception 'ACCESS_DENIED';end if;
select exists(select 1 from public.barber_services where service_id=p_service and barber_id<>p_barber) into shared;
if shared then
insert into public.services(name,description,duration_minutes,price) values(trim(p_name),coalesce(p_description,''),p_duration,p_price) returning id into saved;
insert into public.barber_services(barber_id,service_id) values(p_barber,saved);
delete from public.barber_services where barber_id=p_barber and service_id=p_service;
previous_flag:=current_setting('barbercut.internal_reschedule',true);
perform set_config('barbercut.internal_reschedule','1',true);
update public.calendar_entries set service_id=saved where barber_id=p_barber and service_id=p_service;
perform set_config('barbercut.internal_reschedule',coalesce(previous_flag,'0'),true);
else
update public.services set name=trim(p_name),description=coalesce(p_description,''),duration_minutes=p_duration,price=p_price where id=p_service;
saved:=p_service;
end if;
end if;return saved;end $$;
create function public.save_barber_service(p_barber uuid,p_service uuid,p_name text,p_description text,p_duration int,p_price numeric) returns uuid language sql security invoker set search_path='' as $$select private.save_barber_service(p_barber,p_service,p_name,p_description,p_duration,p_price)$$;
create function private.remove_barber_service(p_barber uuid,p_service uuid) returns void language plpgsql security definer set search_path='' as $$
begin
if not private.can_manage(p_barber) then raise exception 'ACCESS_DENIED';end if;
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
perform 1 from public.services where id=p_service for update;
if not exists(select 1 from public.barber_services where barber_id=p_barber and service_id=p_service) then raise exception 'ACCESS_DENIED';end if;
delete from public.barber_services where barber_id=p_barber and service_id=p_service;
if not exists(select 1 from public.barber_services where service_id=p_service) then update public.services set active=false,deleted_at=now() where id=p_service;end if;
end $$;
create function public.remove_barber_service(p_barber uuid,p_service uuid) returns void language sql security invoker set search_path='' as $$select private.remove_barber_service(p_barber,p_service)$$;
revoke all on function private.save_barber_service(uuid,uuid,text,text,int,numeric),public.save_barber_service(uuid,uuid,text,text,int,numeric),private.remove_barber_service(uuid,uuid),public.remove_barber_service(uuid,uuid) from public,anon;
grant execute on function private.save_barber_service(uuid,uuid,text,text,int,numeric),public.save_barber_service(uuid,uuid,text,text,int,numeric),private.remove_barber_service(uuid,uuid),public.remove_barber_service(uuid,uuid) to authenticated;

create function private.admin_delete_resource(p_kind text,p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
if not private.has_role('admin') then raise exception 'ACCESS_DENIED';end if;
if p_kind='barber' then
perform pg_advisory_xact_lock(hashtextextended(p_id::text,2));
if exists(select 1 from public.calendar_entries where barber_id=p_id and kind='appointment' and status='confirmed' and end_at>now()) then raise exception 'BARBER_HAS_APPOINTMENTS';end if;
update public.barbers set active=false,deleted_at=now() where id=p_id;
elsif p_kind='service' then
perform 1 from public.services where id=p_id for update;
delete from public.barber_services where service_id=p_id;
update public.services set active=false,deleted_at=now() where id=p_id;
else raise exception 'INVALID_RESOURCE';end if;
end $$;
create function public.admin_delete_resource(p_kind text,p_id uuid) returns void language sql security invoker set search_path='' as $$select private.admin_delete_resource(p_kind,p_id)$$;
revoke all on function private.admin_delete_resource(text,uuid),public.admin_delete_resource(text,uuid) from public,anon;
grant execute on function private.admin_delete_resource(text,uuid),public.admin_delete_resource(text,uuid) to authenticated;
CREATE OR REPLACE FUNCTION private.notify_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare recipient uuid;
begin
if current_setting('barbercut.internal_reschedule',true)='1' then return new;end if;
if new.kind='appointment' then
if new.client_id is not null and tg_op='UPDATE' and (new.start_at is distinct from old.start_at or new.status is distinct from old.status) then
insert into public.notifications(user_id,title,body) values(new.client_id,case when new.status='cancelled' then 'Appuntamento cancellato' else 'Appuntamento aggiornato' end,coalesce(new.service_name,'Appuntamento')||' · '||to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));
end if;
select user_id into recipient from public.barbers where id=new.barber_id;
if recipient is not null then insert into public.notifications(user_id,title,body) values(recipient,'Aggiornamento agenda',coalesce(new.service_name,'Appuntamento')||' · '||to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));end if;
end if;return new;end $function$
;
CREATE OR REPLACE FUNCTION private.appointment_reminders()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
insert into public.notifications(user_id,title,body,event_key)
select e.client_id,case when e.start_at<=now()+interval '1 hour' then 'Promemoria appuntamento' else 'Il tuo appuntamento è domani' end,
e.service_name||' · '||to_char(e.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'),
e.id::text||case when e.start_at<=now()+interval '1 hour' then ':1h:' else ':24h:' end||extract(epoch from e.start_at)::text
from public.calendar_entries e
where e.client_id is not null and e.kind='appointment' and e.status='confirmed' and e.start_at>now() and(e.start_at<=now()+interval '1 hour' or e.start_at between now()+interval '23 hours' and now()+interval '24 hours')
on conflict(event_key) do nothing
$function$
;
CREATE OR REPLACE FUNCTION private.reschedule_appointment(p_id uuid, p_start timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e public.calendar_entries; svc public.services;
begin
select * into strict e from public.calendar_entries where id=p_id;
if not private.can_manage(e.barber_id) or e.kind<>'appointment' then raise exception 'ACCESS_DENIED';end if;
perform pg_advisory_xact_lock(hashtextextended(coalesce(e.client_id::text,'guest:'||e.id::text),1));
perform pg_advisory_xact_lock(hashtextextended(e.barber_id::text,2));
select * into strict e from public.calendar_entries where id=p_id for update;
select * into strict svc from public.services where id=e.service_id and deleted_at is null for share;
perform set_config('barbercut.internal_reschedule','1',true);
update public.calendar_entries set status='cancelled' where id=p_id;
if not exists(select 1 from public.get_available_slots(e.barber_id,e.service_id,(p_start at time zone 'Europe/Rome')::date) where start_at=p_start) then raise exception 'SLOT_TAKEN';end if;
perform set_config('barbercut.internal_reschedule','0',true);
update public.calendar_entries set start_at=p_start,end_at=p_start+make_interval(mins=>svc.duration_minutes),status='confirmed',updated_at=now() where id=p_id;
end $function$
;
CREATE OR REPLACE FUNCTION private.book_appointment(p_barber uuid, p_service uuid, p_start timestamp with time zone, p_client uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c uuid:=coalesce(p_client,auth.uid()); svc public.services; result uuid; staff boolean:=private.can_manage(p_barber);
begin
if auth.uid() is null or(c<>auth.uid() and not staff) then raise exception 'ACCESS_DENIED'; end if;
if not staff and not (select bookings_enabled from public.app_settings where id) then raise exception 'BOOKINGS_DISABLED'; end if;
perform pg_advisory_xact_lock(hashtextextended(c::text,1));
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
if not exists(select 1 from public.profiles where id=c and deletion_requested_at is null and length(trim(first_name))>0 and length(trim(last_name))>0 and length(trim(phone))>0) then raise exception 'PROFILE_REQUIRED'; end if;
if exists(select 1 from public.terms_versions where published) and not exists(select 1 from public.terms_acceptances a join public.terms_versions t on t.id=a.terms_id where a.user_id=c and t.published) then raise exception 'TERMS_REQUIRED'; end if;
if(select count(*) from public.calendar_entries where client_id=c and kind='appointment' and status='confirmed' and start_at>now())>=5 then raise exception 'LIMIT_FIVE'; end if;
select * into strict svc from public.services where id=p_service and deleted_at is null for share;
if not exists(select 1 from public.get_available_slots(p_barber,p_service,(p_start at time zone 'Europe/Rome')::date) a where a.start_at=p_start) then raise exception 'SLOT_TAKEN'; end if;
insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by) values(p_barber,'appointment',c,p_service,p_start,p_start+make_interval(mins=>svc.duration_minutes),svc.name,svc.price,auth.uid()) returning id into result;
return result;
end $function$
;
