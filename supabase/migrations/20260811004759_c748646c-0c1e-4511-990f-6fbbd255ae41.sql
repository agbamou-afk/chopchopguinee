-- DEF-FIN-S6-002 — participant wrappers must never be anon-executable.
DROP FUNCTION IF EXISTS public.package_delivery_create_checkout(
  uuid,text,text,text,text,text,text,text,boolean,uuid);

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname IN ('package_delivery_cancel','package_delivery_quote',
                         'package_delivery_cancel_preview','package_delivery_courier_view',
                         'package_delivery_create_checkout','package_evidence_register',
                         'package_claim_open','package_verify_pickup','package_verify_delivery')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END $$;

-- Harness corrections: ledger_journals has `action`, and table grants must be read
-- from the catalog ACL (information_schema is filtered by the current role).
CREATE OR REPLACE FUNCTION public._qa_s6_t2(p_pkg uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT count(*) FROM public.ledger_journals
   WHERE source_module='package' AND source_id=p_pkg AND action='capture_customer_delivery';
$$;
REVOKE ALL ON FUNCTION public._qa_s6_t2(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s6_l4()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(string_agg(DISTINCT c.relname||':'||a.grantee::regrole::text||':'||a.privilege_type, ', '), '')
    FROM pg_class c, aclexplode(c.relacl) a
   WHERE c.relnamespace = 'public'::regnamespace
     AND c.relname IN ('package_evidence_photos','package_runtime')
     AND a.grantee::regrole::text IN ('authenticated','anon')
     AND a.privilege_type <> 'SELECT';
$$;
REVOKE ALL ON FUNCTION public._qa_s6_l4() FROM PUBLIC, anon, authenticated;