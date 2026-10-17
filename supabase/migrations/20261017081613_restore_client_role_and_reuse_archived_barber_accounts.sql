alter table public.barbers drop constraint barbers_user_id_key;
create unique index barbers_live_user_id_key on public.barbers(user_id) where deleted_at is null;

create or replace function private.assign_barber_role() returns trigger language plpgsql security definer set search_path='' as $$
declare previous_user uuid;
begin
 if tg_op<>'INSERT' then previous_user:=old.user_id;end if;
 if tg_op<>'DELETE' then
  if new.user_id is not null and new.active and new.deleted_at is null then
   insert into public.user_roles(user_id,role) values(new.user_id,'barber')
   on conflict(user_id) do update set role='barber' where public.user_roles.role<>'admin';
  end if;
 end if;
 if previous_user is not null and not exists(select 1 from public.barbers where user_id=previous_user and deleted_at is null) then
  update public.user_roles set role='client' where user_id=previous_user and role='barber';
  if found then delete from private.staff_sessions where user_id=previous_user;end if;
 end if;
 if tg_op='DELETE' then return old;end if;
 return new;
end $$;
drop trigger assign_linked_barber_role on public.barbers;
create trigger assign_linked_barber_role after insert or update of user_id,active,deleted_at or delete on public.barbers for each row execute function private.assign_barber_role();

-- Reconcile accounts left behind by previously archived barbers; preserve admins.
with demoted as (
 update public.user_roles r set role='client'
 where r.role='barber'
 and exists(select 1 from public.barbers b where b.user_id=r.user_id and b.deleted_at is not null)
 and not exists(select 1 from public.barbers b where b.user_id=r.user_id and b.deleted_at is null)
 returning user_id
)
delete from private.staff_sessions where user_id in(select user_id from demoted);
