-- Keep both in-app reminders and the existing appointment/start-time deduplication keys.
create or replace function private.appointment_reminders()
returns void language sql security definer set search_path='' as $function$
 insert into public.notifications(user_id,title,body,event_key)
 select e.client_id,
   case when r.kind='24h' then 'Promemoria appuntamento · 24 ore' else 'Promemoria appuntamento · 1 ora' end,
   'Ricordati del tuo appuntamento! Hai prenotato ' || coalesce(nullif(trim(e.service_name),''),'un servizio') ||
   ' per il ' || to_char(e.start_at at time zone 'Europe/Rome','DD/MM/YYYY') ||
   ' alle ' || to_char(e.start_at at time zone 'Europe/Rome','HH24:MI') ||
   '. Ti aspettiamo in barberia.',
   e.id::text || ':' || r.kind || ':' || extract(epoch from e.start_at)::text
 from public.calendar_entries e
 cross join (values ('24h',interval '23 hours',interval '24 hours'),('1h',interval '0 hours',interval '1 hour')) r(kind,lower_bound,upper_bound)
 where e.client_id is not null and e.kind='appointment' and e.status='confirmed'
   and e.start_at>now() and e.start_at>=now()+r.lower_bound and e.start_at<=now()+r.upper_bound
 on conflict(event_key) do nothing
$function$;
revoke all on function private.appointment_reminders() from public,anon,authenticated,service_role;
