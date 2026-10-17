alter table public.app_settings add column require_user_approval boolean not null default true;
create table private.client_memberships(
 user_id uuid primary key references auth.users(id) on delete cascade,
 status text not null check(status in('pending','approved','rejected')),
 requested_at timestamptz not null default now(),
 reviewed_at timestamptz,
 reviewed_by uuid references auth.users(id) on delete set null
);
alter table private.client_memberships enable row level security;
revoke all on private.client_memberships from public,anon,authenticated;
insert into private.client_memberships(user_id,status,reviewed_at) select id,'approved',now() from public.profiles;
create index client_membership_status_idx on private.client_memberships(status,requested_at desc);

create or replace function private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,first_name,last_name,phone) values(new.id,coalesce(new.raw_user_meta_data->>'first_name',''),coalesce(new.raw_user_meta_data->>'last_name',''),coalesce(new.raw_user_meta_data->>'phone',''));
 insert into public.user_roles(user_id) values(new.id);
 insert into private.client_memberships(user_id,status) values(new.id,case when coalesce((select require_user_approval from public.app_settings where id),true) then 'pending' else 'approved' end);
 return new;
end $$;
create function private.can_review_registrations() returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.has_role('admin'),false) or (coalesce(private.has_role('barber'),false) and exists(select 1 from public.barbers where user_id=auth.uid() and active and deleted_at is null))
$$;
create function private.membership_status() returns text language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 if exists(select 1 from public.user_roles where user_id=auth.uid() and role in('admin','barber')) then return 'approved';end if;
 return coalesce((select status from private.client_memberships where user_id=auth.uid()),'pending');
