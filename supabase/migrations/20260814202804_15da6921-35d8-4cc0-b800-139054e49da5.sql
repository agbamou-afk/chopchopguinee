-- 1. Ops tables are RPC-only: strip any default-privilege leakage.
REVOKE ALL ON public.repas_ops_cases FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.repas_ops_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.repas_ops_cases TO service_role;
GRANT ALL ON public.repas_ops_events TO service_role;

-- 2. Attention flags: an order never accepted ages from creation, not from
--    updated_at (which the generic touch trigger keeps refreshing).
DROP FUNCTION IF EXISTS public._repas_ops_flags(text,text,timestamptz,text,uuid,text,boolean,boolean);

CREATE OR REPLACE FUNCTION public._repas_ops_flags(
  p_state text, p_fulfillment text, p_created timestamptz, p_updated timestamptz,
  p_mission_state text, p_courier uuid, p_engine_state text,
  p_disputed boolean, p_custody_locked boolean)
RETURNS text[] LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT ARRAY(SELECT f FROM (VALUES
    (CASE WHEN p_state = 'placed'
            AND p_created < now() - interval '10 minutes'
          THEN 'awaiting_merchant_accept' END),
    (CASE WHEN p_state IN ('confirmed','preparing')
            AND p_updated < now() - interval '45 minutes'
          THEN 'preparation_overdue' END),
    (CASE WHEN p_state = 'ready' AND p_fulfillment = 'delivery' AND p_courier IS NULL
            AND p_updated < now() - interval '20 minutes'
          THEN 'no_courier_assigned' END),
    (CASE WHEN p_state = 'ready' AND p_fulfillment = 'pickup'
            AND p_updated < now() - interval '90 minutes'
          THEN 'pickup_not_collected' END),
    (CASE WHEN p_state = 'out_for_delivery'
            AND p_updated < now() - interval '60 minutes'
          THEN 'delivery_overdue' END),
    (CASE WHEN p_mission_state = 'failed' THEN 'mission_failed' END),
    (CASE WHEN p_disputed THEN 'dispute_open' END),
    (CASE WHEN p_engine_state = 'disputed' THEN 'engine_disputed' END),
    (CASE WHEN p_custody_locked THEN 'custody_locked' END)
  ) t(f) WHERE f IS NOT NULL);
$$;

REVOKE ALL ON FUNCTION public._repas_ops_flags(text,text,timestamptz,timestamptz,text,uuid,text,boolean,boolean)
  FROM PUBLIC, anon, authenticated;

-- 3. allowed_actions: fix the text/array append and keep the same authority rules.
CREATE OR REPLACE FUNCTION public._repas_ops_allowed_actions(
  p_order_id uuid, p_uid uuid, p_role text)
