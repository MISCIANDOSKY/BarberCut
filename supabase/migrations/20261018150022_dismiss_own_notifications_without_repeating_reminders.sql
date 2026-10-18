-- Retain event keys so a dismissed reminder cannot be generated again.
alter table public.notifications add column dismissed_at timestamptz;
alter policy own_notifications_read on public.notifications
 using(user_id=auth.uid() and dismissed_at is null);

create function private.dismiss_notifications(p_id uuid default null)
returns integer language plpgsql security definer set search_path='' as $fn$
declare removed integer;
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 update public.notifications set dismissed_at=now(),read_at=coalesce(read_at,now())
 where user_id=auth.uid() and dismissed_at is null and (p_id is null or id=p_id);
 get diagnostics removed=row_count;
 return removed;
end
$fn$;
create function public.dismiss_notifications(p_id uuid default null)
returns integer language sql security invoker set search_path='' as $fn$
 select private.dismiss_notifications(p_id)
$fn$;
revoke all on function private.dismiss_notifications(uuid),public.dismiss_notifications(uuid) from public,anon;
grant execute on function private.dismiss_notifications(uuid),public.dismiss_notifications(uuid) to authenticated;
notify pgrst,'reload schema';
