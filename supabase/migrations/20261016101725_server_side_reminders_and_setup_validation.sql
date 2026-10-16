
create extension if not exists pg_cron;
alter table public.notifications add column event_key text unique;
create function private.appointment_reminders() returns void language sql security definer set search_path='' as $$
insert into public.notifications(user_id,title,body,event_key)
select e.client_id,case when e.start_at<=now()+interval '1 hour' then 'Promemoria appuntamento' else 'Il tuo appuntamento è domani' end,
e.service_name||' · '||to_char(e.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'),
e.id::text||case when e.start_at<=now()+interval '1 hour' then ':1h:' else ':24h:' end||extract(epoch from e.start_at)::text
from public.calendar_entries e
where e.kind='appointment' and e.status='confirmed' and e.start_at>now() and(e.start_at<=now()+interval '1 hour' or e.start_at between now()+interval '23 hours' and now()+interval '24 hours')
on conflict(event_key) do nothing
$$;
select cron.schedule('barbercut-appointment-reminders','*/5 * * * *','select private.appointment_reminders()');
create function private.validate_booking_configuration() returns trigger language plpgsql security definer set search_path='' as $$
begin
if new.bookings_enabled and(not exists(select 1 from public.terms_versions where published) or not exists(select 1 from public.barber_services bs join public.barbers b on b.id=bs.barber_id join public.services s on s.id=bs.service_id join public.working_hours w on w.barber_id=b.id where b.active and s.active) or new.cancellation_hours is null) then raise exception 'SETUP_REQUIRED';end if;return new;end $$;
create trigger require_setup before insert or update on public.app_settings for each row execute function private.validate_booking_configuration();
