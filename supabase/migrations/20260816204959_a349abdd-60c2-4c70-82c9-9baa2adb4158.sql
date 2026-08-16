-- 1) Derivation authority: one-shot, row-bound internal token; guard now covers INSERT.
CREATE OR REPLACE FUNCTION public.marche_fulfillment_observation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_tok text;
BEGIN
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'FULFILLMENT_OBSERVATION_DERIVED_ONLY'; END IF;
  v_tok := COALESCE(current_setting('marche.fulfillment_derive_token', true), '');
  -- one-shot: authority is consumed by the very first row it authorizes
  PERFORM set_config('marche.fulfillment_derive_token', '', true);
  IF v_tok = '' OR v_tok IS DISTINCT FROM (NEW.order_id::text || ':' || NEW.metric_name) THEN
    RAISE EXCEPTION 'FULFILLMENT_OBSERVATION_DERIVED_ONLY';
  END IF;
  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_marche_fulfillment_observation_guard ON public.marche_fulfillment_observations;
CREATE TRIGGER trg_marche_fulfillment_observation_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.marche_fulfillment_observations
  FOR EACH ROW EXECUTE FUNCTION public.marche_fulfillment_observation_guard();

CREATE OR REPLACE FUNCTION public.marche_fulfillment_recompute_observations(p_order_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  p public.marche_fulfillment_profiles;
  m record; v_start timestamptz; v_end timestamptz; v_n int := 0;
BEGIN
  SELECT * INTO p FROM public.marche_fulfillment_profiles WHERE order_id = p_order_id;
  IF p.order_id IS NULL THEN RETURN 0; END IF;

  FOR m IN
    SELECT * FROM (VALUES
      ('COMMIT_TO_MERCHANT_ACCEPTED','ORDER_COMMITTED','MERCHANT_ACCEPTED'),
      ('MERCHANT_ACCEPTED_TO_READY','MERCHANT_ACCEPTED','MERCHANT_READY'),
      ('COURIER_ENGAGED_TO_STORE_ARRIVAL','COURIER_ENGAGED','COURIER_AT_STORE'),
      ('SHOPPING_START_TO_COMPLETE','SHOPPING_STARTED','SHOPPING_COMPLETED'),
      ('PICKUP_TO_DELIVERED','PICKED_UP','DELIVERED'),
      ('COMMIT_TO_DELIVERED','ORDER_COMMITTED','DELIVERED')
    ) AS v(metric, s_evt, e_evt)
  LOOP
    SELECT min(occurred_at) INTO v_start FROM public.marche_fulfillment_events
      WHERE order_id = p_order_id AND event_type = m.s_evt;
    SELECT min(occurred_at) INTO v_end FROM public.marche_fulfillment_events
      WHERE order_id = p_order_id AND event_type = m.e_evt;
    -- both endpoints required; impossible negative intervals are refused, never clamped
    CONTINUE WHEN v_start IS NULL OR v_end IS NULL OR v_end < v_start;
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                           WHERE order_id = p_order_id AND metric_name = m.metric);

    BEGIN
      PERFORM set_config('marche.fulfillment_derive_token', p_order_id::text || ':' || m.metric, true);
      INSERT INTO public.marche_fulfillment_observations(
        order_id, metric_name, duration_seconds, start_event_at, end_event_at,
        merchant_store_id, fulfillment_mode, distance_m, distance_bucket,
        basket_units, distinct_products, basket_bucket, observed_at)
      VALUES (p_order_id, m.metric, floor(EXTRACT(EPOCH FROM (v_end - v_start)))::bigint, v_start, v_end,
        p.merchant_store_id, p.fulfillment_mode, p.distance_m, public.marche_distance_bucket(p.distance_m),
        p.basket_units, p.distinct_products, public.marche_basket_bucket(p.basket_units, p.distinct_products),
        v_end)
      ON CONFLICT (order_id, metric_name) DO NOTHING;
      PERFORM set_config('marche.fulfillment_derive_token', '', true);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('marche.fulfillment_derive_token', '', true);
      RAISE;
    END;
    v_n := v_n + 1;
  END LOOP;
  PERFORM set_config('marche.fulfillment_derive_token', '', true);
  RETURN v_n;
END $fn$;

REVOKE ALL ON FUNCTION public.marche_fulfillment_recompute_observations(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_recompute_observations(uuid) TO service_role;