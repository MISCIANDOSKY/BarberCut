alter table public.user_roles drop constraint user_roles_role_check;
alter table public.user_roles add constraint user_roles_role_check check(role in('client','barber','barber_admin','admin'));
alter table public.barber_services add column active boolean not null default true;
create or replace function private.has_role(r text)
returns boolean language sql stable security definer set search_path='' as $function$
 select auth.uid() is not null
 and exists(select 1 from public.user_roles ur where ur.user_id=auth.uid()
   and (ur.role=r or (r='barber' and ur.role='barber_admin')))
 and (r='client' or private.staff_ok())
$function$;
create function private.can_manage_services(b uuid)
returns boolean language sql stable security definer set search_path='' as $function$
 select coalesce(private.has_role('admin'),false)
 or (coalesce(private.has_role('barber_admin'),false) and exists(
   select 1 from public.barbers where id=b and user_id=auth.uid() and active and deleted_at is null))
$function$;
create function private.can_configure_shop()
returns boolean language sql stable security definer set search_path='' as $function$
 select coalesce(private.has_role('admin'),false)
 or (coalesce(private.has_role('barber_admin'),false) and exists(
   select 1 from public.barbers where user_id=auth.uid() and active and deleted_at is null))
$function$;
revoke all on function private.can_manage_services(uuid),private.can_configure_shop() from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.staff_authorize_session(p_user uuid, p_session text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
insert into private.staff_sessions(user_id,session_id,otp_hash,expires_at,verified_until) select p_user,p_session,'managed-by-supabase-auth',now(),now()+interval '8 hours' where exists(select 1 from public.user_roles where user_id=p_user and role in('admin','barber','barber_admin')) on conflict(user_id,session_id) do update set verified_until=now()+interval '8 hours'
$function$;

CREATE OR REPLACE FUNCTION private.membership_status()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 if exists(select 1 from public.user_roles where user_id=auth.uid() and role in('admin','barber','barber_admin')) then return 'approved';end if;
 return coalesce((select status from private.client_memberships where user_id=auth.uid()),'pending');
end $function$;

CREATE OR REPLACE FUNCTION private.staff_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select exists(
  select 1 from private.staff_sessions
  where user_id=auth.uid()
    and session_id=auth.jwt()->>'session_id'
    and verified_until>now()
) or exists(
  select 1
  from private.staff_verification_exemptions e
  join auth.users u on u.id=e.user_id
  join auth.sessions s on s.user_id=u.id
  where e.user_id=auth.uid()
    and s.id::text=auth.jwt()->>'session_id'
    and (s.not_after is null or s.not_after>now())
    and (u.banned_until is null or u.banned_until<=now())
    and u.deleted_at is null
    and u.email_confirmed_at is not null
    and exists(select 1 from public.user_roles r where r.user_id=u.id and r.role in('barber','barber_admin'))
    and not exists(select 1 from public.user_roles r where r.user_id=u.id and r.role='admin')
    and exists(select 1 from public.barbers b where b.user_id=u.id and b.active and b.deleted_at is null)
)
$function$;

CREATE OR REPLACE FUNCTION private.assign_barber_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous_user uuid;
begin
 if tg_op<>'INSERT' then previous_user:=old.user_id;end if;
 if tg_op<>'DELETE' then
  if new.user_id is not null and new.active and new.deleted_at is null then
   insert into public.user_roles(user_id,role) values(new.user_id,'barber')
   on conflict(user_id) do update set role='barber' where public.user_roles.role not in('admin','barber_admin');
  end if;
 end if;
 if previous_user is not null and not exists(select 1 from public.barbers where user_id=previous_user and deleted_at is null) then
  update public.user_roles set role='client' where user_id=previous_user and role in('barber','barber_admin');
  if found then delete from private.staff_sessions where user_id=previous_user;end if;
 end if;
 if tg_op='DELETE' then return old;end if;
 return new;
end $function$;

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
insert into public.barber_services(barber_id,service_id,active) select p_barber,saved,bs.active from public.barber_services bs where bs.barber_id=p_barber and bs.service_id=p_service;
delete from public.barber_services where barber_id=p_barber and service_id=p_service;
previous_flag:=current_setting('barbercut.internal_reschedule',true);
perform set_config('barbercut.internal_reschedule','1',true);
update public.calendar_entries set service_id=saved where barber_id=p_barber and service_id=p_service;
perform set_config('barbercut.internal_reschedule',coalesce(previous_flag,'0'),true);
else
update public.services set name=trim(p_name),description=coalesce(p_description,''),duration_minutes=p_duration,price=p_price where id=p_service;
saved:=p_service;
end if;
end if;return saved;end $function$;

CREATE OR REPLACE FUNCTION private.remove_barber_service(p_barber uuid, p_service uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
if not private.can_manage_services(p_barber) then raise exception 'ACCESS_DENIED';end if;
perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
perform 1 from public.services where id=p_service for update;
if not exists(select 1 from public.barber_services where barber_id=p_barber and service_id=p_service) then raise exception 'ACCESS_DENIED';end if;
delete from public.barber_services where barber_id=p_barber and service_id=p_service;
if not exists(select 1 from public.barber_services where service_id=p_service) then update public.services set active=false,deleted_at=now() where id=p_service;end if;
end $function$;

CREATE OR REPLACE FUNCTION private.update_shop_address(p_address text, p_expected_revision integer, p_confirm boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare current_address text;current_revision integer;cleaned text:=btrim(p_address);
begin
 if not private.can_configure_shop() then raise exception 'ACCESS_DENIED';end if;
 if cleaned is null or length(cleaned)<3 or length(cleaned)>500 then raise exception 'INVALID_ADDRESS';end if;
 select shop_address,address_revision into current_address,current_revision from public.app_settings where id for update;
 if p_expected_revision is distinct from current_revision then raise exception 'ADDRESS_CHANGED';end if;
 if cleaned=current_address then return jsonb_build_object('address',current_address,'revision',current_revision);end if;
 if current_revision>0 and p_confirm is distinct from true then raise exception 'ADDRESS_CONFIRMATION_REQUIRED';end if;
 update public.app_settings set shop_address=cleaned,address_revision=address_revision+1 where id returning address_revision into current_revision;
 return jsonb_build_object('address',cleaned,'revision',current_revision);
end $function$;

CREATE OR REPLACE FUNCTION private.set_registration_policy(p_required boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not coalesce(private.can_configure_shop(), false) then
    raise exception 'ACCESS_DENIED';
  end if;
  if p_required is null then
    raise exception 'INVALID_POLICY';
  end if;
  update public.app_settings set require_user_approval = p_required where id;
end
$function$;

CREATE OR REPLACE FUNCTION private.get_available_slots(p_barber uuid, p_service uuid, p_day date)
 RETURNS TABLE(start_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with svc as(select s.duration_minutes from public.services s join public.barber_services bs on bs.service_id=s.id join public.barbers b on b.id=bs.barber_id where s.id=p_service and bs.barber_id=p_barber and s.active and bs.active and b.active and s.deleted_at is null and b.deleted_at is null),
intervals as(
select e.opens,e.closes from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day and not e.closed and not exists(select 1 from public.schedule_exceptions x where x.barber_id=p_barber and x.day=p_day and x.closed)
union all
select w.opens,w.closes from public.working_hours w where w.barber_id=p_barber and w.weekday=extract(dow from p_day) and not private.is_holiday(p_day) and not exists(select 1 from public.schedule_exceptions e where e.barber_id=p_barber and e.day=p_day)
),
slots as(select distinct g as t,s.duration_minutes from svc s cross join intervals i cross join lateral generate_series((p_day+i.opens) at time zone 'Europe/Rome',((p_day+i.closes) at time zone 'Europe/Rome')-make_interval(mins=>s.duration_minutes),interval '15 minutes') g)
select t from slots where t>now() and p_day<=(now() at time zone 'Europe/Rome')::date+interval '3 months' and p_day>=(now() at time zone 'Europe/Rome')::date and not exists(select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed' and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(t,t+make_interval(mins=>duration_minutes),'[)')) order by t
$function$;

CREATE OR REPLACE FUNCTION private.validate_booking_configuration()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
if new.bookings_enabled and(not exists(select 1 from public.terms_versions where published) or not exists(select 1 from public.barber_services bs join public.barbers b on b.id=bs.barber_id join public.services s on s.id=bs.service_id join public.working_hours w on w.barber_id=b.id where b.active and s.active and bs.active and b.deleted_at is null and s.deleted_at is null) or new.cancellation_hours is null) then raise exception 'SETUP_REQUIRED';end if;return new;end $function$;

CREATE OR REPLACE FUNCTION private.seed_new_barber_services()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.deleted_at is null then
    insert into public.barber_services(barber_id,service_id)
    select distinct new.id,s.id
    from public.barber_services bs
    join public.barbers b on b.id=bs.barber_id
    join public.services s on s.id=bs.service_id
    where b.id<>new.id and b.active and b.deleted_at is null
      and bs.active and s.active and s.deleted_at is null
    on conflict(barber_id,service_id) do nothing;
  end if;
  return new;
end
$function$;

create function private.set_barber_service_active(p_barber uuid,p_service uuid,p_active boolean)
returns void language plpgsql security definer set search_path='' as $function$
begin
 if not coalesce(private.can_manage(p_barber),false) then raise exception 'ACCESS_DENIED';end if;
 if p_active is null then raise exception 'INVALID_SERVICE';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_barber::text,2));
 perform 1 from public.services where id=p_service and deleted_at is null for share;
 if not found then raise exception 'ACCESS_DENIED';end if;
 update public.barber_services set active=p_active where barber_id=p_barber and service_id=p_service;
 if not found then raise exception 'ACCESS_DENIED';end if;
end
$function$;
create function public.set_barber_service_active(p_barber uuid,p_service uuid,p_active boolean)
returns void language sql security invoker set search_path='' as $function$
 select private.set_barber_service_active(p_barber,p_service,p_active)
$function$;
revoke all on function private.set_barber_service_active(uuid,uuid,boolean), public.set_barber_service_active(uuid,uuid,boolean) from public,anon;
grant execute on function private.set_barber_service_active(uuid,uuid,boolean), public.set_barber_service_active(uuid,uuid,boolean) to authenticated;
create or replace function private.get_manual_booking_slots(p_barber uuid,p_service uuid,p_day date)
returns table(start_at timestamptz,requires_confirmation boolean)
language plpgsql stable security definer set search_path='' as $function$
declare duration integer;
begin
 if not coalesce(private.can_manage(p_barber),false) then raise exception 'ACCESS_DENIED';end if;
 select s.duration_minutes into duration
 from public.services s join public.barber_services bs on bs.service_id=s.id join public.barbers b on b.id=bs.barber_id
 where s.id=p_service and b.id=p_barber and s.active and bs.active and b.active and s.deleted_at is null and b.deleted_at is null;
 if not found then return;end if;
 if p_day is null or p_day<(now() at time zone 'Europe/Rome')::date
    or p_day>((now() at time zone 'Europe/Rome')::date+interval '3 months')::date then return;end if;
 return query
 with regular as materialized(select s.start_at from public.get_available_slots(p_barber,p_service,p_day) s)
 select g.t,not exists(select 1 from regular r where r.start_at=g.t)
 from generate_series(p_day::timestamp at time zone 'Europe/Rome',
   ((p_day+1)::timestamp at time zone 'Europe/Rome')-make_interval(mins=>duration),
   interval '15 minutes') g(t)
 where g.t>now() and not exists(
   select 1 from public.calendar_entries e where e.barber_id=p_barber and e.status='confirmed'
   and tstzrange(e.start_at,e.end_at,'[)') && tstzrange(g.t,g.t+make_interval(mins=>duration),'[)')
 ) order by g.t;
end
$function$;
notify pgrst,'reload schema';