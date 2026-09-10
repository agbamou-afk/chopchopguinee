DO $do$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def FROM pg_proc
   WHERE proname='_qa_node5_identity_a11' AND pronamespace='public'::regnamespace;
  def := replace(def,
$old$  r := r || public._qa_s13_ok('N5A11.A13 admin_users mutation policy is super-admin scoped',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='admin_users'
                 AND cmd='ALL' AND COALESCE(qual,'') ~ 'has_admin_role'
                 AND COALESCE(with_check,'') ~ 'has_admin_role'), NULL);$old$,
$new$  -- G6 supersedes the former super-admin-scoped mutation policy with a
  -- strictly stronger posture: no session role holds any write privilege on
  -- admin_users at all, and no non-SELECT policy exists. Staff identity moves
  -- only through the governed lifecycle server actions.
  r := r || public._qa_s13_ok('N5A11.A13 admin_users mutation is impossible from any session (G6)',
        NOT has_table_privilege('authenticated','public.admin_users','INSERT')
        AND NOT has_table_privilege('authenticated','public.admin_users','UPDATE')
        AND NOT has_table_privilege('authenticated','public.admin_users','DELETE')
        AND NOT has_table_privilege('anon','public.admin_users','INSERT')
        AND NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                         AND tablename='admin_users' AND cmd <> 'SELECT'), NULL);$new$);
  EXECUTE def;
END
$do$;