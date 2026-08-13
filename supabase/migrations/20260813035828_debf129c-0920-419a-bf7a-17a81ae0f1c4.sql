
DO $mig$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node1_bonbonna_matrix';
  v_src := replace(v_src,
    'public.customer_cancellation_debts WHERE user_id = v_cust',
    'public.customer_cancellation_debts WHERE customer_user_id = v_cust');
  EXECUTE v_src;
END $mig$;
