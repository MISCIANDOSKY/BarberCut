-- Allow verified staff who can review registrations to change only the shop registration policy.
-- The full maintenance settings remain admin-only.
create or replace function private.set_registration_policy(p_required boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not coalesce(private.can_review_registrations(), false) then
    raise exception 'ACCESS_DENIED';
  end if;
  if p_required is null then
    raise exception 'INVALID_POLICY';
  end if;
  update public.app_settings set require_user_approval = p_required where id;
end
$function$;
revoke all on function private.set_registration_policy(boolean) from public, anon;
grant execute on function private.set_registration_policy(boolean) to authenticated;
