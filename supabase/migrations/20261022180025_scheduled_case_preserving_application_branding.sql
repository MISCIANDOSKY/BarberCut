create table private.branding_settings(
 id boolean primary key default true check(id),
 current_name text not null,
 pending_name text,
 activates_at timestamptz,
 version uuid not null default gen_random_uuid(),
 check((pending_name is null)=(activates_at is null))
);
insert into private.branding_settings(id,current_name)select id,shop_name from public.app_settings where id;
alter table private.branding_settings enable row level security;
revoke all on private.branding_settings from public,anon,authenticated;

create function private.effective_brand_name()
returns text language sql stable security definer set search_path='' as $$
 select case when pending_name is not null and activates_at<=statement_timestamp() then pending_name else current_name end
 from private.branding_settings where id
$$;
create function public.app_branding()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',private.effective_brand_name(),'server_time',statement_timestamp(),
 'changes_at',case when activates_at>statement_timestamp() then activates_at else null end)
 from private.branding_settings where id
$$;
create function public.public_app_settings()
returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(s)||jsonb_build_object('shop_name',private.effective_brand_name()) from public.app_settings s where id
$$;
create function private.branding_status()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 return (select jsonb_build_object('name',private.effective_brand_name(),'pending_name',case when activates_at>statement_timestamp() then pending_name else null end,
 'activates_at',case when activates_at>statement_timestamp() then activates_at else null end,'server_time',statement_timestamp()) from private.branding_settings where id);
end $$;
create function public.branding_status()
returns jsonb language sql stable security invoker set search_path='' as $$ select private.branding_status() $$;

create function private.activate_brand_name(p_version uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cfg private.branding_settings; remaining numeric;
begin
 select * into cfg from private.branding_settings where id and version=p_version;
 if not found or cfg.pending_name is null then return;end if;
 remaining:=extract(epoch from(cfg.activates_at-clock_timestamp()));
 if remaining>60 then return;end if;
 if remaining>0 then perform pg_sleep(remaining::double precision);end if;
 select * into cfg from private.branding_settings where id for update;
 if cfg.version<>p_version or cfg.pending_name is null or cfg.activates_at>clock_timestamp() then return;end if;
 update private.branding_settings set current_name=pending_name,pending_name=null,activates_at=null where id;
 update public.app_settings set shop_name=cfg.pending_name where id;
 update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('branding_name',cfg.pending_name);
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
end $$;
revoke all on function private.activate_brand_name(uuid) from public,anon,authenticated;

create function private.schedule_brand_name(p_name text)
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
 -- Start in the target minute, then wait only the remaining seconds. Never publish early.
 perform cron.schedule('barberup-brand-name-activation',
 extract(minute from due at time zone 'UTC')::text||' '||extract(hour from due at time zone 'UTC')::text||' * * *',
 format('select private.activate_brand_name(%L::uuid)',v));
 return private.branding_status();
end $$;
create function public.schedule_brand_name(p_name text)
returns jsonb language sql security invoker set search_path='' as $$ select private.schedule_brand_name(p_name) $$;

create function private.cancel_brand_name()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 perform 1 from private.branding_settings where id for update;
 if exists(select 1 from private.branding_settings where id and activates_at<=clock_timestamp())then raise exception 'BRAND_ALREADY_ACTIVE';end if;
 update private.branding_settings set pending_name=null,activates_at=null,version=gen_random_uuid() where id;
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
 return private.branding_status();
end $$;
create function public.cancel_brand_name()
returns jsonb language sql security invoker set search_path='' as $$ select private.cancel_brand_name() $$;

-- Prevent the old direct form or API from bypassing the delay.
create function private.guard_direct_brand_name()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.shop_name is distinct from old.shop_name and new.shop_name is distinct from (select current_name from private.branding_settings where id)
 then raise exception 'USE_SCHEDULED_BRAND_NAME';end if;
 return new;
end $$;
create trigger scheduled_brand_name_only before update of shop_name on public.app_settings for each row execute function private.guard_direct_brand_name();

-- Presentation-only metadata; never used for authorization.
create function private.auth_branding_metadata()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.raw_user_meta_data:=coalesce(new.raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('branding_name',private.effective_brand_name());
 return new;
end $$;
create trigger auth_branding_metadata before insert or update of raw_user_meta_data on auth.users
for each row execute function private.auth_branding_metadata();
update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('branding_name',private.effective_brand_name());

create function public.pwa_manifest()
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id','https://misciandosky.github.io/BarberUp/','name',private.effective_brand_name(),
 'short_name',private.effective_brand_name(),'description','Il tuo barbiere, a portata di mano.','lang','it',
 'start_url','https://misciandosky.github.io/BarberUp/','scope','https://misciandosky.github.io/BarberUp/',
 'display','standalone','background_color','#151815','theme_color','#151815',
 'icons',jsonb_build_array(
 jsonb_build_object('src','https://misciandosky.github.io/BarberUp/icons/icon-192.png','sizes','192x192','type','image/png','purpose','any'),
 jsonb_build_object('src','https://misciandosky.github.io/BarberUp/icons/icon-512.png','sizes','512x512','type','image/png','purpose','any'),
 jsonb_build_object('src','https://misciandosky.github.io/BarberUp/icons/maskable-512.png','sizes','512x512','type','image/png','purpose','maskable')))
$$;
revoke all on function private.effective_brand_name() from public,anon,authenticated;
revoke all on function private.guard_direct_brand_name() from public,anon,authenticated;
revoke all on function private.auth_branding_metadata() from public,anon,authenticated;
revoke all on function private.branding_status() from public,anon,authenticated;
revoke all on function public.branding_status() from public,anon,authenticated;
revoke all on function private.schedule_brand_name(text) from public,anon,authenticated;
revoke all on function public.schedule_brand_name(text) from public,anon,authenticated;
revoke all on function private.cancel_brand_name() from public,anon,authenticated;
revoke all on function public.cancel_brand_name() from public,anon,authenticated;
grant execute on function private.branding_status(),public.branding_status(),private.schedule_brand_name(text),public.schedule_brand_name(text),private.cancel_brand_name(),public.cancel_brand_name() to authenticated;
revoke all on function public.app_branding(),public.public_app_settings(),public.pwa_manifest() from public,anon,authenticated;
grant execute on function public.app_branding(),public.public_app_settings(),public.pwa_manifest() to anon,authenticated,service_role;
