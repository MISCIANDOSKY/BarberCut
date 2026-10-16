
alter table public.app_settings add column account_deletion_enabled boolean not null default false;
alter table public.calendar_entries add column anonymized_at timestamptz;
alter table public.calendar_entries drop constraint calendar_entries_client_id_fkey;
alter table public.calendar_entries add constraint calendar_entries_client_id_fkey foreign key(client_id) references public.profiles(id) on delete set null;
alter table public.calendar_entries drop constraint calendar_entries_created_by_fkey;
alter table public.calendar_entries add constraint calendar_entries_created_by_fkey foreign key(created_by) references auth.users(id) on delete set null;
alter table public.barbers drop constraint barbers_user_id_fkey;
alter table public.barbers add constraint barbers_user_id_fkey foreign key(user_id) references public.profiles(id) on delete set null;
alter table public.calendar_entries drop constraint calendar_entries_check1;
alter table public.calendar_entries add constraint appointment_client_required check(kind='block' or(service_id is not null and(client_id is not null or anonymized_at is not null)));
create function public.prepare_account_deletion(p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
if not(select account_deletion_enabled from public.app_settings where id) then raise exception 'DELETION_NOT_CONFIGURED';end if;
perform pg_advisory_xact_lock(7348622);
if exists(select 1 from public.user_roles where user_id=p_user and role='admin') and(select count(*) from public.user_roles where role='admin')<=1 then raise exception 'LAST_ADMIN';end if;
update public.calendar_entries set status='cancelled',updated_at=now() where status='confirmed' and start_at>now() and(client_id=p_user or barber_id in(select id from public.barbers where user_id=p_user));
update public.calendar_entries set client_id=null,notes='',anonymized_at=now() where client_id=p_user;
update public.barbers set active=false,name='Barbiere disattivato' where user_id=p_user;
end $$;
revoke all on function public.prepare_account_deletion(uuid) from public,anon,authenticated;
grant execute on function public.prepare_account_deletion(uuid) to service_role;
