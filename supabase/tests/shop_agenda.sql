begin;
update public.app_settings set require_user_approval=false where id;
do $test$
declare viewer uuid:=gen_random_uuid(); normal uuid:=gen_random_uuid();lead uuid:=gen_random_uuid();customer uuid:=gen_random_uuid();ad uuid:=gen_random_uuid();
 b uuid;bl uuid;inactive uuid;orphan uuid;global_b uuid;s uuid;ap uuid;closed_ap uuid;hidden uuid;block_id uuid;d date:=(now()at time zone 'Europe/Rome')::date+3;t timestamptz;n integer;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)values
 (viewer,'shop-view@example.invalid',now(),'{}'),(normal,'shop-normal@example.invalid',now(),'{}'),
 (lead,'shop-lead@example.invalid',now(),'{}'),(customer,'shop-customer@example.invalid',now(),'{"first_name":"Test","last_name":"Cliente","phone":"12345"}'),
 (ad,'shop-admin@example.invalid',now(),'{}');
 update public.user_roles set role='admin'where user_id=ad;
 insert into public.barbers(name,user_id)values('Shop normal',normal)returning id into b;
 insert into public.barbers(name,user_id)values('Shop lead',lead)returning id into bl;
 update public.user_roles set role='barber_admin'where user_id=lead;
 insert into public.barbers(name)values('Shop no account')returning id into orphan;
 insert into public.barbers(name,user_id,active)values('Shop inactive',customer,false)returning id into inactive;
 insert into public.barbers(name,user_id)values('Shop global admin',ad)returning id into global_b;
 delete from public.working_hours where barber_id in(b,bl,inactive,orphan,global_b);
 insert into public.working_hours(barber_id,weekday,opens,closes)select x.id,w,'09:00','18:00'from(values(b),(bl))x(id)cross join generate_series(0,6)w;
 insert into public.services(name,duration_minutes,price)values('TEST Shop service',30,12)returning id into s;
 insert into public.barber_services(barber_id,service_id)values(b,s),(bl,s),(inactive,s),(orphan,s),(global_b,s);
 while private.is_holiday(d)loop d:=d+1;end loop;t:=(d+time '10:00')at time zone 'Europe/Rome';
 insert into public.calendar_entries(barber_id,kind,client_id,service_id,start_at,end_at,service_name,price)values(b,'appointment',customer,s,t,t+interval '30 minutes','Shop snapshot',12)returning id into ap;
 insert into public.calendar_entries(barber_id,kind,service_id,start_at,end_at,service_name,guest_first_name,guest_last_name,guest_phone)
 values(bl,'appointment',s,t,t+interval '30 minutes','Guest service','Ospite','Test','67890')returning id into closed_ap;
 insert into public.calendar_entries(barber_id,kind,service_id,start_at,end_at,service_name,client_id)
 values(inactive,'appointment',s,t,t+interval '30 minutes','Hidden',customer)returning id into hidden;
 insert into public.calendar_entries(barber_id,kind,start_at,end_at)values(b,'block',t+interval '1 hour',t+interval '2 hours')returning id into block_id;
 perform public.staff_authorize_session(ad,'shop-admin');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','shop-admin')::text,true);
 set local role authenticated;
 update public.user_roles set role='shop'where user_id=viewer;
 reset role;
 if(select role from public.user_roles where user_id=viewer)<>'shop'then raise exception 'Admin cannot assign Shop';end if;
 -- New role requires verified staff access.
 perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer,'role','authenticated','session_id','shop-view')::text,true);
 set local role authenticated;
 begin perform public.shop_barbers();raise exception 'Unverified shop allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 perform public.staff_authorize_session(viewer,'shop-view');
 set local role authenticated;
 if not public.staff_session_status()then raise exception 'Shop authorization failed';end if;
 if not exists(select 1 from public.shop_barbers()where id=b)or not exists(select 1 from public.shop_barbers()where id=bl)
 or exists(select 1 from public.shop_barbers()where id in(inactive,orphan,global_b))then raise exception 'Wrong barber list';end if;
 if not exists(select 1 from public.shop_agenda(b,d)where id=ap and client_name='Test Cliente'and phone='12345'and service_name='Shop snapshot')then raise exception 'Customer booking missing';end if;
 if not exists(select 1 from public.shop_agenda(bl,d)where id=closed_ap and client_name='Ospite Test'and phone='67890')then raise exception 'Guest booking missing';end if;
 if exists(select 1 from public.shop_agenda(b,d)where id=block_id)then raise exception 'Block exposed';end if;
 if exists(select 1 from public.shop_agenda(b,d+1))then raise exception 'Wrong day exposed';end if;
 begin perform public.shop_agenda(inactive,d);raise exception 'Inactive agenda exposed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.cancel_appointment(hidden);raise exception 'Inactive agenda cancellation';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.cancel_appointment(block_id);raise exception 'Shop cancels block';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 if exists(select 1 from public.get_reschedule_slots(ap,d)where start_at=t+interval '1 hour')then raise exception 'Occupied move offered';end if;
 perform public.reschedule_appointment(ap,t+interval '3 hours',false);
 if not exists(select 1 from public.shop_agenda(b,d)where id=ap and start_at=t+interval '3 hours')then raise exception 'Shop move failed';end if;
 begin perform public.reschedule_appointment(ap,t+interval '1 hour',true);raise exception 'Shop overlap allowed';exception when raise_exception then if sqlerrm<>'SLOT_TAKEN'then raise;end if;end;
 begin perform public.reschedule_appointment(ap,d::timestamp at time zone 'Europe/Rome',false);raise exception 'Shop closed bypass';exception when raise_exception then if sqlerrm<>'CLOSED_DAY_CONFIRM_REQUIRED'then raise;end if;end;
 perform public.reschedule_appointment(ap,d::timestamp at time zone 'Europe/Rome',true);
 perform public.cancel_appointment(ap);
 if exists(select 1 from public.shop_agenda(b,d)where id=ap)then raise exception 'Shop cancellation failed';end if;
 if exists(select 1 from public.calendar_entries where id=closed_ap)then raise exception 'Direct RLS expanded';end if;
 begin update public.calendar_entries set status='cancelled'where id=closed_ap;get diagnostics n=row_count;if n<>0 then raise exception 'Direct Shop update allowed';end if;exception when insufficient_privilege then null;end;
 update public.user_roles set role='admin'where user_id=viewer;get diagnostics n=row_count;if n<>0 then raise exception 'Shop role escalation';end if;
 begin perform public.set_recurring_policy(50,true);raise exception 'Shop settings allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.book_appointment(b,s,t+interval '4 hours');raise exception 'Shop client booking allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.book_manual_appointment(b,s,t+interval '4 hours','Fake','Test','',true);raise exception 'Shop manual booking allowed';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 -- Revocation takes effect without waiting for JWT renewal.
 update public.user_roles set role='client'where user_id=viewer;
 set local role authenticated;
 begin perform public.shop_barbers();raise exception 'Revoked shop read';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 begin perform public.reschedule_appointment(closed_ap,t+interval '4 hours',true);raise exception 'Revoked shop move';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED'then raise;end if;end;
 reset role;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 set local role anon;
 begin perform public.shop_barbers();raise exception 'Anonymous shop access';exception when insufficient_privilege then null;end;
 reset role;
end $test$;
select 'PASS Shop role assignment, verified sessions, eligible agendas, scoped reads, move/cancel, conflicts, role revocation, no other powers' result;
rollback;