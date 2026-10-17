CREATE OR REPLACE FUNCTION private.maintenance_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 return jsonb_build_object(
 'settings',(select to_jsonb(s)||jsonb_build_object('require_user_approval',(select require_user_approval from public.app_settings where id)) from private.maintenance_settings s where id),
 'last_run',(select to_jsonb(r) from private.maintenance_runs r order by id desc limit 1),
 'disabled_count',(select count(*) from private.inactive_accounts),
 'disabled_accounts',coalesce((select jsonb_agg(t) from (
 select i.user_id,i.disabled_at,p.first_name,p.last_name from private.inactive_accounts i join public.profiles p on p.id=i.user_id order by i.disabled_at desc limit 100)t),'[]'::jsonb));
end $function$
;
create function private.save_maintenance_with_registrations(p_inactive_days integer,p_appointment_days integer,p_disable_inactive boolean,p_delete_old boolean,p_require_approval boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.save_maintenance_settings(p_inactive_days,p_appointment_days,p_disable_inactive,p_delete_old);
 perform private.set_registration_policy(p_require_approval);
end $$;
create function public.save_maintenance_with_registrations(p_inactive_days integer,p_appointment_days integer,p_disable_inactive boolean,p_delete_old boolean,p_require_approval boolean) returns void language sql security invoker set search_path='' as $$select private.save_maintenance_with_registrations(p_inactive_days,p_appointment_days,p_disable_inactive,p_delete_old,p_require_approval)$$;
revoke all on function private.save_maintenance_with_registrations(integer,integer,boolean,boolean,boolean),public.save_maintenance_with_registrations(integer,integer,boolean,boolean,boolean) from public,anon;
grant execute on function private.save_maintenance_with_registrations(integer,integer,boolean,boolean,boolean),public.save_maintenance_with_registrations(integer,integer,boolean,boolean,boolean) to authenticated;
