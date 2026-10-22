create function private.search_appointment_activity_log(p_search text,p_before bigint default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare output jsonb;
begin
 if not private.can_view_appointment_log() then raise exception 'ACCESS_DENIED';end if;
 if p_search is null or length(trim(p_search))<2 or length(p_search)>120 or (p_before is not null and p_before<1) then raise exception 'INVALID_SEARCH';end if;
 with page as(
 select l.*,nullif(trim(concat_ws(' ',a.first_name,a.last_name)),'') actor_name,
 nullif(trim(concat_ws(' ',c.first_name,c.last_name)),'') client_name
 from private.appointment_logs l
 left join public.profiles a on a.id=l.actor_id
 left join public.profiles c on c.id=l.client_id
 where (p_before is null or l.id<p_before)
 and not exists(
 select 1 from regexp_split_to_table(lower(trim(p_search)),E'\\s+') word
 where strpos(lower(concat_ws(' ',a.first_name,a.last_name,c.first_name,c.last_name,l.barber_name,
 l.before_state->>'guest_name',l.after_state->>'guest_name',
 l.before_state->>'service_name',l.after_state->>'service_name',
 l.before_state->>'notes',l.after_state->>'notes',
 case l.action when 'created' then 'inserito creato prenotato appuntamento blocco orario'
 when 'cancelled' then 'cancellato annullato appuntamento blocco'
 when 'deleted' then 'eliminato cancellato appuntamento blocco'
 when 'rescheduled' then 'spostato riprogrammato appuntamento blocco'
 when 'restored' then 'ripristinato riattivato appuntamento blocco'
 else 'modificato aggiornato appuntamento blocco' end)),word)=0)
 order by l.id desc limit 51
 ), visible as(select * from page order by id desc limit 50)
 select jsonb_build_object('entries',coalesce((select jsonb_agg(to_jsonb(v) order by v.id desc) from visible v),'[]'::jsonb),
 'has_more',(select count(*)>50 from page)) into output;
 return output;
end $$;
create function public.search_appointment_activity_log(p_search text,p_before bigint default null)
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.search_appointment_activity_log(p_search,p_before)
$$;
revoke all on function private.search_appointment_activity_log(text,bigint) from public,anon,authenticated;
revoke all on function public.search_appointment_activity_log(text,bigint) from public,anon,authenticated;
grant execute on function private.search_appointment_activity_log(text,bigint) to authenticated;
grant execute on function public.search_appointment_activity_log(text,bigint) to authenticated;
