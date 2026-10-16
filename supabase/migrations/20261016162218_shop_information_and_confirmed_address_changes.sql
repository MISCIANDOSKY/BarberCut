alter table public.app_settings add column shop_address text not null default '', add column address_revision integer not null default 0 check(address_revision>=0);
create function private.update_shop_address(p_address text,p_expected_revision integer,p_confirm boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare current_address text;current_revision integer;cleaned text:=btrim(p_address);
begin
 if not (coalesce(private.has_role('admin'),false) or (coalesce(private.has_role('barber'),false) and exists(select 1 from public.barbers where user_id=auth.uid() and active and deleted_at is null))) then raise exception 'ACCESS_DENIED';end if;
 if cleaned is null or length(cleaned)<3 or length(cleaned)>500 then raise exception 'INVALID_ADDRESS';end if;
 select shop_address,address_revision into current_address,current_revision from public.app_settings where id for update;
 if p_expected_revision is distinct from current_revision then raise exception 'ADDRESS_CHANGED';end if;
 if cleaned=current_address then return jsonb_build_object('address',current_address,'revision',current_revision);end if;
 if current_revision>0 and p_confirm is distinct from true then raise exception 'ADDRESS_CONFIRMATION_REQUIRED';end if;
 update public.app_settings set shop_address=cleaned,address_revision=address_revision+1 where id returning address_revision into current_revision;
 return jsonb_build_object('address',cleaned,'revision',current_revision);
end $$;
create function public.update_shop_address(p_address text,p_expected_revision integer,p_confirm boolean default false) returns jsonb language sql security invoker set search_path='' as $$select private.update_shop_address(p_address,p_expected_revision,p_confirm)$$;
revoke all on function private.update_shop_address(text,integer,boolean),public.update_shop_address(text,integer,boolean) from public,anon;
grant execute on function private.update_shop_address(text,integer,boolean),public.update_shop_address(text,integer,boolean) to authenticated;
create function private.shop_information() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('shop_name',s.shop_name,'address',s.shop_address,'barbers',coalesce((
 select jsonb_agg(jsonb_build_object(
  'id',b.id,'name',b.name,
  'hours',coalesce((select jsonb_agg(jsonb_build_object('weekday',h.weekday,'opens',h.opens,'closes',h.closes) order by h.weekday,h.opens) from public.working_hours h where h.barber_id=b.id),'[]'::jsonb),
  'exceptions',coalesce((select jsonb_agg(jsonb_build_object('day',e.day,'closed',e.closed,'opens',e.opens,'closes',e.closes) order by e.day,e.opens) from public.schedule_exceptions e where e.barber_id=b.id and e.day between (now() at time zone 'Europe/Rome')::date and (now() at time zone 'Europe/Rome')::date+30),'[]'::jsonb)
 ) order by b.name) from public.barbers b where b.active and b.deleted_at is null
 ),'[]'::jsonb)) from public.app_settings s where s.id
$$;
create function public.shop_information() returns jsonb language sql stable security invoker set search_path='' as $$select private.shop_information()$$;
revoke all on function private.shop_information(),public.shop_information() from public;
grant execute on function private.shop_information(),public.shop_information() to anon,authenticated;
