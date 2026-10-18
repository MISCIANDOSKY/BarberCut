alter table public.barbers add column can_approve_clients boolean not null default false;
-- Keep current lead barbers able to review while new agendas default to false.
update public.barbers b set can_approve_clients=true
from public.user_roles r where r.user_id=b.user_id and r.role='barber_admin'
and b.active and b.deleted_at is null;

create or replace function private.can_review_registrations()
returns boolean language sql stable security definer set search_path='' as $fn$
 select coalesce(private.has_role('admin'),false)
 or (coalesce(private.has_role('barber'),false) and exists(
   select 1 from public.barbers where user_id=auth.uid() and active
   and deleted_at is null and can_approve_clients))
$fn$;
create function public.can_review_registrations()
returns boolean language sql stable security invoker set search_path='' as $fn$
 select private.can_review_registrations()
$fn$;
revoke all on function private.can_review_registrations(),public.can_review_registrations() from public,anon;
grant execute on function private.can_review_registrations(),public.can_review_registrations() to authenticated;

create function private.list_registration_approvers()
returns table(barber_id uuid,barber_name text,account_name text,can_approve boolean)
language plpgsql stable security definer set search_path='' as $fn$
begin
 if not coalesce(private.can_configure_shop(),false) then raise exception 'ACCESS_DENIED';end if;
 return query select b.id,b.name,
   nullif(btrim(concat_ws(' ',nullif(btrim(p.first_name),''),nullif(btrim(p.last_name),''))),''),
   b.can_approve_clients
 from public.barbers b join public.user_roles r on r.user_id=b.user_id
 left join public.profiles p on p.id=b.user_id
 where b.active and b.deleted_at is null and r.role in('barber','barber_admin')
 order by b.name,b.id;
end
$fn$;
create function public.list_registration_approvers()
returns table(barber_id uuid,barber_name text,account_name text,can_approve boolean)
language sql stable security invoker set search_path='' as $fn$
 select * from private.list_registration_approvers()
$fn$;
create function private.set_registration_approver(p_barber uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $fn$
begin
 if not coalesce(private.can_configure_shop(),false) then raise exception 'ACCESS_DENIED';end if;
 if p_enabled is null then raise exception 'INVALID_POLICY';end if;
 update public.barbers b set can_approve_clients=p_enabled
 where b.id=p_barber and b.active and b.deleted_at is null
 and exists(select 1 from public.user_roles r where r.user_id=b.user_id and r.role in('barber','barber_admin'));
 if not found then raise exception 'ACCESS_DENIED';end if;
end
$fn$;
create function public.set_registration_approver(p_barber uuid,p_enabled boolean)
returns void language sql security invoker set search_path='' as $fn$
 select private.set_registration_approver(p_barber,p_enabled)
$fn$;
revoke all on function private.list_registration_approvers(),public.list_registration_approvers(),private.set_registration_approver(uuid,boolean),public.set_registration_approver(uuid,boolean) from public,anon;
grant execute on function private.list_registration_approvers(),public.list_registration_approvers(),private.set_registration_approver(uuid,boolean),public.set_registration_approver(uuid,boolean) to authenticated;
notify pgrst,'reload schema';