end $$;
create function public.membership_status() returns text language sql stable security invoker set search_path='' as $$select private.membership_status()$$;
create function private.set_registration_policy(p_required boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 if p_required is null then raise exception 'INVALID_POLICY';end if;
 update public.app_settings set require_user_approval=p_required where id;
end $$;
create function public.set_registration_policy(p_required boolean) returns void language sql security invoker set search_path='' as $$select private.set_registration_policy(p_required)$$;
create function private.list_registration_requests(p_status text default 'pending') returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.can_review_registrations() then raise exception 'ACCESS_DENIED';end if;
 if p_status not in('pending','approved','rejected') or p_status is null then raise exception 'INVALID_STATUS';end if;
 return coalesce((select jsonb_agg(t) from (
 select m.user_id,m.status,m.requested_at,m.reviewed_at,p.first_name,p.last_name,p.phone,a.email,(a.email_confirmed_at is not null) email_verified
 from private.client_memberships m join public.profiles p on p.id=m.user_id join auth.users a on a.id=m.user_id join public.user_roles r on r.user_id=m.user_id and r.role='client'
 where m.status=p_status and a.deleted_at is null
 order by m.requested_at desc limit 200)t),'[]'::jsonb);
end $$;
create function public.list_registration_requests(p_status text default 'pending') returns jsonb language sql stable security invoker set search_path='' as $$select private.list_registration_requests(p_status)$$;
revoke all on function private.can_review_registrations(),private.membership_status(),public.membership_status(),private.set_registration_policy(boolean),public.set_registration_policy(boolean),private.list_registration_requests(text),public.list_registration_requests(text) from public,anon;
grant execute on function private.membership_status(),public.membership_status(),private.set_registration_policy(boolean),public.set_registration_policy(boolean),private.list_registration_requests(text),public.list_registration_requests(text) to authenticated;

create function private.enforce_client_approval() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind='appointment' and new.client_id is not null
 and exists(select 1 from public.user_roles where user_id=new.client_id and role='client')
 and not exists(select 1 from private.client_memberships where user_id=new.client_id and status='approved') then
  raise exception 'USER_APPROVAL_REQUIRED';
 end if;
 return new;
end $$;
revoke all on function private.enforce_client_approval() from public,anon,authenticated;
create trigger client_approval_before_booking before insert or update of client_id,kind on public.calendar_entries for each row execute function private.enforce_client_approval();

create table private.registration_emails(
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references auth.users(id) on delete cascade,
 status text not null default 'pending' check(status in('pending','queued','sending','sent','failed','cancelled')),
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 token_hash bytea,token_expires_at timestamptz,sent_at timestamptz
);
alter table private.registration_emails enable row level security;
revoke all on private.registration_emails from public,anon,authenticated;
create index registration_email_dispatch_idx on private.registration_emails(next_attempt_at) where status in('pending','queued','sending','failed');

create function private.dispatch_registration_emails() returns integer language plpgsql security definer set search_path='' as $$
declare n record;secret text;amount integer:=0;
begin
 if not pg_try_advisory_xact_lock(hashtextextended('barbercut-registration-emails',0)) then return 0;end if;
 update auth.users a set raw_user_meta_data=raw_user_meta_data-'barbercut_approved'-'barbercut_approval_notice'
 where exists(select 1 from private.registration_emails n where n.user_id=a.id and a.raw_user_meta_data->>'barbercut_approval_notice'=n.id::text and (n.token_expires_at<=now() or n.status in('sent','cancelled','failed')));
 for n in select id from private.registration_emails where status in('pending','failed','queued','sending') and attempts<6 and next_attempt_at<=now() order by next_attempt_at limit 10 for update skip locked
 loop
  secret:=gen_random_uuid()::text||gen_random_uuid()::text;
  update private.registration_emails set status='queued',attempts=attempts+1,token_hash=extensions.digest(secret,'sha256'),token_expires_at=now()+interval '30 minutes',next_attempt_at=now()+interval '30 minutes' where id=n.id;
  perform net.http_post(url:='https://wrpwitehcikplsauiwmg.supabase.co/functions/v1/registration-approved',headers:='{"Content-Type":"application/json"}'::jsonb,body:=jsonb_build_object('notice_id',n.id,'token',secret),timeout_milliseconds:=60000);
  amount:=amount+1;
 end loop;
 return amount;
end $$;
create function private.review_registration(p_user uuid,p_decision text) returns void language plpgsql security definer set search_path='' as $$
declare current_status text;
begin
 if not private.can_review_registrations() then raise exception 'ACCESS_DENIED';end if;
 if p_decision is null or p_decision not in('approved','rejected') then raise exception 'INVALID_STATUS';end if;
 if not exists(select 1 from public.user_roles where user_id=p_user and role='client') then raise exception 'CLIENT_REQUIRED';end if;
 select status into current_status from private.client_memberships where user_id=p_user for update;
 if not found then raise exception 'CLIENT_REQUIRED';end if;
 if current_status=p_decision then return;end if;
 if current_status<>'pending' then raise exception 'REGISTRATION_ALREADY_REVIEWED';end if;
 if p_decision='approved' and not exists(select 1 from auth.users where id=p_user and email_confirmed_at is not null and deleted_at is null and(banned_until is null or banned_until<=now())) then raise exception 'EMAIL_NOT_VERIFIED';end if;
 update private.client_memberships set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid() where user_id=p_user;
 if p_decision='approved' then
  insert into private.registration_emails(user_id) values(p_user) on conflict(user_id) do nothing;
  perform private.dispatch_registration_emails();
 end if;
end $$;
create function public.review_registration(p_user uuid,p_decision text) returns void language sql security invoker set search_path='' as $$select private.review_registration(p_user,p_decision)$$;
create function private.claim_registration_email(p_notice uuid,p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare n private.registration_emails%rowtype;address text;
begin
 select * into n from private.registration_emails where id=p_notice and status='queued' and token_hash=extensions.digest(p_token,'sha256') and token_expires_at>now() for update;
 if not found then return null;end if;
 select email into address from auth.users a join private.client_memberships m on m.user_id=a.id and m.status='approved' where a.id=n.user_id and a.email_confirmed_at is not null and a.deleted_at is null and (a.banned_until is null or a.banned_until<=now());
 if address is null then update private.registration_emails set status='cancelled',token_hash=null where id=n.id;return jsonb_build_object('cancelled',true);end if;
 update private.registration_emails set status='sending',next_attempt_at=now()+interval '30 minutes' where id=n.id;
 update auth.users set raw_user_meta_data=coalesce(raw_user_meta_data,'{}'::jsonb)||jsonb_build_object('barbercut_approved',true,'barbercut_approval_notice',n.id::text) where id=n.user_id;
 return jsonb_build_object('email',address);
end $$;
create function private.finish_registration_email(p_notice uuid,p_token text,p_sent boolean) returns void language plpgsql security definer set search_path='' as $$
declare uid uuid;
begin
 select user_id into uid from private.registration_emails where id=p_notice and status='sending' and token_hash=extensions.digest(p_token,'sha256') for update;
 if not found then return;end if;
 update auth.users set raw_user_meta_data=raw_user_meta_data-'barbercut_approved'-'barbercut_approval_notice' where id=uid and raw_user_meta_data->>'barbercut_approval_notice'=p_notice::text;
 update private.registration_emails set status=case when p_sent then 'sent' else 'failed' end,sent_at=case when p_sent then now() else null end,token_hash=null,next_attempt_at=now()+interval '30 minutes' where id=p_notice;
end $$;
create function public.claim_registration_email(p_notice uuid,p_token text) returns jsonb language sql security invoker set search_path='' as $$select private.claim_registration_email(p_notice,p_token)$$;
create function public.finish_registration_email(p_notice uuid,p_token text,p_sent boolean) returns void language sql security invoker set search_path='' as $$select private.finish_registration_email(p_notice,p_token,p_sent)$$;
revoke all on function private.dispatch_registration_emails(),private.review_registration(uuid,text),public.review_registration(uuid,text),private.claim_registration_email(uuid,text),public.claim_registration_email(uuid,text),private.finish_registration_email(uuid,text,boolean),public.finish_registration_email(uuid,text,boolean) from public,anon,authenticated,service_role;
grant execute on function private.review_registration(uuid,text),public.review_registration(uuid,text) to authenticated;
grant execute on function private.claim_registration_email(uuid,text),public.claim_registration_email(uuid,text),private.finish_registration_email(uuid,text,boolean),public.finish_registration_email(uuid,text,boolean) to service_role;
select cron.schedule('barbercut-registration-approved-email','*/5 * * * *','select private.dispatch_registration_emails();');
