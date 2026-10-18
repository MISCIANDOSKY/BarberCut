create or replace function private.list_registration_requests(p_status text default 'pending')
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
begin
 if not private.can_review_registrations() then raise exception 'ACCESS_DENIED';end if;
 if p_status not in('pending','approved','rejected') or p_status is null then raise exception 'INVALID_STATUS';end if;
 return coalesce((select jsonb_agg(t) from (
 select m.user_id,m.status,m.requested_at,m.reviewed_at,p.first_name,p.last_name,p.phone,a.email,
        (a.email_confirmed_at is not null) email_verified,
        nullif(btrim(concat_ws(' ',nullif(btrim(reviewer.first_name),''),nullif(btrim(reviewer.last_name),''))),'') reviewed_by_name
 from private.client_memberships m
 join public.profiles p on p.id=m.user_id
 join auth.users a on a.id=m.user_id
 join public.user_roles r on r.user_id=m.user_id and r.role='client'
 left join public.profiles reviewer on reviewer.id=m.reviewed_by
 where m.status=p_status and a.deleted_at is null
 order by m.requested_at desc limit 200)t),'[]'::jsonb);
end
$fn$;
notify pgrst,'reload schema';