RETURNS text[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_o public.food_orders%ROWTYPE;
  v_case public.repas_ops_cases%ROWTYPE;
  v_mission uuid; v_terminal boolean; v_fin boolean;
  v_pending text; v_disputed boolean; v_runtime boolean;
  a text[] := '{}';
BEGIN
  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RETURN a; END IF;
  SELECT * INTO v_case FROM public.repas_ops_cases
   WHERE food_order_id = p_order_id ORDER BY (status <> 'resolved') DESC, created_at DESC LIMIT 1;
  SELECT courier_id INTO v_mission FROM public.missions
   WHERE ref_food_order_id = p_order_id ORDER BY created_at DESC LIMIT 1;
  v_terminal := v_o.state::text IN ('completed','cancelled');
  v_fin := public._finance_privileged(p_uid);
  v_disputed := public._repas_custody_dispute_blocked(p_order_id);
  v_runtime := EXISTS (SELECT 1 FROM public.chop_pay_order_runtime
                        WHERE source_module='repas' AND source_id=p_order_id);
  SELECT kind INTO v_pending FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND consumed_at IS NULL
   ORDER BY created_at DESC LIMIT 1;

  IF v_case.id IS NULL OR v_case.status = 'resolved' THEN
    a := a || ARRAY['open_case'];
  END IF;
  IF v_case.id IS NOT NULL THEN
    a := a || ARRAY['add_note','contact_customer','contact_merchant'];
    IF v_mission IS NOT NULL THEN a := a || ARRAY['contact_courier']; END IF;
    IF v_case.status = 'open' THEN a := a || ARRAY['escalate']; END IF;
    IF v_case.status <> 'resolved' THEN a := a || ARRAY['resolve']; END IF;
    IF v_case.status = 'resolved' THEN a := a || ARRAY['reopen']; END IF;
  END IF;

  IF v_case.id IS NOT NULL AND v_case.status <> 'resolved' AND NOT v_terminal AND NOT v_disputed
     AND v_o.state::text = 'ready' AND v_pending IS NOT NULL THEN
    a := a || ARRAY['custody_reissue'];
  END IF;

  IF v_case.id IS NOT NULL AND v_case.status <> 'resolved' AND v_fin AND NOT v_terminal
     AND v_o.payment_method::text = 'choppay' AND v_runtime THEN
    a := a || ARRAY['cancel_order'];
  END IF;
  IF v_case.id IS NOT NULL AND v_case.status <> 'resolved' AND v_fin AND v_disputed THEN
    a := a || ARRAY['dispute_resolve'];
  END IF;
  RETURN a;
END; $$;

REVOKE ALL ON FUNCTION public._repas_ops_allowed_actions(uuid,uuid,text) FROM PUBLIC, anon, authenticated;

-- 4. Queue: pass both timestamps and expose total age + current-step age.
CREATE OR REPLACE FUNCTION public.repas_ops_queue(
  p_filter text DEFAULT 'attention',
  p_search text DEFAULT NULL,
  p_limit int DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  v_role := public._repas_ops_actor_role(v_uid);
  IF v_role IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_filter NOT IN ('attention','active','open','escalated','resolved','all') THEN
    RAISE EXCEPTION 'INVALID_FILTER' USING DETAIL = COALESCE(p_filter,'null');
  END IF;

  WITH base AS (
    SELECT
      fo.id, fo.state::text AS state, fo.fulfillment::text AS fulfillment,
      fo.payment_method::text AS tender, fo.order_total_gnf, fo.created_at, fo.updated_at,
      fo.client_request_id,
      r.id AS restaurant_id, r.name AS restaurant_name,
      m.id AS mission_id, m.state::text AS mission_state, m.courier_id,
      COALESCE(cp.state, co.state) AS engine_state,
      (cp.disputed_at IS NOT NULL AND cp.dispute_resolution IS NULL)
        OR (co.disputed_at IS NOT NULL AND co.dispute_resolution IS NULL) AS disputed,
      EXISTS (SELECT 1 FROM public.repas_custody_credentials c
               WHERE c.order_id = fo.id AND c.locked_at IS NOT NULL) AS custody_locked,
      (SELECT c.kind FROM public.repas_custody_credentials c
        WHERE c.order_id = fo.id AND c.consumed_at IS NULL AND c.locked_at IS NULL
        ORDER BY c.created_at DESC LIMIT 1) AS custody_pending_kind,
      oc.id AS case_id, oc.status AS case_status, oc.reason_code AS case_reason,
      oc.severity AS case_severity
    FROM public.food_orders fo
    JOIN public.food_restaurants r ON r.id = fo.restaurant_id
    LEFT JOIN LATERAL (
      SELECT * FROM public.missions mm
       WHERE mm.ref_food_order_id = fo.id ORDER BY mm.created_at DESC LIMIT 1) m ON true
    LEFT JOIN public.chop_pay_order_runtime cp
      ON cp.source_module = 'repas' AND cp.source_id = fo.id
    LEFT JOIN public.cash_order_runtime co
      ON co.source_module = 'repas' AND co.source_id = fo.id
    LEFT JOIN LATERAL (
      SELECT * FROM public.repas_ops_cases c
       WHERE c.food_order_id = fo.id ORDER BY (c.status <> 'resolved') DESC, c.created_at DESC
       LIMIT 1) oc ON true
    WHERE fo.created_at >= now() - interval '30 days'
      AND (p_search IS NULL OR btrim(p_search) = ''
           OR fo.id::text = btrim(p_search)
           OR fo.client_request_id::text = btrim(p_search)
           OR r.name ILIKE '%'||btrim(p_search)||'%')
  ), scored AS (
    SELECT b.*, public._repas_ops_flags(
      b.state, b.fulfillment, b.created_at, b.updated_at, b.mission_state, b.courier_id,
      b.engine_state, COALESCE(b.disputed,false), b.custody_locked) AS flags
    FROM base b
  )
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'updated_at' DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'order_id', s.id,
      'state', s.state,
      'fulfillment', s.fulfillment,
      'tender', s.tender,
      'order_total_gnf', s.order_total_gnf,
      'restaurant_id', s.restaurant_id,
      'restaurant_name', s.restaurant_name,
      'mission_id', s.mission_id,
      'mission_state', s.mission_state,
      'courier_assigned', s.courier_id IS NOT NULL,
      'engine_state', s.engine_state,
      'disputed', COALESCE(s.disputed,false),
      'custody_locked', s.custody_locked,
      'custody_pending_kind', s.custody_pending_kind,
      'case_id', s.case_id,
      'case_status', s.case_status,
      'case_reason_code', s.case_reason,
      'case_severity', s.case_severity,
      'created_at', s.created_at,
      'updated_at', s.updated_at,
      'age_minutes', floor(extract(epoch FROM (now() - s.created_at)) / 60)::int,
      'state_age_minutes', floor(extract(epoch FROM (now() - s.updated_at)) / 60)::int,
      'terminal', s.state IN ('completed','cancelled'),
      'attention', array_length(s.flags,1) IS NOT NULL,
      'attention_flags', to_jsonb(s.flags)
    ) AS x
    FROM scored s
    WHERE CASE p_filter
      WHEN 'attention' THEN array_length(s.flags,1) IS NOT NULL
                         OR (s.case_status IS NOT NULL AND s.case_status <> 'resolved')
      WHEN 'active'    THEN s.state NOT IN ('completed','cancelled')
      WHEN 'open'      THEN s.case_status = 'open'
      WHEN 'escalated' THEN s.case_status = 'escalated'
      WHEN 'resolved'  THEN s.case_status = 'resolved'
      ELSE true END
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit,50), 200))
  ) q;

  RETURN jsonb_build_object(
    'ok', true, 'actor_role', v_role, 'filter', p_filter,
    'reassignment_available', false,
    'count', jsonb_array_length(v_rows), 'rows', v_rows);
END; $$;

REVOKE ALL ON FUNCTION public.repas_ops_queue(text,text,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_ops_queue(text,text,int) TO authenticated, service_role;