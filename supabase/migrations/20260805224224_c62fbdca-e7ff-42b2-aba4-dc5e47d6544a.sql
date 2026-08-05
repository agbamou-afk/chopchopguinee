REVOKE ALL ON FUNCTION public.driver_balance_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_balance_summary(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.finance_mission_requirement(text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_mission_requirement(text, bigint) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.finance_mission_requirement_v2(text, bigint, bigint, bigint, bigint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_mission_requirement_v2(text, bigint, bigint, bigint, bigint, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.finance_policy_current(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_policy_current(text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public._ledger_assert_balanced() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._ledger_assert_journal_complete() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._ledger_immutable() FROM PUBLIC, anon, authenticated;

DO $g$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname LIKE 'driver_financial_eligibility%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END $g$;