
create extension if not exists btree_gist with schema extensions;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
-- The obsolete empty table is retained privately for reversible migration.
alter table public.bookings set schema private;
revoke all on private.bookings from anon,authenticated;
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,first_name text not null default '',last_name text not null default '',phone text not null default '',created_at timestamptz not null default now());
create table public.user_roles(user_id uuid primary key references auth.users(id) on delete cascade,role text not null default 'client' check(role in('client','barber','admin')));
create table public.barbers(id uuid primary key default gen_random_uuid(),user_id uuid unique references public.profiles(id),name text not null,active boolean not null default true);
create table public.services(id uuid primary key default gen_random_uuid(),name text not null,description text not null default '',duration_minutes int not null check(duration_minutes>0 and duration_minutes<=480 and duration_minutes%15=0),price numeric(8,2) not null check(price>=0),active boolean not null default true);
create table public.barber_services(barber_id uuid references public.barbers on delete cascade,service_id uuid references public.services on delete cascade,primary key(barber_id,service_id));
create table public.working_hours(id uuid primary key default gen_random_uuid(),barber_id uuid not null references public.barbers on delete cascade,weekday int not null check(weekday between 0 and 6),opens time not null,closes time not null,check(opens<closes));
create table public.schedule_exceptions(id uuid primary key default gen_random_uuid(),barber_id uuid not null references public.barbers on delete cascade,day date not null,closed boolean not null default false,opens time,closes time,check((closed and opens is null and closes is null) or (not closed and opens<closes)));
create table public.calendar_entries(id uuid primary key default gen_random_uuid(),barber_id uuid not null references public.barbers,kind text not null check(kind in('appointment','block')),client_id uuid references public.profiles,service_id uuid references public.services,start_at timestamptz not null,end_at timestamptz not null,status text not null default 'confirmed' check(status in('confirmed','cancelled','completed','no_show')),service_name text,price numeric(8,2),notes text not null default '',created_by uuid references auth.users,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(start_at<end_at),check(kind='block' or(client_id is not null and service_id is not null)),exclude using gist(barber_id with =,tstzrange(start_at,end_at,'[)') with &&) where(status='confirmed'));
create index entries_client_idx on public.calendar_entries(client_id,start_at);
create index entries_service_idx on public.calendar_entries(service_id);
create index entries_creator_idx on public.calendar_entries(created_by);
create index barbers_user_idx on public.barbers(user_id);
create index barber_services_service_idx on public.barber_services(service_id);
create table public.terms_versions(id uuid primary key default gen_random_uuid(),version text unique not null,body text not null,published boolean not null default false,created_at timestamptz not null default now());
create unique index one_published_terms on public.terms_versions(published) where published;
create table public.terms_acceptances(user_id uuid references auth.users on delete cascade,terms_id uuid references public.terms_versions,accepted_at timestamptz not null default now(),primary key(user_id,terms_id));
create index terms_acceptance_terms_idx on public.terms_acceptances(terms_id);
create table public.notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users on delete cascade,title text not null,body text not null,read_at timestamptz,created_at timestamptz not null default now());
create index notifications_user_idx on public.notifications(user_id,created_at);
create table public.app_settings(id boolean primary key default true check(id),shop_name text not null default 'BarberCut',accent text not null default '#c6a66b' check(accent ~ '^#[0-9a-fA-F]{6}$'),cancellation_hours int check(cancellation_hours>=0),bookings_enabled boolean not null default false,timezone text not null default 'Europe/Rome' check(timezone='Europe/Rome'));
insert into public.app_settings(id) values(true);
create table private.staff_sessions(user_id uuid references auth.users on delete cascade,session_id text,otp_hash text not null,expires_at timestamptz not null,verified_until timestamptz,attempts int not null default 0,sent_at timestamptz not null default now(),primary key(user_id,session_id));
create function private.staff_ok() returns boolean language sql stable security definer set search_path='' as $$
select exists(select 1 from private.staff_sessions where user_id=auth.uid() and session_id=auth.jwt()->>'session_id' and verified_until>now())
$$;
create function private.has_role(r text) returns boolean language sql stable security definer set search_path='' as $$
select auth.uid() is not null and exists(select 1 from public.user_roles where user_id=auth.uid() and role=r) and (r='client' or private.staff_ok())
$$;
create function private.can_manage(b uuid) returns boolean language sql stable security definer set search_path='' as $$
select private.has_role('admin') or(private.has_role('barber') and exists(select 1 from public.barbers where id=b and user_id=auth.uid()))
$$;
grant execute on function private.staff_ok(),private.has_role(text),private.can_manage(uuid) to authenticated;
create function private.new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
insert into public.profiles(id,first_name,last_name,phone) values(new.id,coalesce(new.raw_user_meta_data->>'first_name',''),coalesce(new.raw_user_meta_data->>'last_name',''),coalesce(new.raw_user_meta_data->>'phone',''));
insert into public.user_roles(user_id) values(new.id);
return new; end $$;
create trigger barbercut_new_user after insert on auth.users for each row execute function private.new_user();
insert into public.profiles(id,first_name,last_name,phone) select id,coalesce(raw_user_meta_data->>'first_name',''),coalesce(raw_user_meta_data->>'last_name',''),coalesce(raw_user_meta_data->>'phone','') from auth.users;
insert into public.user_roles(user_id) select id from auth.users;

