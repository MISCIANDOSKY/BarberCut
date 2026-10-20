CREATE OR REPLACE FUNCTION private.notify_entry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare recipient uuid; own_manual_insert boolean;
begin
 if current_setting('barbercut.internal_reschedule',true)='1' then return new;end if;
 if new.kind='appointment' then
   if new.client_id is not null and new.status <> 'cancelled' and tg_op='UPDATE'
      and (new.start_at is distinct from old.start_at or new.status is distinct from old.status) then
     insert into public.notifications(user_id,title,body)
     values(new.client_id,'Appuntamento aggiornato',
       coalesce(new.service_name,'Appuntamento')||' · '||to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));
   end if;
   select user_id into recipient from public.barbers where id=new.barber_id;
   own_manual_insert:=tg_op='INSERT' and nullif(btrim(new.guest_first_name),'') is not null
     and new.created_by=recipient and auth.uid()=recipient
     and coalesce(private.can_manage(new.barber_id),false);
   if recipient is not null and not coalesce(own_manual_insert,false) then
     insert into public.notifications(user_id,title,body)
     values(recipient,'Aggiornamento agenda',coalesce(new.service_name,'Appuntamento')||' · '||
       to_char(new.start_at at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI'));
   end if;
 end if;
 return new;
end
$function$
;
