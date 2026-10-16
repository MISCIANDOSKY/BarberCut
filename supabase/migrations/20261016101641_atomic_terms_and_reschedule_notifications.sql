
create function public.publish_terms(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
if not private.has_role('admin') then raise exception 'ACCESS_DENIED';end if;
perform pg_advisory_xact_lock(7348621);
if not exists(select 1 from public.terms_versions where id=p_id and length(trim(body))>20) then raise exception 'INVALID_TERMS';end if;
update public.terms_versions set published=false where published;
update public.terms_versions set published=true where id=p_id;
end $$;
revoke all on function public.publish_terms(uuid) from public,anon;
grant execute on function public.publish_terms(uuid) to authenticated;
create or replace function public.reschedule_appointment(p_id uuid,p_start timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare e public.calendar_entries; svc public.services;
begin
select * into strict e from public.calendar_entries where id=p_id;
if not private.can_manage(e.barber_id) or e.kind<>'appointment' then raise exception 'ACCESS_DENIED';end if;
perform pg_advisory_xact_lock(hashtextextended(e.client_id::text,1));
perform pg_advisory_xact_lock(hashtextextended(e.barber_id::text,2));
select * into strict e from public.calendar_entries where id=p_id for update;
select * into strict svc from public.services where id=e.service_id;
perform set_config('barbercut.internal_reschedule','1',true);
update public.calendar_entries set status='cancelled' where id=p_id;
if not exists(select 1 from public.get_available_slots(e.barber_id,e.service_id,(p_start at time zone 'Europe/Rome')::date) where start_at=p_start) then raise exception 'SLOT_TAKEN';end if;
perform set_config('barbercut.internal_reschedule','0',true);
update public.calendar_entries set start_at=p_start,end_at=p_start+make_interval(mins=>svc.duration_minutes),status='confirmed',updated_at=now() where id=p_id;
end $$;
create or replace function private.notify_entry() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid;
begin
if current_setting('barbercut.internal_reschedule',true)='1' then return new;end if;
if new.kind='appointment' then
if tg_op='UPDATE' and (new.start_at is distinct from old.start_at or new.status is distinct from old.status) then
insert into public.notifications(user_id,title,body) values(new.client_id,case when new.status='cancelled' then 'Appuntamento cancellato' else 'Appuntamento aggiornato' end,coalesce(new.service_name,'Appuntamento')||' · '||to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));
end if;
select user_id into recipient from public.barbers where id=new.barber_id;
if recipient is not null then insert into public.notifications(user_id,title,body) values(recipient,'Aggiornamento agenda',coalesce(new.service_name,'Appuntamento')||' · '||to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));end if;
end if;return new;end $$;
