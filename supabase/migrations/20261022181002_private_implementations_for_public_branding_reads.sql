CREATE OR REPLACE FUNCTION private.app_branding()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object('name',private.effective_brand_name(),'server_time',statement_timestamp(),
 'changes_at',case when activates_at>statement_timestamp() then activates_at else null end)
 from private.branding_settings where id
$function$;
CREATE OR REPLACE FUNCTION private.public_app_settings()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select to_jsonb(s)||jsonb_build_object('shop_name',private.effective_brand_name()) from public.app_settings s where id
$function$;
CREATE OR REPLACE FUNCTION private.pwa_manifest()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform set_config('response.headers','[{"Cache-Control":"no-store, max-age=0"}]',true);
 return (select jsonb_build_object('id','https://misciandosky.github.io/BarberUp/','name',private.effective_brand_name(),
 'short_name',private.effective_brand_name(),'description','Il tuo barbiere, a portata di mano.','lang','it',
 'start_url','https://misciandosky.github.io/BarberUp/','scope','https://misciandosky.github.io/BarberUp/',
 'display','standalone','background_color','#151815','theme_color','#151815',
 'icons',jsonb_build_array(
 jsonb_build_object('src','https://misciandosky.github.io/BarberUp/icons/icon-192.png','sizes','192x192','type','image/png','purpose','any'),
 jsonb_build_object('src','https://misciandosky.github.io/BarberUp/icons/icon-512.png','sizes','512x512','type','image/png','purpose','any'),
 jsonb_build_object('src','https://misciandosky.github.io/BarberUp/icons/maskable-512.png','sizes','512x512','type','image/png','purpose','maskable'))));
end $function$;
create or replace function public.app_branding()
returns jsonb language sql stable security invoker set search_path='' as $brand$
 select private.app_branding()
$brand$;
revoke all on function private.app_branding() from public,anon,authenticated;
grant execute on function private.app_branding() to anon,authenticated,service_role;

create or replace function public.public_app_settings()
returns jsonb language sql stable security invoker set search_path='' as $brand$
 select private.public_app_settings()
$brand$;
revoke all on function private.public_app_settings() from public,anon,authenticated;
grant execute on function private.public_app_settings() to anon,authenticated,service_role;

create or replace function public.pwa_manifest()
returns jsonb language sql stable security invoker set search_path='' as $brand$
 select private.pwa_manifest()
$brand$;
revoke all on function private.pwa_manifest() from public,anon,authenticated;
grant execute on function private.pwa_manifest() to anon,authenticated,service_role;
