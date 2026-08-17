CREATE OR REPLACE FUNCTION public._marche_procurement_evidence_can_read(p_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public._finance_privileged(auth.uid()) OR EXISTS (
    SELECT 1 FROM public.marche_procurement_missions m
    WHERE p_name LIKE m.request_id::text || '/%'
      AND (m.shopper_user_id = auth.uid() OR m.buyer_user_id = auth.uid())
  )
$$;

CREATE OR REPLACE FUNCTION public._marche_procurement_evidence_can_write(p_name text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.marche_procurement_missions m
    WHERE m.shopper_user_id = auth.uid()
      AND m.state IN ('at_market','shopping')
      AND p_name LIKE m.request_id::text || '/%'
  )
$$;

REVOKE ALL ON FUNCTION public._marche_procurement_evidence_can_read(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._marche_procurement_evidence_can_write(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._marche_procurement_evidence_can_read(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._marche_procurement_evidence_can_write(text) TO authenticated, service_role;

DROP POLICY IF EXISTS "marche procurement evidence: private authenticated reads" ON storage.objects;
DROP POLICY IF EXISTS "marche procurement evidence: shopper writes own mission" ON storage.objects;

CREATE POLICY "marche procurement evidence: private authenticated reads"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'marche-procurement-evidence'
       AND public._marche_procurement_evidence_can_read(name));

CREATE POLICY "marche procurement evidence: shopper writes own mission"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'marche-procurement-evidence'
       AND public._marche_procurement_evidence_can_write(name));

DO $mig$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node4_marche_r65';
  d := replace(d,
    'OR column_name LIKE ''%delivery%''',
    'OR (column_name LIKE ''%delivery%'' AND column_name NOT LIKE ''%\_at'')');
  EXECUTE d;
END $mig$;