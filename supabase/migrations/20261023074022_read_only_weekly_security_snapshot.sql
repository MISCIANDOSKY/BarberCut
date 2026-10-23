-- Read-only aggregate security checks. No application/customer rows are queried.
create or replace function private.weekly_security_snapshot()
returns jsonb language sql stable security definer set search_path = '' as $$
with tables as (
 select c.oid,c.relrowsecurity,n.nspname from pg_catalog.pg_class c
 join pg_catalog.pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private') and c.relkind in ('r','p')
), routines as (
 select p.oid,p.prosecdef,p.proconfig,n.nspname from pg_catalog.pg_proc p
 join pg_catalog.pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private')
)
select jsonb_build_object(
 'version',1,
 'checked_at',pg_catalog.now(),
 'tables_checked',(select count(*) from tables),
 'tables_without_rls',(select count(*) from tables where not relrowsecurity),
 'private_client_grants',(select count(*) from tables where nspname='private' and (
   pg_catalog.has_table_privilege('anon',oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
   or pg_catalog.has_table_privilege('authenticated',oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))),
 'public_client_definers',(select count(*) from routines where nspname='public' and prosecdef and (
   pg_catalog.has_function_privilege('anon',oid,'EXECUTE') or
   pg_catalog.has_function_privilege('authenticated',oid,'EXECUTE'))),
 'definers_without_fixed_search_path',(select count(*) from routines where prosecdef and
   not exists(select 1 from pg_catalog.unnest(proconfig) cfg where cfg like 'search_path=%')),
 'client_views_without_invoker',(select count(*) from pg_catalog.pg_class c
   join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v'
   and (pg_catalog.has_table_privilege('anon',c.oid,'SELECT') or pg_catalog.has_table_privilege('authenticated',c.oid,'SELECT'))
   and not coalesce(c.reloptions @> array['security_invoker=true'],false)),
 'unrestricted_sensitive_policies',(select count(*) from pg_catalog.pg_policies p
   where p.schemaname='public' and p.tablename in ('profiles','calendar_entries','notifications','user_roles','terms_acceptances')
   and p.permissive='PERMISSIVE' and (
     (p.cmd in ('SELECT','DELETE','ALL','UPDATE') and p.qual in ('true','(true)'))
     or (p.cmd in ('INSERT','UPDATE','ALL') and p.with_check in ('true','(true)'))))
);
$$;
revoke all on function private.weekly_security_snapshot() from public,anon,authenticated;
grant execute on function private.weekly_security_snapshot() to service_role;
create or replace function public.weekly_security_snapshot()
returns jsonb language sql stable security invoker set search_path = '' as $$
 select private.weekly_security_snapshot();
$$;
revoke all on function public.weekly_security_snapshot() from public,anon,authenticated;
grant execute on function public.weekly_security_snapshot() to service_role;
