create table private.staff_verification_exemptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table private.staff_verification_exemptions enable row level security;
revoke all on private.staff_verification_exemptions from public, anon, authenticated;
create or replace function private.staff_ok()
returns boolean language sql stable security definer set search_path = ''
as $function$
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
    and exists(select 1 from public.user_roles r where r.user_id=u.id and r.role='barber')
    and not exists(select 1 from public.user_roles r where r.user_id=u.id and r.role='admin')
    and exists(select 1 from public.barbers b where b.user_id=u.id and b.active and b.deleted_at is null)
)
$function$;
