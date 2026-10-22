alter table private.branding_settings add column sync_token_hash text,
 add column sync_expires_at timestamptz,add column sync_claimed boolean not null default false,
 add column sync_error boolean not null default false;
create or replace function private.effective_brand_name()
returns text language sql stable security definer set search_path='' as $$
 select current_name from private.branding_settings where id
$$;
create or replace function private.branding_status()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false)then raise exception 'ACCESS_DENIED';end if;
 return(select jsonb_build_object('name',current_name,'pending_name',pending_name,'activates_at',activates_at,
 'server_time',statement_timestamp(),'sync_error',sync_error,
 'setup_required',not exists(select 1 from vault.secrets where name='branding_management_token'))
 from private.branding_settings where id);
end $$;

create or replace function private.activate_brand_name(p_version uuid)
returns void language plpgsql security definer set search_path='' as $$
declare cfg private.branding_settings;remaining numeric;token text;
begin
 select * into cfg from private.branding_settings where id and version=p_version;
 if not found or cfg.pending_name is null then return;end if;
 remaining:=extract(epoch from(cfg.activates_at-clock_timestamp()));
 if remaining>60 then return;end if;
 if remaining>0 then perform pg_sleep(remaining::double precision);end if;
 select * into cfg from private.branding_settings where id for update;
 if cfg.version<>p_version or cfg.pending_name is null or cfg.activates_at>clock_timestamp()then return;end if;
 if cfg.sync_claimed and cfg.sync_expires_at>clock_timestamp()then return;end if;
 token:=gen_random_uuid()::text||gen_random_uuid()::text;
 update private.branding_settings set sync_token_hash=encode(extensions.digest(token,'sha256'),'hex'),
 sync_expires_at=clock_timestamp()+interval '3 minutes',sync_claimed=false where id;
 perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/activate-brand',
 headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('version',p_version,'token',token),timeout_milliseconds:=10000);
end $$;

create function private.claim_brand_activation(p_version uuid,p_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg private.branding_settings;credential text;
begin
 select * into cfg from private.branding_settings where id for update;
 if cfg.version<>p_version or cfg.pending_name is null or cfg.activates_at>clock_timestamp()
 or cfg.sync_claimed or cfg.sync_expires_at<=clock_timestamp()
 or cfg.sync_token_hash is distinct from encode(extensions.digest(p_token,'sha256'),'hex')
 then return null;end if;
 select decrypted_secret into credential from vault.decrypted_secrets where name='branding_management_token'limit 1;
 if credential is null then update private.branding_settings set sync_error=true where id;return null;end if;
 update private.branding_settings set sync_claimed=true where id;
 return jsonb_build_object('name',cfg.pending_name,'access_token',credential);
end $$;
create function public.claim_brand_activation(p_version uuid,p_token text)
returns jsonb language sql security invoker set search_path='' as $$select private.claim_brand_activation(p_version,p_token)$$;

create function private.finish_brand_activation(p_version uuid,p_token text,p_success boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare cfg private.branding_settings;
begin
 select * into cfg from private.branding_settings where id for update;
 if cfg.version<>p_version or cfg.pending_name is null or not cfg.sync_claimed
 or cfg.sync_expires_at<=clock_timestamp()or cfg.sync_token_hash is distinct from encode(extensions.digest(p_token,'sha256'),'hex')
 then return false;end if;
 if not coalesce(p_success,false)then update private.branding_settings set sync_error=true,sync_claimed=false where id;return false;end if;
 update private.branding_settings set current_name=pending_name,pending_name=null,activates_at=null,
 sync_token_hash=null,sync_expires_at=null,sync_claimed=false,sync_error=false where id;
 update public.app_settings set shop_name=cfg.pending_name where id;
 update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('branding_name',cfg.pending_name);
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
 return true;
end $$;
create function public.finish_brand_activation(p_version uuid,p_token text,p_success boolean)
returns boolean language sql security invoker set search_path='' as $$select private.finish_brand_activation(p_version,p_token,p_success)$$;
revoke all on function private.claim_brand_activation(uuid,text),public.claim_brand_activation(uuid,text),private.finish_brand_activation(uuid,text,boolean),public.finish_brand_activation(uuid,text,boolean) from public,anon,authenticated;
grant execute on function private.claim_brand_activation(uuid,text),public.claim_brand_activation(uuid,text),private.finish_brand_activation(uuid,text,boolean),public.finish_brand_activation(uuid,text,boolean)to service_role;

create or replace function private.schedule_brand_name(p_name text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare chosen text:=btrim(p_name); due timestamptz; v uuid:=gen_random_uuid(); cfg private.branding_settings;
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 if not exists(select 1 from vault.secrets where name='branding_management_token')then raise exception 'BRANDING_SETUP_REQUIRED';end if;
 if chosen is null or char_length(chosen)<1 or char_length(chosen)>60 or chosen~'[[:cntrl:]<>]' then raise exception 'INVALID_BRAND_NAME';end if;
 select * into cfg from private.branding_settings where id for update;
 if cfg.sync_claimed and cfg.sync_expires_at>clock_timestamp()then raise exception 'BRAND_CHANGE_PROCESSING';end if;
 if chosen=cfg.current_name then raise exception 'BRAND_NAME_UNCHANGED';end if;
 due:=clock_timestamp()+interval '15 minutes';
 update private.branding_settings set pending_name=chosen,activates_at=due,version=v,sync_claimed=false,sync_token_hash=null,sync_expires_at=null,sync_error=false where id;
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
 -- Retry once per minute; only wait in the final minute, never publish early.
 perform cron.schedule('barberup-brand-name-activation',
 '* * * * *',
 format('select private.activate_brand_name(%L::uuid)',v));
 return private.branding_status();
end $$;


create or replace function private.cancel_brand_name()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 perform 1 from private.branding_settings where id for update;
 if exists(select 1 from private.branding_settings where id and sync_claimed and sync_expires_at>clock_timestamp())then raise exception 'BRAND_CHANGE_PROCESSING';end if;
 update private.branding_settings set pending_name=null,activates_at=null,version=gen_random_uuid(),sync_claimed=false,sync_token_hash=null,sync_expires_at=null,sync_error=false where id;
 perform cron.unschedule(jobid) from cron.job where jobname='barberup-brand-name-activation';
 return private.branding_status();
end $$;
