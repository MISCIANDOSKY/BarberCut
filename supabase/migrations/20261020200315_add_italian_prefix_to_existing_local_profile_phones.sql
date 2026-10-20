with normalized as (
 select id,phone,
 case when regexp_replace(btrim(phone),'[^0-9]','','g') ~ '^00' then '+'||substr(regexp_replace(btrim(phone),'[^0-9]','','g'),3)
 when regexp_replace(btrim(phone),'[^0-9]','','g') ~ '^39[0-9]{10}$' then '+'||regexp_replace(btrim(phone),'[^0-9]','','g')
 else '+39'||regexp_replace(btrim(phone),'[^0-9]','','g') end as full_phone
 from public.profiles
 where btrim(coalesce(phone,''))<>'' and btrim(phone) !~ '^\+' and phone !~ '[A-Za-z]'
), changed as (
 update public.profiles p set phone=n.full_phone from normalized n where p.id=n.id and p.phone=n.phone and n.full_phone<>'+39' and n.full_phone<>'+' returning p.id,p.phone
)
update auth.users a set raw_user_meta_data=jsonb_set(coalesce(a.raw_user_meta_data,'{}'::jsonb),'{phone}',to_jsonb(c.phone))
from changed c where a.id=c.id;
