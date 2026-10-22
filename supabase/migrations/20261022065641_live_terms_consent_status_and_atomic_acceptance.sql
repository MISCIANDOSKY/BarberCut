create or replace function private.current_terms_status()
returns jsonb language plpgsql stable security definer set search_path='' as $function$
declare current_terms public.terms_versions;
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 select * into current_terms from public.terms_versions where published limit 1;
 if not found then return jsonb_build_object('terms',null,'accepted',true);end if;
 return jsonb_build_object('terms',to_jsonb(current_terms),'accepted',
 exists(select 1 from public.terms_acceptances where user_id=auth.uid() and terms_id=current_terms.id));
end $function$;
create or replace function public.current_terms_status()
returns jsonb language sql set search_path='' as $function$select private.current_terms_status()$function$;

create or replace function private.accept_current_terms(p_id uuid)
returns void language plpgsql security definer set search_path='' as $function$
begin
 if auth.uid() is null then raise exception 'ACCESS_DENIED';end if;
 -- Serialize consent with publication: an old dialog cannot accept a newer version.
 perform pg_advisory_xact_lock(7348621);
 if p_id is null or not exists(select 1 from public.terms_versions where id=p_id and published) then raise exception 'TERMS_CHANGED';end if;
 insert into public.terms_acceptances(user_id,terms_id)values(auth.uid(),p_id)
 on conflict(user_id,terms_id)do nothing;
end $function$;
create or replace function public.accept_current_terms(p_id uuid)
returns void language sql set search_path='' as $function$select private.accept_current_terms(p_id)$function$;

revoke all on function private.current_terms_status(),public.current_terms_status(),
private.accept_current_terms(uuid),public.accept_current_terms(uuid) from public,anon;
grant execute on function private.current_terms_status(),public.current_terms_status(),
private.accept_current_terms(uuid),public.accept_current_terms(uuid) to authenticated;

-- Only public legal text changes are streamed; existing RLS remains in force.
do $migration$
begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime'
 and schemaname='public' and tablename='terms_versions')then
 alter publication supabase_realtime add table public.terms_versions;
 end if;
end $migration$;