create function private.is_holiday(d date) returns boolean language plpgsql immutable set search_path='' as $$
declare y int:=extract(year from d); a int; b int; c int; h int; l int; m int; easter date;
begin
if to_char(d,'MM-DD')=any(array['01-01','01-06','04-25','05-01','06-02','08-15','11-01','12-08','12-25','12-26']) then return true; end if;
a:=y%19;b:=y/100;c:=y%100;h:=(19*a+b-b/4-(b-(b+8)/25+1)/3+15)%30;l:=(32+2*(b%4)+2*(c/4)-h-c%4)%7;m:=(a+11*h+22*l)/451;
easter:=make_date(y,(h+l-7*m+114)/31,(h+l-7*m+114)%31+1);
return d=easter or d=easter+1;
end $$;
create function public.get_available_slots(p_barber uuid,p_service uuid,p_day date) returns table(start_at timestamptz) language sql stable security definer set search_path='' as $$
with svc as(select s.duration_minutes from public.services s join public.barber_services bs on bs.service_id=s.id join public.barbers b on b.id=bs.barber_id where s.id=p_service and bs.barber_id=p_barber and s.active and b.active),
intervals as(
select e.opens,e.closes from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day and not e.closed and not exists(select 1 from public.schedule_exceptions x where x.barber_id=p_barber and x.day=p_day and x.closed)
union all
select w.opens,w.closes from public.working_hours w where w.barber_id=p_barber and w.weekday=extract(dow from p_day) and not private.is_holiday(p_day) and not exists(select 1 from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day)
),
slots as(select distinct g as t,s.duration_minutes from svc s cross join intervals i cross join lateral generate_series((p_day+i.opens) at time zone 'Europe/Rome',((p_day+i.closes) at time zone 'Europe/Rome')-make_interval(mins=>s.duration_minutes),interval '15 minutes') g)
select t from slots where t>now() and p_day<=(now() at time zone 'Europe/Rome')::date+interval '3 months' and p_day>=(now() at time zone 'Europe/Rome')::date and not exists(select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed' and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(t,t+make_interval(mins=>duration_minutes),'[)')) order by t
$$;
create function public.book_appointment(p_barber uuid,p_service uuid,p_start timestamptz,p_client uuid default null) returns uuid language plpgsql security definer set search_path='' as $$
declare c uuid:=coalesce(p_client,auth.uid()); svc public.services; result uuid; staff boolean:=private.can_manage(p_barber);
begin
if auth.uid() is null or(c<>auth.uid() and not staff) then raise exception 'ACCESS_DENIED'; end if;
if not staff and not (select bookings_enabled from public.app_settings where id) then raise exception 'BOOKINGS_DISABLED'; end if;
perform pg_advisory_xact_lock(hashtextextended(c::text,1));
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
if not exists(select 1 from public.profiles where id=c and length(trim(first_name))>0 and length(trim(last_name))>0 and length(trim(phone))>0) then raise exception 'PROFILE_REQUIRED'; end if;
if exists(select 1 from public.terms_versions where published) and not exists(select 1 from public.terms_acceptances a join public.terms_versions t on t.id=a.terms_id where a.user_id=c and t.published) then raise exception 'TERMS_REQUIRED'; end if;
if(select count(*) from public.calendar_entries where client_id=c and kind='appointment' and status='confirmed' and start_at>now())>=5 then raise exception 'LIMIT_FIVE'; end if;
if not exists(select 1 from public.get_available_slots(p_barber,p_service,(p_start at time zone 'Europe/Rome')::date) a where a.start_at=p_start) then raise exception 'SLOT_TAKEN'; end if;
select * into strict svc from public.services where id=p_service;
insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price,created_by) values(p_barber,'appointment',c,p_service,p_start,p_start+make_interval(mins=>svc.duration_minutes),svc.name,svc.price,auth.uid()) returning id into result;
return result;
end $$;
create function public.cancel_appointment(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare e public.calendar_entries; hours int;
begin
select * into strict e from public.calendar_entries where id=p_id for update;
if not private.can_manage(e.barber_id) then
if e.client_id is distinct from auth.uid() or auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
select cancellation_hours into hours from public.app_settings where id;
if hours is null then raise exception 'CANCELLATION_NOT_CONFIGURED';end if;
if e.start_at<now()+make_interval(hours=>hours) then raise exception 'CANCELLATION_TOO_LATE';end if;
end if;
update public.calendar_entries set status='cancelled',updated_at=now() where id=p_id;
end $$;
create function private.notify_entry() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid;
begin
if new.kind='appointment' then
if tg_op='UPDATE' and (new.start_at is distinct from old.start_at or new.status is distinct from old.status) then
insert into public.notifications(user_id,title,body) values(new.client_id,case when new.status='cancelled' then 'Appuntamento cancellato' else 'Appuntamento aggiornato' end,coalesce(new.service_name,'Appuntamento')||' · '||to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));
end if;
select user_id into recipient from public.barbers where id=new.barber_id;
if recipient is not null then insert into public.notifications(user_id,title,body) values(recipient,'Aggiornamento agenda',coalesce(new.service_name,'Appuntamento')||' · '||to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));end if;
end if;return new;end $$;
create trigger entry_notification after insert or update on public.calendar_entries for each row execute function private.notify_entry();

