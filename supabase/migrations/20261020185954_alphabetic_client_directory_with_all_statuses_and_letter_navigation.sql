create function private.list_clients(p_status text default 'all',p_offset integer default 0,p_from_letter text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.can_review_registrations(),false) then raise exception 'ACCESS_DENIED';end if;
 if p_status is null or p_status not in('all','pending','approved','rejected') then raise exception 'INVALID_STATUS';end if;
 if p_offset is null or p_offset<0 or (p_from_letter is not null and p_from_letter !~ '^[A-Z#]$') then raise exception 'INVALID_STATUS';end if;
 return (
 with eligible as materialized(
 select m.user_id,m.status,m.requested_at,m.reviewed_at,p.first_name,p.last_name,p.phone,a.email,
        (a.email_confirmed_at is not null) email_verified,
        nullif(btrim(concat_ws(' ',nullif(btrim(reviewer.first_name),''),nullif(btrim(reviewer.last_name),''))),'') reviewed_by_name,
 translate(lower(btrim(concat_ws(' ',nullif(btrim(p.first_name),''),nullif(btrim(p.last_name),'')))),'àáâäãåèéêëìíîïòóôöõùúûüçñ','aaaaaaeeeeiiiiooooouuuucn') collate "C" as name_key
 from private.client_memberships m
 join public.profiles p on p.id=m.user_id
 join auth.users a on a.id=m.user_id
 join public.user_roles r on r.user_id=m.user_id and r.role='client'
 left join public.profiles reviewer on reviewer.id=m.reviewed_by

 where (p_status='all' or m.status=p_status) and a.deleted_at is null
 ), tagged as(
 select e.*,case when left(name_key,1)~'^[a-z]$' then upper(left(name_key,1)) else '#'end as letter,
 case when left(name_key,1)~'^[a-z]$' then upper(left(name_key,1)) else '['end collate "C" as sort_letter from eligible e
 ),page as materialized(
 select * from tagged
 where p_from_letter is null or sort_letter>=(case when p_from_letter='#'then '['else p_from_letter end collate "C")
 order by sort_letter,name_key,user_id limit 201 offset p_offset
 )
 select jsonb_build_object(
 'items',coalesce((select jsonb_agg(to_jsonb(t)-'name_key'-'sort_letter') from (select * from page order by sort_letter,name_key,user_id limit 200)t),'[]'::jsonb),
 'has_more',(select count(*) from page)>200,
 'letters',coalesce((select jsonb_agg(x.letter order by x.sort_letter)from(select distinct letter,sort_letter from tagged)x),'[]'::jsonb))
 );
end $$;
create function public.list_clients(p_status text default 'all',p_offset integer default 0,p_from_letter text default null) returns jsonb
language sql stable set search_path='' as $$select private.list_clients(p_status,p_offset,p_from_letter)$$;
revoke all on function private.list_clients(text,integer,text),public.list_clients(text,integer,text) from public,anon;
grant execute on function private.list_clients(text,integer,text),public.list_clients(text,integer,text) to authenticated;
