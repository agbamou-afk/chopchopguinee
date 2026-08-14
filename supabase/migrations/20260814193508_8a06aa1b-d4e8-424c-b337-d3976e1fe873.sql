DO $do$
DECLARE v_src text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r8_channel';

  v_old := $q$    BEGIN
      PERFORM public.repas_quote_preview(v_closed,
        jsonb_build_array(jsonb_build_object('menu_item_id',
          (SELECT id FROM public.food_menu_items WHERE restaurant_id=v_closed LIMIT 1), 'qty', 1)),
        'pickup', NULL, NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C6.2 quote refuses a closed restaurant', v_err <> 'NO_ERROR', v_err);$q$;

  v_new := $q$    v_det := public.repas_quote_preview(v_closed,
        jsonb_build_array(jsonb_build_object('menu_item_id',
          (SELECT id FROM public.food_menu_items WHERE restaurant_id=v_closed LIMIT 1), 'qty', 1)),
        'pickup', NULL, NULL);
    r := r || public._qa_s13_ok('C6.2 quote marks a closed restaurant as not orderable',
          (v_det->>'orderable')::boolean = false AND v_det->>'blocked_reason' = 'RESTAURANT_CLOSED',
          coalesce(v_det->>'blocked_reason','null'));
    BEGIN
      PERFORM public.repas_order_create(v_closed,
        jsonb_build_array(jsonb_build_object('menu_item_id',
          (SELECT id FROM public.food_menu_items WHERE restaurant_id=v_closed LIMIT 1), 'qty', 1)),
        'pickup', 'cash', NULL, NULL, NULL, gen_random_uuid()::text);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C6.2b order placement refuses a closed restaurant',
          v_err <> 'NO_ERROR', v_err);$q$;

  IF position(v_old in v_src) = 0 THEN RAISE EXCEPTION 'C6_PATCH_ANCHOR_MISSING'; END IF;
  v_src := replace(v_src, v_old, v_new);

  v_old := $q$    SELECT count(*) INTO v_n FROM public.food_orders WHERE customer_id = v_cust;$q$;
  IF position(v_old in v_src) = 0 THEN RAISE EXCEPTION 'C8_PATCH_ANCHOR_MISSING'; END IF;
  v_src := replace(v_src, v_old,
    $q$    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id = v_cust;$q$);

  EXECUTE v_src;
END
$do$;

INSERT INTO public._qa_s13_results(part, result)
SELECT 813, public._qa_node3_repas_r8_discovery_truth();