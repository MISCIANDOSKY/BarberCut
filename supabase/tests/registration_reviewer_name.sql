begin;
update public.app_settings set require_user_approval=true where id;
do $test$
declare
 ad uuid:=gen_random_uuid(); barber_user uuid:=gen_random_uuid(); approved_user uuid:=gen_random_uuid(); rejected_user uuid:=gen_random_uuid(); pending_user uuid:=gen_random_uuid(); agenda uuid; record jsonb;
begin
 insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
 (ad,'review-name-admin@example.invalid',now(),'{"first_name":"Test","last_name":"Amministratore"}'),
 (barber_user,'review-name-barber@example.invalid',now(),'{"first_name":"Test","last_name":"Collaboratore"}'),
 (approved_user,'review-name-approved@example.invalid',now(),'{"first_name":"Approved","last_name":"Client"}'),
 (rejected_user,'review-name-rejected@example.invalid',now(),'{"first_name":"Rejected","last_name":"Client"}'),
 (pending_user,'review-name-pending@example.invalid',now(),'{"first_name":"Pending","last_name":"Client"}');
 update public.user_roles set role='admin' where user_id=ad;
 insert into public.barbers(name,user_id,can_approve_clients) values('Review name barber',barber_user,true) returning id into agenda;
 perform public.staff_authorize_session(ad,'review-name-admin');
 perform public.staff_authorize_session(barber_user,'review-name-barber');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',ad,'role','authenticated','session_id','review-name-admin')::text,true);
 set local role authenticated;
 perform public.review_registration(approved_user,'approved');
 select v into record from jsonb_array_elements(public.list_registration_requests('approved')) v where v->>'user_id'=approved_user::text;
 if record->>'reviewed_by_name' is distinct from 'Test Amministratore' then raise exception 'Approver name missing';end if;
 select v into record from jsonb_array_elements(public.list_registration_requests('pending')) v where v->>'user_id'=pending_user::text;
 if record is null or record->>'reviewed_by_name' is not null then raise exception 'Pending attribution invented';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',barber_user,'role','authenticated','session_id','review-name-barber')::text,true);
 set local role authenticated;
 perform public.review_registration(rejected_user,'rejected');
 select v into record from jsonb_array_elements(public.list_registration_requests('rejected')) v where v->>'user_id'=rejected_user::text;
 if record->>'reviewed_by_name' is distinct from 'Test Collaboratore' then raise exception 'Rejector name missing';end if;
 -- Both staff roles can see the recorded reviewer.
 select v into record from jsonb_array_elements(public.list_registration_requests('approved')) v where v->>'user_id'=approved_user::text;
 if record->>'reviewed_by_name' is distinct from 'Test Amministratore' then raise exception 'Staff approver name missing';end if;
 reset role;
 update public.profiles set first_name='',last_name='' where id=ad;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',barber_user,'role','authenticated','session_id','review-name-barber')::text,true);
 set local role authenticated;
 select v into record from jsonb_array_elements(public.list_registration_requests('approved')) v where v->>'user_id'=approved_user::text;
 if record is null or record->>'reviewed_by_name' is not null then raise exception 'Missing name fallback invalid';end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',approved_user,'role','authenticated')::text,true);
 set local role authenticated;
 begin perform public.list_registration_requests('approved');raise exception 'Client reviewer list access';exception when raise_exception then if sqlerrm<>'ACCESS_DENIED' then raise;end if;end;
 reset role;
end $test$;
rollback;
