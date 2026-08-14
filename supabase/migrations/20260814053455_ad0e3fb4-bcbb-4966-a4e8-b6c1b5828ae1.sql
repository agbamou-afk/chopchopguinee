DO $mig$
DECLARE s text; s0 text; b text;
BEGIN
  b := 'jsonb_build_object(''base'',v_fo.base_delivery_fee_gnf,''cust'',v_fo.delivery_fee_gnf,'
    || '''disc'',v_fo.promo_discount_gnf,''promo'',v_fo.promotion_id,''payout'',v_fo.courier_payout_gnf,'
    || '''fee'',v_fo.platform_fee_gnf,''total'',v_fo.order_total_gnf,''policy'',v_fo.pricing_policy_id,'
    || '''dist'',v_fo.delivery_distance_km)';

  SELECT pg_get_functiondef(p.oid) INTO s FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r5_runtime';
  s0 := s;
  s := replace(s, E'v_snap4 := to_jsonb(v_fo) - \'updated_at\' - \'state\';', 'v_snap4 := ' || b || ';');
  IF s = s0 THEN RAISE EXCEPTION 'p1'; END IF; s0 := s;
  s := replace(s, E'(to_jsonb(v_fo) - \'updated_at\' - \'state\') = v_snap4', b || ' = v_snap4');
  IF s = s0 THEN RAISE EXCEPTION 'p2'; END IF;
  EXECUTE s;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r5_runtime() FROM PUBLIC, anon, authenticated;

DELETE FROM public._qa_s13_results WHERE part = 351;
INSERT INTO public._qa_s13_results(part, result)
VALUES (351, public._qa_node3_repas_r5_runtime());