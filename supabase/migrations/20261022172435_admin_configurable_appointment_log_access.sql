create table private.appointment_log_permissions (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 enabled boolean not null,
 updated_at timestamptz not null default now()
);
alter table private.appointment_log_permissions enable row level security;
revoke all on private.appointment_log_permissions from public,anon,authenticated;
create function private.can_view_appointment_log()
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.has_role('admin') or (
 private.staff_ok() and exists(
 select 1 from public.user_roles r
 left join private.appointment_log_permissions p on p.user_id=r.user_id
 where r.user_id=auth.uid() and r.role in('barber','barber_admin','shop')
 and coalesce(p.enabled,r.role='barber_admin')
 and (r.role='shop' or exists(select 1 from public.barbers b where b.user_id=r.user_id and b.active and b.deleted_at is null))
 )),false)
$$;
create function public.can_view_appointment_log()
returns boolean language sql stable security invoker set search_path='' as $$
 select private.can_view_appointment_log()
$$;
revoke all on function private.can_view_appointment_log() from public,anon,authenticated;
revoke all on function public.can_view_appointment_log() from public,anon,authenticated;
grant execute on function private.can_view_appointment_log() to authenticated;
grant execute on function public.can_view_appointment_log() to authenticated;

create function private.appointment_log_access_users()
returns table(user_id uuid,first_name text,last_name text,role text,enabled boolean)
language plpgsql stable security definer set search_path='' as $$
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 return query select r.user_id,p.first_name,p.last_name,r.role,
 (r.role='admin' or coalesce(a.enabled,r.role='barber_admin'))
 from public.user_roles r join public.profiles p on p.id=r.user_id
 left join private.appointment_log_permissions a on a.user_id=r.user_id
 where r.role in('admin','barber','barber_admin','shop')
 order by lower(p.first_name),lower(p.last_name),r.user_id;
end $$;
create function public.appointment_log_access_users()
returns table(user_id uuid,first_name text,last_name text,role text,enabled boolean)
language sql stable security invoker set search_path='' as $$
 select * from private.appointment_log_access_users()
$$;
create function private.set_appointment_log_access(p_user uuid,p_enabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare target_role text;
begin
 if not coalesce(private.has_role('admin'),false) then raise exception 'ACCESS_DENIED';end if;
 if p_enabled is null then raise exception 'ACCESS_DENIED';end if;
 select role into target_role from public.user_roles where user_id=p_user for update;
 if not found or target_role not in('barber','barber_admin','shop') then raise exception 'ACCESS_DENIED';end if;
 insert into private.appointment_log_permissions(user_id,enabled) values(p_user,p_enabled)
 on conflict(user_id) do update set enabled=excluded.enabled,updated_at=now();
end $$;
create function public.set_appointment_log_access(p_user uuid,p_enabled boolean)
returns void language sql security invoker set search_path='' as $$
 select private.set_appointment_log_access(p_user,p_enabled)
$$;
revoke all on function private.appointment_log_access_users() from public,anon,authenticated;
revoke all on function public.appointment_log_access_users() from public,anon,authenticated;
revoke all on function private.set_appointment_log_access(uuid,boolean) from public,anon,authenticated;
revoke all on function public.set_appointment_log_access(uuid,boolean) from public,anon,authenticated;
grant execute on function private.appointment_log_access_users() to authenticated;
grant execute on function public.appointment_log_access_users() to authenticated;
grant execute on function private.set_appointment_log_access(uuid,boolean) to authenticated;
grant execute on function public.set_appointment_log_access(uuid,boolean) to authenticated;

create or replace function private.appointment_activity_log(p_day date,p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output jsonb;
begin
 if not private.can_view_appointment_log() then raise exception 'ACCESS_DENIED';end if;
 if p_day is null or (p_before is not null and p_before<1) then raise exception 'INVALID_DATE';end if;
 with page as(
 select l.*,nullif(trim(concat_ws(' ',a.first_name,a.last_name)),'') actor_name,
 nullif(trim(concat_ws(' ',c.first_name,c.last_name)),'') client_name
 from private.appointment_logs l
 left join public.profiles a on a.id=l.actor_id
 left join public.profiles c on c.id=l.client_id
 where l.occurred_at >= (p_day::timestamp at time zone 'Europe/Rome')
 and l.occurred_at < ((p_day+1)::timestamp at time zone 'Europe/Rome')
 and (p_before is null or l.id<p_before)
 order by l.id desc limit 51
 ), visible as(select * from page order by id desc limit 50)
 select jsonb_build_object('entries',coalesce((select jsonb_agg(to_jsonb(v) order by v.id desc) from visible v),'[]'::jsonb),
 'has_more',(select count(*)>50 from page)) into output;
 return output;
end $$;
