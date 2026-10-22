create table private.appointment_logs (
 id bigint generated always as identity primary key,
 occurred_at timestamptz not null default clock_timestamp(),
 actor_id uuid references public.profiles(id) on delete set null,
 actor_role text not null check(actor_role in ('barber','barber_admin','shop')),
 entry_id uuid not null,
 barber_id uuid not null,
 barber_name text not null,
 client_id uuid references public.profiles(id) on delete set null,
 action text not null check(action in ('created','updated','rescheduled','cancelled','restored','deleted')),
 changed_fields text[] not null default '{}',
 before_state jsonb,
 after_state jsonb
);
create index appointment_logs_day_id_idx on private.appointment_logs(occurred_at,id desc);
create index appointment_logs_actor_idx on private.appointment_logs(actor_id);
create index appointment_logs_client_idx on private.appointment_logs(client_id);
alter table private.appointment_logs enable row level security;
revoke all on private.appointment_logs from public,anon,authenticated;
revoke all on sequence private.appointment_logs_id_seq from public,anon,authenticated;

-- Keep appointment details, without duplicating registered customers' personal data,
-- telephone numbers, email addresses or session tokens.
create function private.appointment_log_snapshot(e public.calendar_entries)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object(
 'kind',e.kind,'start_at',e.start_at,'end_at',e.end_at,'status',e.status,
 'service_name',e.service_name,'price',e.price,'notes',e.notes,
 'guest_name',case when e.client_id is null then nullif(trim(concat_ws(' ',e.guest_first_name,e.guest_last_name)),'') else null end)
$$;
revoke all on function private.appointment_log_snapshot(public.calendar_entries) from public,anon,authenticated;

create function private.capture_appointment_log()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 who uuid:=auth.uid(); who_role text; e public.calendar_entries;
 before_data jsonb; after_data jsonb; changed text[]; operation text; old_raw jsonb; new_raw jsonb;
begin
 select role into who_role from public.user_roles where user_id=who;
 -- Cron jobs, maintenance, clients and global Admin actions are outside this log.
 if who is null or who_role is null or who_role not in ('barber','barber_admin','shop') then return null;end if;
 if tg_op='DELETE' then e:=old;else e:=new;end if;
 if tg_op<>'INSERT' then before_data:=private.appointment_log_snapshot(old);old_raw:=to_jsonb(old);end if;
 if tg_op<>'DELETE' then after_data:=private.appointment_log_snapshot(new);new_raw:=to_jsonb(new);end if;
 if tg_op='UPDATE' then
  select array_agg(k order by k) into changed
  from unnest(array['barber_id','kind','client_id','service_id','start_at','end_at','status','service_name','price','notes','guest_first_name','guest_last_name','guest_phone']) k
  where old_raw->k is distinct from new_raw->k;
  if changed is null then return null;end if;
  operation:=case
   when old.status is distinct from new.status and new.status='cancelled' then 'cancelled'
   when old.status is distinct from new.status and new.status='confirmed' then 'restored'
   when old.start_at is distinct from new.start_at or old.end_at is distinct from new.end_at or old.barber_id is distinct from new.barber_id then 'rescheduled'
   else 'updated' end;
 elsif tg_op='INSERT' then operation:='created';changed:='{}';
 else operation:='deleted';changed:='{}';end if;
 insert into private.appointment_logs(actor_id,actor_role,entry_id,barber_id,barber_name,client_id,action,changed_fields,before_state,after_state)
 values(who,who_role,e.id,e.barber_id,coalesce((select name from public.barbers where id=e.barber_id),'Agenda rimossa'),e.client_id,operation,changed,before_data,after_data);
 return null;
end $$;
revoke all on function private.capture_appointment_log() from public,anon,authenticated;
create trigger appointment_audit_log after insert or update or delete on public.calendar_entries
for each row execute function private.capture_appointment_log();

create function private.appointment_activity_log(p_day date,p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output jsonb;
begin
 if not coalesce(private.has_role('admin') or (
 private.has_role('barber_admin') and exists(select 1 from public.barbers b where b.user_id=auth.uid() and b.active and b.deleted_at is null)),false)
 then raise exception 'ACCESS_DENIED';end if;
 if p_day is null or (p_before is not null and p_before<1) then raise exception 'INVALID_DATE';end if;
 with page as(
 select l.*,nullif(trim(concat_ws(' ',a.first_name,a.last_name)),'') actor_name,
 nullif(trim(concat_ws(' ',c.first_name,c.last_name)),'') client_name
 from private.appointment_logs l
 left join public.profiles a on a.id=l.actor_id
 left join public.profiles c on c.id=l.client_id
 where l.occurred_at >= (p_day::timestamp at time zone 'Europe/Rome')
 and l.occurred_at < ((p_day+1)::timestamp at time zone 'Europe/Rome')
 and (p_before is null or l.id<p_before)
 order by l.id desc limit 51
 ), visible as(select * from page order by id desc limit 50)
 select jsonb_build_object('entries',coalesce((select jsonb_agg(to_jsonb(v) order by v.id desc) from visible v),'[]'::jsonb),
 'has_more',(select count(*)>50 from page)) into output;
 return output;
end $$;
create function public.appointment_activity_log(p_day date,p_before bigint default null)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.appointment_activity_log(p_day,p_before)
$$;
revoke all on function private.appointment_activity_log(date,bigint) from public,anon,authenticated;
revoke all on function public.appointment_activity_log(date,bigint) from public,anon,authenticated;
grant execute on function private.appointment_activity_log(date,bigint) to authenticated;
grant execute on function public.appointment_activity_log(date,bigint) to authenticated;
