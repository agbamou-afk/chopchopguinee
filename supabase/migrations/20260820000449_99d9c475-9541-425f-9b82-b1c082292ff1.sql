DO $mig$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public._qa_node4_marche_r65()'::regprocedure) INTO d;

  d := replace(d,
    $old$'N4R65.A6 procurement rail carries no merchant/listing coupling column'$old$,
    $new$'N4R65.A6 procurement transaction rail carries no merchant/listing coupling column (R8 evidence stream excluded)'$new$);
  d := replace(d,
    $old$'N4R65.A7 procurement rail has no FK to marketplace_listings or merchant_stores'$old$,
    $new$'N4R65.A7 procurement transaction rail has no FK to marketplace_listings or merchant_stores (R8 evidence stream excluded)'$new$);

  d := replace(d,
    $old$AND column_name IN ('listing_id','store_id','merchant_store_id','merchant_user_id','offer_id','seller_id')), NULL);$old$,
    $new$AND table_name <> 'marche_procurement_price_observations'
          AND column_name IN ('listing_id','store_id','merchant_store_id','merchant_user_id','offer_id','seller_id')), NULL);$new$);

  d := replace(d,
    $old$AND c.confrelid IN ('public.marketplace_listings'::regclass,'public.merchant_stores'::regclass)), NULL);$old$,
    $new$AND t.relname <> 'marche_procurement_price_observations'
            AND c.confrelid IN ('public.marketplace_listings'::regclass,'public.merchant_stores'::regclass)), NULL);
  r := r || public._qa_s13_ok('N4R65.A6b R8 evidence stream links merchant supply for provenance only, never for procurement pricing',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_procurement_price_observations' AND column_name='listing_id')
        AND pg_get_functiondef('public._marche_procurement_option_estimate(uuid)'::regprocedure)
            NOT ILIKE '%marketplace_listings%'
        AND pg_get_functiondef('public._marche_procurement_option_estimate(uuid)'::regprocedure)
            NOT ILIKE '%merchant_stores%', NULL);$new$);

  EXECUTE d;
END $mig$;

DELETE FROM public._qa_r8_out;
INSERT INTO public._qa_r8_out(res) VALUES (jsonb_build_object('suite','r65','res', public._qa_node4_marche_r65()));
INSERT INTO public._qa_r8_out(res) VALUES (jsonb_build_object('suite','repas_r5_core','res', public._qa_node3_repas_r5_runtime_core()));
INSERT INTO public._qa_r8_out(res) VALUES (jsonb_build_object('suite','marche_r5','res', public._qa_node4_marche_r5()));