create function public.staff_issue_otp(p_user uuid,p_session text,p_hash text) returns boolean language plpgsql security definer set search_path='' as $$
begin
if not exists(select 1 from public.user_roles where user_id=p_user and role in('admin','barber')) then return false;end if;
if exists(select 1 from private.staff_sessions where user_id=p_user and session_id=p_session and sent_at>now()-interval '60 seconds') then return false;end if;
insert into private.staff_sessions(user_id,session_id,otp_hash,expires_at) values(p_user,p_session,p_hash,now()+interval '10 minutes') on conflict(user_id,session_id) do update set otp_hash=excluded.otp_hash,expires_at=excluded.expires_at,attempts=0,sent_at=now(),verified_until=null;
return true;end $$;
create function public.staff_verify_otp(p_user uuid,p_session text,p_hash text) returns boolean language plpgsql security definer set search_path='' as $$
declare ok boolean;
begin
select otp_hash=p_hash and attempts<5 and expires_at>now() into ok from private.staff_sessions where user_id=p_user and session_id=p_session for update;
update private.staff_sessions set attempts=attempts+1,verified_until=case when ok then now()+interval '8 hours' else verified_until end,expires_at=case when ok then now() else expires_at end where user_id=p_user and session_id=p_session;
return coalesce(ok,false);end $$;
create function public.staff_session_status() returns boolean language sql stable security invoker set search_path='' as $$select private.staff_ok()$$;
revoke all on function public.staff_issue_otp(uuid,text,text),public.staff_verify_otp(uuid,text,text) from public,anon,authenticated;
grant execute on function public.staff_issue_otp(uuid,text,text),public.staff_verify_otp(uuid,text,text) to service_role;
revoke all on function public.book_appointment(uuid,uuid,timestamptz,uuid),public.cancel_appointment(uuid),public.staff_session_status() from public,anon;
grant execute on function public.book_appointment(uuid,uuid,timestamptz,uuid),public.cancel_appointment(uuid),public.staff_session_status() to authenticated;
revoke all on function public.get_available_slots(uuid,uuid,date) from public;
grant execute on function public.get_available_slots(uuid,uuid,date) to anon,authenticated;

do $policies$
declare t text;
begin
foreach t in array array['profiles','user_roles','barbers','services','barber_services','working_hours','schedule_exceptions','calendar_entries','terms_versions','terms_acceptances','notifications','app_settings'] loop
execute format('alter table public.%I enable row level security',t);
execute format('grant select,insert,update,delete on public.%I to authenticated',t);
execute format('create policy admin_all on public.%I for all to authenticated using(private.has_role(''admin'')) with check(private.has_role(''admin''))',t);
end loop;
end $policies$;
create policy own_profile_read on public.profiles for select to authenticated using(id=auth.uid() or exists(select 1 from public.calendar_entries e where e.client_id=profiles.id and private.can_manage(e.barber_id)));
create policy own_profile_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy own_role_read on public.user_roles for select to authenticated using(user_id=auth.uid());
create policy public_barbers on public.barbers for select to anon,authenticated using(active);
create policy public_services on public.services for select to anon,authenticated using(active);
create policy public_links on public.barber_services for select to anon,authenticated using(true);
create policy public_settings on public.app_settings for select to anon,authenticated using(true);
create policy public_terms on public.terms_versions for select to anon,authenticated using(published);
grant select on public.barbers,public.services,public.barber_services,public.app_settings,public.terms_versions to anon;
create policy own_acceptances_read on public.terms_acceptances for select to authenticated using(user_id=auth.uid());
create policy own_acceptances_insert on public.terms_acceptances for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.terms_versions where id=terms_id and published));
create policy own_entries_read on public.calendar_entries for select to authenticated using(client_id=auth.uid() or private.can_manage(barber_id));
create policy staff_entries_update on public.calendar_entries for update to authenticated using(private.can_manage(barber_id)) with check(private.can_manage(barber_id));
create policy staff_blocks_insert on public.calendar_entries for insert to authenticated with check(kind='block' and private.can_manage(barber_id) and created_by=auth.uid());
create policy staff_hours on public.working_hours for all to authenticated using(private.can_manage(barber_id)) with check(private.can_manage(barber_id));
create policy staff_exceptions on public.schedule_exceptions for all to authenticated using(private.can_manage(barber_id)) with check(private.can_manage(barber_id));
create policy own_notifications_read on public.notifications for select to authenticated using(user_id=auth.uid());
create policy own_notifications_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
revoke update on public.notifications from authenticated;
grant update(read_at) on public.notifications to authenticated;

alter table private.staff_sessions enable row level security;
grant all on all tables in schema public to service_role;
