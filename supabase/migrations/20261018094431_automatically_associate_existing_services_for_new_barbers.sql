-- Seed a new barber from services currently offered by existing active barbers.
-- Later changes use the existing per-barber copy-on-write service workflow.
create function private.seed_new_barber_services()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if new.deleted_at is null then
    insert into public.barber_services(barber_id,service_id)
    select distinct new.id,s.id
    from public.barber_services bs
    join public.barbers b on b.id=bs.barber_id
    join public.services s on s.id=bs.service_id
    where b.id<>new.id and b.active and b.deleted_at is null
      and s.active and s.deleted_at is null
    on conflict(barber_id,service_id) do nothing;
  end if;
  return new;
end
$function$;
revoke all on function private.seed_new_barber_services() from public,anon,authenticated;
create trigger seed_services_for_new_barber
after insert on public.barbers
for each row execute function private.seed_new_barber_services();
