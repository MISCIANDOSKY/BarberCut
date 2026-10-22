create or replace function private.schedule_brand_name(p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare chosen text:=btrim(p_name); due timestamptz; v uuid:=gen_random_uuid(); cfg private.branding_settings;
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 if chosen is null or char_length(chosen)<1 or char_length(chosen)>60 or chosen~'[[:cntrl:]<>]' then raise exception 'INVALID_BRAND_NAME';end if;
 select * into cfg from private.branding_settings where id for update;
 -- Settle any due change before scheduling the next one.
 if cfg.pending_name is not null and cfg.activates_at<=clock_timestamp() then
  update private.branding_settings set current_name=pending_name,pending_name=null,activates_at=null where id returning * into cfg;
  update public.app_settings set shop_name=cfg.current_name where id;
 end if;
 if chosen=cfg.current_name then raise exception 'BRAND_NAME_UNCHANGED';end if;
 due:=clock_timestamp()+interval '15 minutes';
 update private.branding_settings set pending_name=chosen,activates_at=due,version=v where id;
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
 -- Retry once per minute; only wait in the final minute, never publish early.
 perform cron.schedule('barberup-brand-name-activation',
 '* * * * *',
 format('select private.activate_brand_name(%L::uuid)',v));
 return private.branding_status();
end $$;

create or replace function public.pwa_manifest()
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
end $$;
