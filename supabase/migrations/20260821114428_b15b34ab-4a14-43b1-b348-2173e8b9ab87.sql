DO $mig$
DECLARE v_src text; v_new text;
BEGIN
  v_src := pg_get_functiondef('public._qa_node5_identity_a7()'::regprocedure);
  v_new := replace(v_src, 'merchant_settlement_requests WHERE store_id',
                          'merchant_settlement_requests WHERE merchant_store_id');
  IF v_new = v_src THEN RAISE EXCEPTION 'A7_QA_FIX_ANCHOR_MISSING'; END IF;
  EXECUTE v_new;
  IF pg_get_functiondef('public._qa_node5_identity_a7()'::regprocedure)
       LIKE '%merchant_settlement_requests WHERE store_id%' THEN
    RAISE EXCEPTION 'A7_QA_FIX_NOT_APPLIED';
  END IF;
END $mig$;