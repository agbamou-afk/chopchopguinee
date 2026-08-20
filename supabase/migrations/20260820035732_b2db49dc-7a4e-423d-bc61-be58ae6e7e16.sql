DO $mig$
DECLARE
  d text;
  o1 text; n1 text; o2 text; n2 text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = '_qa_node4_marche_r10';
  IF d IS NULL THEN RAISE EXCEPTION 'R10_HARNESS_NOT_FOUND'; END IF;

  o1 := $old$    UPDATE public.marketplace_listings
       SET staple_variant_id = v_var, staple_purchase_option_id = v_opt
     WHERE id IN (la,lb,lc,ld,le,lf,lz1,lz2,lz3,lz4,lz5,lag,lst);$old$;

  n1 := $new$    UPDATE public.marketplace_listings
       SET staple_variant_id = v_var, staple_purchase_option_id = v_opt
     WHERE id IN (la,lb,lc,ld,le,lf,lz1,lz2,lz3,lz4,lz5);
    -- Aged/stale fixtures map the VARIANT ONLY: assigning a purchase option would fire the
    -- frozen R8 merchant-ask trigger and manufacture a fresh observation, which is exactly
    -- the contamination that made the previous freshness assertions vacuous.
    UPDATE public.marketplace_listings
       SET staple_variant_id = v_var
     WHERE id IN (lag,lst);$new$;

  o2 := $old$    r := r || public._qa_s13_ok('N4R10.D2 a listing is never benchmarked against itself',
      (cmp->>'self_excluded')::boolean AND (cmp->>'sample_count')::int = 5, cmp#>>'{}');
    r := r || public._qa_s13_ok('N4R10.D3 a price cohort never mixes two different zones',
      cmp->>'cohort_zone_commune' = 'QA-N410-ZONE-A'
      AND (cmp->>'sample_count')::int = 5, cmp#>>'{}');$old$;

  n2 := $new$    -- Zone-A peers of `la`: lb..lf (5 fresh asks) + lag (100h, inside the 168h lookback) = 6.
    -- `lst` (400h) is outside the lookback and MUST be excluded; `la` itself is self-excluded.
    r := r || public._qa_s13_ok('N4R10.D2 a listing is never benchmarked against itself',
      (cmp->>'self_excluded')::boolean AND (cmp->>'sample_count')::int = 6, cmp#>>'{}');
    r := r || public._qa_s13_ok('N4R10.D3 a price cohort never mixes two different zones',
      cmp->>'cohort_zone_commune' = 'QA-N410-ZONE-A'
      AND (cmp->>'sample_count')::int = 6, cmp#>>'{}');
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations o
     WHERE o.variant_id = v_var AND o.zone_commune = 'QA-N410-ZONE-A'
       AND o.comparable AND o.superseded_by IS NULL;
    r := r || public._qa_s13_ok('N4R10.D3b an out-of-lookback stale ask is excluded from the cohort',
      v_n = 8 AND (cmp->>'sample_count')::int = 6, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE listing_id IN (lag,lst);
    r := r || public._qa_s13_ok('N4R10.D3c the aged fixtures carry exactly one backdated observation each',
      v_n = 2, v_n::text);$new$;

  IF position(o1 in d) = 0 THEN RAISE EXCEPTION 'R10_FIXTURE_ANCHOR_1_NOT_FOUND'; END IF;
  IF position(o2 in d) = 0 THEN RAISE EXCEPTION 'R10_FIXTURE_ANCHOR_2_NOT_FOUND'; END IF;

  d := replace(d, o1, n1);
  d := replace(d, o2, n2);

  EXECUTE d;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r10() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r10() TO service_role;