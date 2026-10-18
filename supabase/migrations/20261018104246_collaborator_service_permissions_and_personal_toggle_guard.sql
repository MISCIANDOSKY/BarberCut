-- Separate a collaborator's permission from their personal service switch.
alter table public.barber_services add column staff_enabled boolean not null default true;
alter table public.barber_services add constraint barber_services_staff_enabled_check check (staff_enabled or not active);

create or replace function private.set_barber_service_active(p_barber uuid,p_service uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $fn$
declare service_active boolean; permitted boolean;
begin
 if not coalesce(private.can_manage(p_barber),false) then raise exception 'ACCESS_DENIED';end if;
 if p_active is null then raise exception 'INVALID_SERVICE';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
 select active into service_active from public.services where id=p_service and deleted_at is null for share;
 if not found then raise exception 'ACCESS_DENIED';end if;
 select staff_enabled into permitted from public.barber_services where barber_id=p_barber and service_id=p_service for update;
 if not found then raise exception 'ACCESS_DENIED';end if;
 if p_active and (not service_active or not permitted) then raise exception 'SERVICE_REACTIVATION_BLOCKED';end if;
 update public.barber_services set active=p_active where barber_id=p_barber and service_id=p_service;
end
$fn$;

create function private.service_collaborators(p_source uuid,p_service uuid)
returns table(barber_id uuid,barber_name text,enabled boolean,personally_active boolean)
language plpgsql stable security definer set search_path='' as $fn$
begin
 if not coalesce(private.can_manage_services(p_source),false)
    or not exists(select 1 from public.barber_services bs join public.services s on s.id=bs.service_id where bs.barber_id=p_source and s.id=p_service and s.deleted_at is null)
 then raise exception 'ACCESS_DENIED';end if;
 return query select b.id,b.name,coalesce(bs.staff_enabled,false),coalesce(bs.active,false)
 from public.barbers b left join public.barber_services bs on bs.barber_id=b.id and bs.service_id=p_service
 where b.id<>p_source and b.active and b.deleted_at is null order by b.name,b.id;
end
$fn$;
create function public.service_collaborators(p_source uuid,p_service uuid)
returns table(barber_id uuid,barber_name text,enabled boolean,personally_active boolean)
language sql security invoker set search_path='' as $fn$
 select * from private.service_collaborators(p_source,p_service)
$fn$;

create function private.set_collaborator_service(p_source uuid,p_service uuid,p_barber uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $fn$
begin
 if not coalesce(private.can_manage_services(p_source),false) or p_barber is null or p_source=p_barber then raise exception 'ACCESS_DENIED';end if;
 if p_enabled is null then raise exception 'INVALID_SERVICE';end if;
 -- Use the same agenda lock as booking and personal toggles.
 perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
 perform 1 from public.services s where s.id=p_service and s.deleted_at is null for share;
 if not found or not exists(select 1 from public.barber_services where barber_id=p_source and service_id=p_service)
    or not exists(select 1 from public.barbers where id=p_barber and active and deleted_at is null)
 then raise exception 'ACCESS_DENIED';end if;
 insert into public.barber_services(barber_id,service_id,active,staff_enabled)
 values(p_barber,p_service,p_enabled,p_enabled)
 on conflict(barber_id,service_id) do update set active=excluded.active,staff_enabled=excluded.staff_enabled;
end
$fn$;
create function public.set_collaborator_service(p_source uuid,p_service uuid,p_barber uuid,p_enabled boolean)
returns void language sql security invoker set search_path='' as $fn$
 select private.set_collaborator_service(p_source,p_service,p_barber,p_enabled)
$fn$;

revoke all on function private.service_collaborators(uuid,uuid),public.service_collaborators(uuid,uuid),private.set_collaborator_service(uuid,uuid,uuid,boolean),public.set_collaborator_service(uuid,uuid,uuid,boolean) from public,anon;
grant execute on function private.service_collaborators(uuid,uuid),public.service_collaborators(uuid,uuid),private.set_collaborator_service(uuid,uuid,uuid,boolean),public.set_collaborator_service(uuid,uuid,uuid,boolean) to authenticated;
CREATE OR REPLACE FUNCTION private.save_barber_service(p_barber uuid, p_service uuid, p_name text, p_description text, p_duration integer, p_price numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare saved uuid;shared boolean; previous_flag text;
begin
if not private.can_manage_services(p_barber) then raise exception 'ACCESS_DENIED';end if;
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
insert into public.barber_services(barber_id,service_id,active,staff_enabled) select p_barber,saved,bs.active,bs.staff_enabled from public.barber_services bs where bs.barber_id=p_barber and bs.service_id=p_service;
delete from public.barber_services where barber_id=p_barber and service_id=p_service;
previous_flag:=current_setting('barbercut.internal_reschedule',true);
perform set_config('barbercut.internal_reschedule','1',true);
update public.calendar_entries set service_id=saved where barber_id=p_barber and service_id=p_service;
perform set_config('barbercut.internal_reschedule',coalesce(previous_flag,'0'),true);
else
update public.services set name=trim(p_name),description=coalesce(p_description,''),duration_minutes=p_duration,price=p_price where id=p_service;
saved:=p_service;
end if;
end if;return saved;end $function$
;
notify pgrst,'reload schema';
