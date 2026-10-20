begin;
create temporary table cancellation_notification_fixture as select * from public.calendar_entries with no data;
create trigger test_notify after insert or update on cancellation_notification_fixture for each row execute function private.notify_entry();
do $$
declare client uuid:=gen_random_uuid(); entry uuid:=gen_random_uuid();
begin
 insert into auth.users(id,email,raw_user_meta_data) values(client,client::text||'@notifications-test.invalid','{"first_name":"Test","last_name":"Cliente"}'::jsonb);
 insert into cancellation_notification_fixture(id,kind,client_id,start_at,end_at,status,service_name) values(entry,'appointment',client,now()+interval '2 days',now()+interval '2 days 30 minutes','confirmed','Servizio di prova');
 update cancellation_notification_fixture set status='cancelled' where id=entry;
 if exists(select 1 from public.notifications where user_id=client) then raise exception 'Cancellation generated client notification';end if;
 update cancellation_notification_fixture set start_at=start_at+interval '1 hour',end_at=end_at+interval '1 hour' where id=entry;
 if exists(select 1 from public.notifications where user_id=client) then raise exception 'Cancelled appointment update generated client notification';end if;
 update cancellation_notification_fixture set status='confirmed' where id=entry;
 if (select count(*) from public.notifications where user_id=client and title='Appuntamento aggiornato')<>1 then raise exception 'Appointment update notification missing';end if;
 update cancellation_notification_fixture set start_at=start_at+interval '1 hour',end_at=end_at+interval '1 hour' where id=entry;
 if (select count(*) from public.notifications where user_id=client and title='Appuntamento aggiornato')<>2 then raise exception 'Reschedule notification missing';end if;
end $$;
select 'cancellation_notification_test_passed' as result;
rollback;
