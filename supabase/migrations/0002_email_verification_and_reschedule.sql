
create function public.staff_authorize_session(p_user uuid,p_session text) returns void language sql security definer set search_path='' as $$
insert into private.staff_sessions(user_id,session_id,otp_hash,expires_at,verified_until) select p_user,p_session,'managed-by-supabase-auth',now(),now()+interval '8 hours' where exists(select 1 from public.user_roles where user_id=p_user and role in('admin','barber')) on conflict(user_id,session_id) do update set verified_until=now()+interval '8 hours'
$$;
revoke all on function public.staff_authorize_session(uuid,text) from public,anon,authenticated;
grant execute on function public.staff_authorize_session(uuid,text) to service_role;
drop function public.staff_issue_otp(uuid,text,text);
drop function public.staff_verify_otp(uuid,text,text);
create function public.reschedule_appointment(p_id uuid,p_start timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare e public.calendar_entries;
begin
select * into strict e from public.calendar_entries where id=p_id;
if not private.can_manage(e.barber_id) or e.kind<>'appointment' then raise exception 'ACCESS_DENIED';end if;
perform pg_advisory_xact_lock(hashtextextended(e.client_id::text,1));
perform pg_advisory_xact_lock(hashtextextended(e.barber_id::text,2));
select * into strict e from public.calendar_entries where id=p_id for update;
update public.calendar_entries set status='cancelled' where id=p_id;
if not exists(select 1 from public.get_available_slots(e.barber_id,e.service_id,(p_start at time zone 'Europe/Rome')::date) where start_at=p_start) then raise exception 'SLOT_TAKEN';end if;
update public.calendar_entries set start_at=p_start,end_at=p_start+(e.end_at-e.start_at),status='confirmed',updated_at=now() where id=p_id;
end $$;
revoke all on function public.reschedule_appointment(uuid,timestamptz) from public,anon;
grant execute on function public.reschedule_appointment(uuid,timestamptz) to authenticated;
revoke update on public.calendar_entries from authenticated;
create function public.lookup_client(p_email text,p_barber uuid) returns table(id uuid,first_name text,last_name text,phone text) language sql stable security definer set search_path='' as $$
select p.id,p.first_name,p.last_name,p.phone from public.profiles p join auth.users u on u.id=p.id where private.can_manage(p_barber) and lower(u.email)=lower(trim(p_email))
$$;
revoke all on function public.lookup_client(text,uuid) from public,anon;
grant execute on function public.lookup_client(text,uuid) to authenticated;
