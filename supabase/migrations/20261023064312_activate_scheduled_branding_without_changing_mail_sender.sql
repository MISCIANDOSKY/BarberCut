-- The sender stays unchanged: no Management API credential or HTTP dispatch.
create or replace function private.activate_brand_name(p_version uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cfg private.branding_settings;remaining numeric;
begin
 select * into cfg from private.branding_settings where id and version=p_version;
 if not found or cfg.pending_name is null then return;end if;
 remaining:=extract(epoch from(cfg.activates_at-clock_timestamp()));
 if remaining>60 then return;end if;
 if remaining>0 then perform pg_sleep(remaining::double precision);end if;
 select * into cfg from private.branding_settings where id for update;
 if cfg.version<>p_version or cfg.pending_name is null or cfg.activates_at>clock_timestamp()then return;end if;
 update private.branding_settings set current_name=pending_name,pending_name=null,activates_at=null where id;
 update public.app_settings set shop_name=cfg.pending_name where id;
 update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('branding_name',cfg.pending_name);
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
end $$;
create or replace function private.branding_status()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false)then raise exception 'ACCESS_DENIED';end if;
 return(select jsonb_build_object('name',current_name,'pending_name',pending_name,'activates_at',activates_at,
 'server_time',statement_timestamp(),'setup_required',false)
 from private.branding_settings where id);
end $$;
create or replace function private.schedule_brand_name(p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare chosen text:=btrim(p_name); due timestamptz;v uuid:=gen_random_uuid();
begin
 if not coalesce(private.has_role('admin'),false)then raise exception 'ACCESS_DENIED';end if;
 if chosen is null or char_length(chosen)<1 or char_length(chosen)>60 or chosen~'[[:cntrl:]<>]'then raise exception 'INVALID_BRAND_NAME';end if;
 perform 1 from private.branding_settings where id for update;
 if chosen=(select current_name from private.branding_settings where id)then raise exception 'BRAND_NAME_UNCHANGED';end if;
 due:=clock_timestamp()+interval '15 minutes';
 update private.branding_settings set pending_name=chosen,activates_at=due,version=v where id;
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
 perform cron.schedule('barberup-brand-name-activation','* * * * *',format('select private.activate_brand_name(%L::uuid)',v));
 return private.branding_status();
end $$;
create or replace function private.cancel_brand_name()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false)then raise exception 'ACCESS_DENIED';end if;
 perform 1 from private.branding_settings where id for update;
 update private.branding_settings set pending_name=null,activates_at=null,version=gen_random_uuid()where id;
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
 return private.branding_status();
end $$;
drop function public.claim_brand_activation(uuid,text);
drop function public.finish_brand_activation(uuid,text,boolean);
drop function private.claim_brand_activation(uuid,text);
drop function private.finish_brand_activation(uuid,text,boolean);
alter table private.branding_settings drop column sync_token_hash,drop column sync_expires_at,
 drop column sync_claimed,drop column sync_error;
