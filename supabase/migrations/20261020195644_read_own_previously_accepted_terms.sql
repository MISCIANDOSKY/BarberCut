create policy own_accepted_terms_read on public.terms_versions for select to authenticated
using(exists(select 1 from public.terms_acceptances a where a.terms_id=terms_versions.id and a.user_id=(select auth.uid())));
