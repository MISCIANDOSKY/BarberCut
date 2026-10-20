CREATE OR REPLACE FUNCTION private.staff_ok()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select exists(
  select 1 from private.staff_sessions
  where user_id=auth.uid()
    and not exists(select 1 from public.user_roles r where r.user_id=auth.uid() and r.role='shop')
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
) or exists(
 select 1 from public.user_roles r
 join auth.users u on u.id=r.user_id
 join auth.sessions s on s.user_id=u.id
 where r.user_id=auth.uid() and r.role='shop'
 and s.id::text=auth.jwt()->>'session_id'
 and (s.not_after is null or s.not_after>now())
 and (u.banned_until is null or u.banned_until<=now())
 and u.deleted_at is null and u.email_confirmed_at is not null
)
$function$;
CREATE OR REPLACE FUNCTION public.staff_authorize_session(p_user uuid, p_session text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
insert into private.staff_sessions(user_id,session_id,otp_hash,expires_at,verified_until) select p_user,p_session,'managed-by-supabase-auth',now(),now()+interval '8 hours' where exists(select 1 from public.user_roles where user_id=p_user and role in('admin','barber','barber_admin')) on conflict(user_id,session_id) do update set verified_until=now()+interval '8 hours'
$function$;

-- Remove only legacy extra-verification stamps for this role; Auth sessions remain active.
delete from private.staff_sessions s using public.user_roles r where r.user_id=s.user_id and r.role='shop';
