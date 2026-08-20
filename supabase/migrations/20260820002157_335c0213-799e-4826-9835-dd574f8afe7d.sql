ALTER FUNCTION public._qa_node4_marche_r8() RENAME TO _qa_node4_marche_r8_core;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r8_j()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_n bigint; v_res jsonb; v_j jsonb; v_obs0 bigint;
  v_mer uuid := gen_random_uuid(); v_com uuid; v_v1 uuid; v_o1 uuid;
  v_store uuid; v_list uuid; v_list2 uuid; v_t1 timestamptz; v_t2 timestamptz; v_t3 timestamptz;
BEGIN
  SELECT count(*) INTO v_obs0 FROM public.marche_procurement_price_observations;

  BEGIN
    -- ============ J. MERCHANT ASK EFFECTIVE-EVENT IDENTITY ============
    PERFORM public._qa_s13_user(v_mer, 'r8jmer');
    INSERT INTO public.marche_staple_categories(code, name_fr) VALUES ('qa_r8j_cat','QA R8J')
      ON CONFLICT (code) DO NOTHING;
    INSERT INTO public.marche_staple_commodities(code, category_code, name_fr, unit_family)
      VALUES ('qa_r8j_riz','qa_r8j_cat','QA R8J Riz','mass') RETURNING id INTO v_com;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v1','QA R8J V1') RETURNING id INTO v_v1;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v1,'o1','kg','Sac 1kg','exact','kg',1,1,50,1) RETURNING id INTO v_o1;
    INSERT INTO public.merchant_stores(owner_user_id, name, slug, status, onboarding_status, commune, verification_state)
      VALUES (v_mer,'QA R8J Store','qa-r8j-store','active','approved','Matam','none') RETURNING id INTO v_store;

    -- J1: initial published ask 11 000
    INSERT INTO public.marketplace_listings(seller_id, store_id, kind, category, title,
        asking_price_gnf, price_gnf, status, visibility, staple_purchase_option_id)
      VALUES (v_mer, v_store, 'merchant','Alimentation','QA R8J Riz 1kg', 11000, 11000,
              'active','public', v_o1) RETURNING id INTO v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J1 initial published 11 000 ask yields exactly one observation',
      v_n = 1, v_n::text);

    -- J2/J3: change to 13 000
    UPDATE public.marketplace_listings SET asking_price_gnf = 13000, price_gnf = 13000 WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J2 change to 13 000 adds a second observation', v_n = 2, v_n::text);
    r := r || public._qa_s13_ok('N4R8.J3 the first 11 000 fact is preserved, not rewritten',
      (SELECT count(*) FROM public.marche_procurement_price_observations
        WHERE listing_id=v_list AND raw_amount_gnf=11000) = 1, NULL);

    -- J4..J7: change BACK to 11 000 -> genuinely new event
    UPDATE public.marketplace_listings SET asking_price_gnf = 11000, price_gnf = 11000 WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J4 returning to a previous price creates a THIRD observation',
      v_n = 3, v_n::text);
    r := r || public._qa_s13_ok('N4R8.J5 both prior facts survive the return to 11 000',
      (SELECT count(*) FROM public.marche_procurement_price_observations
        WHERE listing_id=v_list AND raw_amount_gnf=11000) = 2
      AND (SELECT count(*) FROM public.marche_procurement_price_observations
        WHERE listing_id=v_list AND raw_amount_gnf=13000) = 1, NULL);
    SELECT count(DISTINCT source_ref) INTO v_n FROM public.marche_procurement_price_observations
      WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J6 each effective event carries a distinct source identity',
      v_n = 3, v_n::text);
    SELECT count(DISTINCT observed_at) INTO v_n FROM public.marche_procurement_price_observations
      WHERE listing_id = v_list;
    SELECT max(observed_at) INTO v_t3 FROM public.marche_procurement_price_observations WHERE listing_id=v_list;
    SELECT observed_at INTO v_t1 FROM public.marche_procurement_price_observations
      WHERE listing_id=v_list AND raw_amount_gnf=13000;
    r := r || public._qa_s13_ok('N4R8.J7 newest observed_at is strictly later than the 13 000 event',
      v_n = 3 AND v_t3 > v_t1
      AND (SELECT raw_amount_gnf FROM public.marche_procurement_price_observations
            WHERE listing_id=v_list ORDER BY observed_at DESC LIMIT 1) = 11000, NULL);

    -- J8: replay / retry of the same effective event
    v_res := public.marche_price_ingest_merchant_ask(v_list);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J8 replay of the same effective event stays idempotent',
      v_n = 3 AND (v_res->>'ingested')::boolean IS FALSE AND v_res->>'reason' = 'ALREADY_OBSERVED',
      v_res::text);

    -- J9/J10: unrelated update + idle re-save
    UPDATE public.marketplace_listings SET description = 'QA R8J note' WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J9 unrelated listing update creates no price observation',
      v_n = 3, v_n::text);
    UPDATE public.marketplace_listings SET asking_price_gnf = 11000, price_gnf = 11000 WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J10 same-value idle re-save creates no duplicate', v_n = 3, v_n::text);

    -- J11: trigger discipline is declared, not accidental
    r := r || public._qa_s13_ok('N4R8.J11 ask trigger is narrowed to ask-relevant columns',
      NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.marketplace_listings'::regclass
                   AND tgname='trg_marche_price_merchant_ask' AND NOT tgisinternal)
      AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.marketplace_listings'::regclass
                   AND tgname='trg_marche_price_merchant_ask_upd' AND NOT tgisinternal)
      AND pg_get_triggerdef((SELECT oid FROM pg_trigger WHERE tgrelid='public.marketplace_listings'::regclass
                              AND tgname='trg_marche_price_merchant_ask_upd')) LIKE '%WHEN%asking_price_gnf%', NULL);

    -- J12/J13: unpublish -> republish at the same price stays one logical event
    UPDATE public.marketplace_listings SET status = 'paused' WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J12 unpublishing observes nothing new', v_n = 3, v_n::text);
    UPDATE public.marketplace_listings SET status = 'active' WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J13 republishing an unchanged ask is idempotent, not a new event',
      v_n = 3, v_n::text);

    -- J14: re-exposure after a price change while unpublished is a real new event
    UPDATE public.marketplace_listings SET status = 'paused' WHERE id = v_list;
    UPDATE public.marketplace_listings SET asking_price_gnf = 15000, price_gnf = 15000 WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J14 price change while unpublished observes nothing',
      v_n = 3, v_n::text);
    UPDATE public.marketplace_listings SET status = 'active' WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.J15 becoming observable again at a new price records it once',
      v_n = 4
      AND (SELECT raw_amount_gnf FROM public.marche_procurement_price_observations
            WHERE listing_id=v_list ORDER BY observed_at DESC LIMIT 1) = 15000, v_n::text);

    -- J16: storeless / ineligible supply stays excluded
    INSERT INTO public.marketplace_listings(seller_id, kind, category, title, asking_price_gnf,
        status, visibility, staple_purchase_option_id)
      VALUES (v_mer,'community','Alimentation','QA R8J communautaire', 9000,'active','public', v_o1)
      RETURNING id INTO v_list2;
    v_res := public.marche_price_ingest_merchant_ask(v_list2);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list2;
    r := r || public._qa_s13_ok('N4R8.J16 storeless community supply is still refused',
      v_res->>'reason' = 'MERCHANT_STORE_REQUIRED' AND v_n = 0, v_res::text);

    -- J17: public cohort sees every valid effective observation
    v_j := public.marche_price_observed_public('qa_r8j_riz','Matam');
    r := r || public._qa_s13_ok('N4R8.J17 public cohort counts all effective merchant-ask events',
      (SELECT (c->>'sample_count')::int FROM jsonb_array_elements(v_j->'cohorts') c LIMIT 1) = 4,
      v_j::text);
    r := r || public._qa_s13_ok('N4R8.J18 public cohort leaks no provenance identity',
      v_j::text NOT ILIKE '%source_ref%' AND v_j::text NOT LIKE '%'||v_list::text||'%', NULL);

    RAISE EXCEPTION 'QA_N4R8J_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R8J_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_R8J_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations;
  r := r || public._qa_s13_ok('N4R8.J19 zero observation fixture residue', v_n = v_obs0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA R8J%';
  r := r || public._qa_s13_ok('N4R8.J20 zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code='qa_r8j_riz';
  r := r || public._qa_s13_ok('N4R8.J21 zero catalog fixture residue', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(1018, r);
END $function$;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r8()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE a jsonb; b jsonb;
BEGIN
  a := public._qa_node4_marche_r8_core();
  b := public._qa_node4_marche_r8_j();
  RETURN jsonb_build_object(
    'part', 101,
    'total', (a->>'total')::int + (b->>'total')::int,
    'passed', (a->>'passed')::int + (b->>'passed')::int,
    'failed', (a->>'failed')::int + (b->>'failed')::int,
    'failures', (a->'failures') || (b->'failures'));
END $function$;