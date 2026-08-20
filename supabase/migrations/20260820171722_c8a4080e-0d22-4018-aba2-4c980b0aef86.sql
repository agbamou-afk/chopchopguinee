select public._qa_users_purge(array(
  select p.user_id from public.profiles p
  where not exists (select 1 from auth.users u where u.id = p.user_id)
    and p.created_at >= '2026-08-20 17:00:00+00'
    and (p.email like '%@qa.invalid' or p.email like 'demo.qa-%@chopchop.gn')
));