-- Copy one existing weekly schedule once when a barber is created.
-- Prefer the hiring barber's agenda, then an active Barber Admin, then
-- another active agenda. Never merge different barbers' working hours.
create function private.seed_new_barber_working_hours()
returns trigger language plpgsql security definer set search_path='' as $fn$
declare source_agenda uuid;
begin
 if new.deleted_at is not null then return new;end if;
 select b.id into source_agenda
 from public.barbers b left join public.user_roles r on r.user_id=b.user_id
 where b.id<>new.id and b.active and b.deleted_at is null
 order by (b.user_id=auth.uid()) desc nulls last,
          (r.role='barber_admin') desc nulls last,b.id
 limit 1;
 if source_agenda is null then return new;end if;
 insert into public.working_hours(barber_id,weekday,opens,closes)
 select new.id,w.weekday,w.opens,w.closes from public.working_hours w
 where w.barber_id=source_agenda;
 return new;
end
$fn$;
revoke all on function private.seed_new_barber_working_hours() from public,anon,authenticated;
create trigger seed_working_hours_for_new_barber
after insert on public.barbers for each row execute function private.seed_new_barber_working_hours();
notify pgrst,'reload schema';
