-- Fix 1: cockpit must stay strictly read-only (no temp table in a STABLE function).
CREATE OR REPLACE FUNCTION public.marche_merchant_orders_cockpit(
  p_store_id uuid DEFAULT NULL,
  p_bucket text DEFAULT NULL,
  p_limit int DEFAULT 40,
  p_offset int DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  v_priv boolean := public._finance_privileged(caller);
  v_limit int := LEAST(GREATEST(COALESCE(p_limit,40),1),100);
  v_offset int := GREATEST(COALESCE(p_offset,0),0);
  v_counts jsonb;
  v_items jsonb;
BEGIN
  IF caller IS NULL AND NOT v_priv THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_bucket IS NOT NULL AND p_bucket NOT IN
     ('action_required','preparing','in_delivery','completed','cancelled') THEN
    RAISE EXCEPTION 'UNKNOWN_BUCKET' USING DETAIL = p_bucket;
  END IF;

  WITH scoped AS (
    SELECT o.* FROM public.marche_orders o
     WHERE (p_store_id IS NULL OR o.merchant_store_id = p_store_id)
       AND public._marche_merchant_ops_authorized(o, caller)
  )
  SELECT jsonb_object_agg(b, n) INTO v_counts FROM (
    SELECT public._marche_order_ops_bucket(s.*) AS b, count(*) AS n
      FROM scoped s GROUP BY 1) q(b,n);

  WITH scoped AS (
    SELECT o.* FROM public.marche_orders o
     WHERE (p_store_id IS NULL OR o.merchant_store_id = p_store_id)
       AND public._marche_merchant_ops_authorized(o, caller)
  ), filtered AS (
    SELECT s.* FROM scoped s
     WHERE p_bucket IS NULL OR public._marche_order_ops_bucket(s.*) = p_bucket
     ORDER BY s.created_at DESC, s.id DESC
     LIMIT v_limit OFFSET v_offset
  )
  SELECT COALESCE(jsonb_agg(public.marche_merchant_order_ops(f.id)
                            ORDER BY f.created_at DESC, f.id DESC), '[]'::jsonb)
    INTO v_items FROM filtered f;

  RETURN jsonb_build_object(
    'counts', COALESCE(v_counts, '{}'::jsonb),
    'bucket', p_bucket,
    'items', COALESCE(v_items, '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION public.marche_merchant_orders_cockpit(uuid,text,int,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_merchant_orders_cockpit(uuid,text,int,int) TO authenticated, service_role;

-- Fix 2: assertion A8 must state the frozen Slice 11 access law, not a stricter fiction.
CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11_a8()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public._qa_s13_ok('N4R11.A8 finance tables stay signed-out-proof and client-read-only',
    NOT has_table_privilege('anon','public.merchant_payables','SELECT')
    AND NOT has_table_privilege('anon','public.payout_settlement_allocations','SELECT')
    AND NOT has_table_privilege('authenticated','public.merchant_payables','UPDATE')
    AND NOT has_table_privilege('authenticated','public.merchant_payables','INSERT')
    AND NOT has_table_privilege('authenticated','public.payout_settlement_allocations','INSERT')
    AND NOT has_table_privilege('authenticated','public.payout_settlement_allocations','UPDATE')
    AND NOT EXISTS (SELECT 1 FROM pg_policies
                     WHERE tablename IN ('merchant_payables','payout_settlement_allocations')
                       AND cmd <> 'SELECT'), NULL)
$$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r11_a8() FROM PUBLIC, anon, authenticated;
