create or replace function private.admin_service_barbers(p_service uuid)
returns table(barber_id uuid,barber_name text,enabled boolean,personally_active boolean)
language plpgsql stable security definer set search_path='' as $function$
declare service_active boolean;
begin
 if not coalesce(private.has_role('admin'),false)then raise exception 'ACCESS_DENIED';end if;
 select s.active into service_active from public.services s where s.id=p_service and s.deleted_at is null;
 if not found then raise exception 'ACCESS_DENIED';end if;
 return query select b.id,b.name,service_active and coalesce(bs.staff_enabled,false),coalesce(bs.active,false)
 from public.barbers b join public.user_roles r on r.user_id=b.user_id
 left join public.barber_services bs on bs.barber_id=b.id and bs.service_id=p_service
 where b.active and b.deleted_at is null and r.role in('barber','barber_admin','admin')
 order by b.name,b.id;
end $function$;
create or replace function public.admin_service_barbers(p_service uuid)
returns table(barber_id uuid,barber_name text,enabled boolean,personally_active boolean)
language sql set search_path='' as $function$select * from private.admin_service_barbers(p_service)$function$;

create or replace function private.admin_set_service_barber(p_service uuid,p_barber uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $function$
declare service_active boolean;
begin
 if not coalesce(private.has_role('admin'),false)then raise exception 'ACCESS_DENIED';end if;
 if p_enabled is null then raise exception 'INVALID_SERVICE';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
 select s.active into service_active from public.services s where s.id=p_service and s.deleted_at is null for update;
 if not found or not exists(select 1 from public.barbers b join public.user_roles r on r.user_id=b.user_id
 where b.id=p_barber and b.active and b.deleted_at is null and r.role in('barber','barber_admin','admin'))
 then raise exception 'ACCESS_DENIED';end if;
 if p_enabled and not service_active then
  -- Reopening a legacy globally-disabled service must not reopen every old assignment.
  update public.barber_services set active=false,staff_enabled=false where service_id=p_service;
  update public.services set active=true where id=p_service;
 end if;
 insert into public.barber_services(barber_id,service_id,active,staff_enabled)
 values(p_barber,p_service,p_enabled,p_enabled)
 on conflict(barber_id,service_id)do update set active=excluded.active,staff_enabled=excluded.staff_enabled;
end $function$;
create or replace function public.admin_set_service_barber(p_service uuid,p_barber uuid,p_enabled boolean)
returns void language sql set search_path='' as $function$select private.admin_set_service_barber(p_service,p_barber,p_enabled)$function$;

revoke all on function private.admin_service_barbers(uuid),public.admin_service_barbers(uuid),
 private.admin_set_service_barber(uuid,uuid,boolean),public.admin_set_service_barber(uuid,uuid,boolean) from public,anon;
grant execute on function private.admin_service_barbers(uuid),public.admin_service_barbers(uuid),
 private.admin_set_service_barber(uuid,uuid,boolean),public.admin_set_service_barber(uuid,uuid,boolean) to authenticated;
