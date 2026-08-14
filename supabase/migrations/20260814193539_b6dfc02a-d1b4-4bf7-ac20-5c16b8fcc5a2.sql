DO $do$
DECLARE v_src text; v_old text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r8_channel';

  v_old := $q$          (v_det->>'orderable')::boolean = false AND v_det->>'blocked_reason' = 'RESTAURANT_CLOSED',
          coalesce(v_det->>'blocked_reason','null'));$q$;
  IF position(v_old in v_src) = 0 THEN RAISE EXCEPTION 'ANCHOR1_MISSING'; END IF;
  v_src := replace(v_src, v_old,
    $q$          (v_det->>'orderable')::boolean = false
          AND (v_det->>'restaurant_open')::boolean = false
          AND v_det->>'ineligible_reason' = 'RESTAURANT_CLOSED',
          coalesce(v_det->>'ineligible_reason','null'));$q$);

  v_old := 'FROM public.wallets WHERE user_id = v_cust';
  IF position(v_old in v_src) = 0 THEN RAISE EXCEPTION 'ANCHOR2_MISSING'; END IF;
  v_src := replace(v_src, v_old, 'FROM public.wallets WHERE owner_user_id = v_cust');

  EXECUTE v_src;
END
$do$;

INSERT INTO public._qa_s13_results(part, result)
SELECT 813, public._qa_node3_repas_r8_discovery_truth();