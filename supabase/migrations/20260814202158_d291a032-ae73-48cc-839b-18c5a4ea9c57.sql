-- ============================================================
-- NODE 3 REPAS — R10 OPERATIONS / CORE-TEAM INTERVENTION
-- Append-only ops case model + command plane. No new money logic.
-- ============================================================

CREATE TABLE public.repas_ops_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  food_order_id uuid NOT NULL REFERENCES public.food_orders(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','escalated','resolved')),
  reason_code text NOT NULL CHECK (reason_code IN (
    'merchant_unresponsive','courier_unresponsive','customer_unreachable',
    'order_stuck','payment_issue','custody_issue','wrong_order',
    'quality_issue','delivery_failed','other')),
  severity text NOT NULL DEFAULT 'normal' CHECK (severity IN ('low','normal','high')),
  note text NOT NULL CHECK (length(btrim(note)) >= 3),
  created_by uuid NOT NULL,
  resolved_by uuid,
  resolved_at timestamptz,
  resolution_code text CHECK (resolution_code IS NULL OR resolution_code IN (
    'resolved_delivered','resolved_cancelled','resolved_refunded',
    'resolved_contacted','resolved_no_action','resolved_duplicate','other')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX repas_ops_cases_one_active
  ON public.repas_ops_cases(food_order_id) WHERE status <> 'resolved';
CREATE INDEX repas_ops_cases_order ON public.repas_ops_cases(food_order_id);

GRANT ALL ON public.repas_ops_cases TO service_role;
ALTER TABLE public.repas_ops_cases ENABLE ROW LEVEL SECURITY;

CREATE TABLE public.repas_ops_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES public.repas_ops_cases(id) ON DELETE CASCADE,
  food_order_id uuid NOT NULL,
  action text NOT NULL CHECK (action IN (
    'open_case','add_note','contact_customer','contact_merchant','contact_courier',
    'escalate','resolve','reopen','custody_reissue','cancel_order','dispute_resolve')),
  actor_user_id uuid NOT NULL,
  actor_role text NOT NULL,
  reason_code text,
  note text,
  request_id uuid NOT NULL,
  before_state jsonb,
  after_state jsonb,
  finance_result jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX repas_ops_events_request_key
  ON public.repas_ops_events(action, request_id);
CREATE INDEX repas_ops_events_order ON public.repas_ops_events(food_order_id, created_at);

GRANT ALL ON public.repas_ops_events TO service_role;
ALTER TABLE public.repas_ops_events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._repas_ops_events_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  RAISE EXCEPTION 'OPS_EVENTS_APPEND_ONLY';
END; $$;

CREATE TRIGGER repas_ops_events_immutable
  BEFORE UPDATE OR DELETE ON public.repas_ops_events
  FOR EACH ROW EXECUTE FUNCTION public._repas_ops_events_append_only();

CREATE TRIGGER repas_ops_cases_updated
  BEFORE UPDATE ON public.repas_ops_cases
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ------------------------------------------------------------
-- Actor resolution (fails closed; reuses existing admin tiers)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._repas_ops_actor_role(p_uid uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_uid IS NULL THEN NULL
    WHEN public.is_god_admin(p_uid) THEN 'god_admin'
    WHEN public.has_admin_role(p_uid, 'finance_admin'::admin_role) THEN 'finance_admin'
    WHEN public._is_ops_or_god_admin(p_uid) THEN 'operations_admin'
    ELSE NULL END;
$$;

-- ------------------------------------------------------------
-- Server-derived attention signals
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._repas_ops_flags(
  p_state text, p_fulfillment text, p_updated timestamptz,
  p_mission_state text, p_courier uuid, p_engine_state text,
  p_disputed boolean, p_custody_locked boolean)
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT ARRAY(SELECT f FROM (VALUES
    (CASE WHEN p_state = 'placed'
            AND p_updated < now() - interval '10 minutes'
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

-- ------------------------------------------------------------
-- C. READ-ONLY OPS WORK QUEUE
-- ------------------------------------------------------------
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
      b.state, b.fulfillment, b.updated_at, b.mission_state, b.courier_id,
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
      'age_minutes', floor(extract(epoch FROM (now() - s.updated_at)) / 60)::int,
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

-- ------------------------------------------------------------
-- Allowed actions (server-side authority)
-- ------------------------------------------------------------
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
    a := a || 'open_case';
  END IF;
  IF v_case.id IS NOT NULL THEN
    a := a || ARRAY['add_note','contact_customer','contact_merchant'];
    IF v_mission IS NOT NULL THEN a := a || 'contact_courier'; END IF;
    IF v_case.status = 'open' THEN a := a || 'escalate'; END IF;
    IF v_case.status <> 'resolved' THEN a := a || 'resolve'; END IF;
    IF v_case.status = 'resolved' THEN a := a || 'reopen'; END IF;
  END IF;

  -- Custody recovery: pre-handoff only, never a completion bypass.
  IF v_case.id IS NOT NULL AND NOT v_terminal AND NOT v_disputed
     AND v_o.state::text = 'ready' AND v_pending IS NOT NULL THEN
    a := a || 'custody_reissue';
  END IF;

  -- Finance-sensitive: existing finance delegation only.
  IF v_case.id IS NOT NULL AND v_fin AND NOT v_terminal
     AND v_o.payment_method::text = 'choppay' AND v_runtime THEN
    a := a || 'cancel_order';
  END IF;
  IF v_case.id IS NOT NULL AND v_fin AND v_disputed THEN
    a := a || 'dispute_resolve';
  END IF;
  RETURN a;
END; $$;

-- ------------------------------------------------------------
-- Case detail read model (no custody secrets)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.repas_ops_case_detail(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_role text;
  v_o public.food_orders%ROWTYPE; v_r public.food_restaurants%ROWTYPE;
  v_m public.missions%ROWTYPE; v_case public.repas_ops_cases%ROWTYPE;
  v_engine text; v_dispute text; v_timeline jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  v_role := public._repas_ops_actor_role(v_uid);
  IF v_role IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  SELECT * INTO v_m FROM public.missions WHERE ref_food_order_id = p_order_id
   ORDER BY created_at DESC LIMIT 1;
  SELECT * INTO v_case FROM public.repas_ops_cases WHERE food_order_id = p_order_id
   ORDER BY (status <> 'resolved') DESC, created_at DESC LIMIT 1;

  SELECT state, dispute_reason INTO v_engine, v_dispute FROM public.chop_pay_order_runtime
   WHERE source_module='repas' AND source_id=p_order_id;
  IF v_engine IS NULL THEN
    SELECT state, dispute_reason INTO v_engine, v_dispute FROM public.cash_order_runtime
     WHERE source_module='repas' AND source_id=p_order_id;
  END IF;

  SELECT COALESCE(jsonb_agg(t ORDER BY (t->>'at')), '[]'::jsonb) INTO v_timeline FROM (
    SELECT jsonb_build_object('source','order','at',v_o.created_at,
             'label','order_placed','actor','customer') AS t
    UNION ALL
    SELECT jsonb_build_object('source','custody','at',e.occurred_at,
             'label',e.boundary,'method',e.method,'actor','participant')
      FROM public.repas_custody_events e WHERE e.order_id = p_order_id
    UNION ALL
    SELECT jsonb_build_object('source','ops','at',ev.created_at,'label',ev.action,
             'actor','operator','actor_user_id',ev.actor_user_id,'actor_role',ev.actor_role,
             'reason_code',ev.reason_code,'note',ev.note,
             'finance_result',ev.finance_result)
      FROM public.repas_ops_events ev WHERE ev.food_order_id = p_order_id
  ) z;

  RETURN jsonb_build_object(
    'ok', true, 'actor_role', v_role,
    'order', jsonb_build_object(
      'order_id', v_o.id, 'state', v_o.state::text,
      'fulfillment', v_o.fulfillment::text, 'tender', v_o.payment_method::text,
      'order_total_gnf', v_o.order_total_gnf, 'delivery_fee_gnf', v_o.delivery_fee_gnf,
      'subtotal_gnf', v_o.subtotal_gnf,
      'created_at', v_o.created_at, 'updated_at', v_o.updated_at,
      'client_request_id', v_o.client_request_id,
      'customer_user_id', v_o.user_id,
      'restaurant_id', v_r.id, 'restaurant_name', v_r.name,
      'terminal', v_o.state::text IN ('completed','cancelled')),
    'payment', jsonb_build_object(
      'engine_state', v_engine, 'dispute_reason', v_dispute,
      'settlement_state', v_o.settlement_state,
      'disputed', public._repas_custody_dispute_blocked(p_order_id)),
    'mission', CASE WHEN v_m.id IS NULL THEN NULL ELSE jsonb_build_object(
      'mission_id', v_m.id, 'state', v_m.state::text,
      'courier_id', v_m.courier_id, 'issue_reason', v_m.issue_reason) END,
    'custody', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'kind', c.kind, 'consumed', c.consumed_at IS NOT NULL,
        'locked', c.locked_at IS NOT NULL, 'attempts', c.attempts,
        'issued_at', c.created_at))
      FROM public.repas_custody_credentials c WHERE c.order_id = p_order_id), '[]'::jsonb),
    'case', CASE WHEN v_case.id IS NULL THEN NULL ELSE jsonb_build_object(
      'case_id', v_case.id, 'status', v_case.status, 'reason_code', v_case.reason_code,
      'severity', v_case.severity, 'note', v_case.note,
      'created_by', v_case.created_by, 'created_at', v_case.created_at,
      'resolved_by', v_case.resolved_by, 'resolved_at', v_case.resolved_at,
      'resolution_code', v_case.resolution_code) END,
    'timeline', v_timeline,
    'allowed_actions', to_jsonb(public._repas_ops_allowed_actions(p_order_id, v_uid, v_role)),
    'reassignment_available', false,
    'reassignment_reason', 'NO_CERTIFIED_REASSIGNMENT_PRIMITIVE');
END; $$;

-- ------------------------------------------------------------
-- D/E/F. SINGLE IDEMPOTENT COMMAND RPC
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.repas_ops_command(
  p_order_id uuid,
  p_action text,
  p_request_id uuid,
  p_reason_code text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_params jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid(); v_role text;
  v_o public.food_orders%ROWTYPE;
  v_case public.repas_ops_cases%ROWTYPE;
  v_prior public.repas_ops_events%ROWTYPE;
  v_before jsonb; v_after jsonb; v_fin jsonb := NULL;
  v_cred public.repas_custody_credentials%ROWTYPE;
  v_allowed text[]; v_ev uuid; v_party text; v_outcome text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  v_role := public._repas_ops_actor_role(v_uid);
  IF v_role IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'REQUEST_ID_REQUIRED'; END IF;

  IF p_action = 'reassign_courier' THEN
    RAISE EXCEPTION 'ACTION_NOT_AVAILABLE'
      USING DETAIL = 'NO_CERTIFIED_REASSIGNMENT_PRIMITIVE';
  END IF;
  IF p_action IN ('undo_reject','restore_order','mark_delivered','force_complete') THEN
    RAISE EXCEPTION 'ACTION_NOT_REVERSIBLE' USING DETAIL = p_action;
  END IF;
  IF p_action NOT IN ('open_case','add_note','contact_customer','contact_merchant',
      'contact_courier','escalate','resolve','reopen','custody_reissue',
      'cancel_order','dispute_resolve') THEN
    RAISE EXCEPTION 'UNKNOWN_ACTION' USING DETAIL = COALESCE(p_action,'null');
  END IF;

  -- Idempotent replay: return the canonical prior result.
  SELECT * INTO v_prior FROM public.repas_ops_events
   WHERE action = p_action AND request_id = p_request_id;
  IF v_prior.id IS NOT NULL THEN
    IF v_prior.food_order_id <> p_order_id THEN
      RAISE EXCEPTION 'OPS_REQUEST_ID_CONFLICT' USING DETAIL = v_prior.food_order_id::text;
    END IF;
    RETURN jsonb_build_object('ok', true, 'replay', true, 'action', p_action,
      'event_id', v_prior.id, 'case_id', v_prior.case_id,
      'result', COALESCE(v_prior.after_state,'{}'::jsonb),
      'finance_result', v_prior.finance_result);
  END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_case FROM public.repas_ops_cases WHERE food_order_id = p_order_id
   ORDER BY (status <> 'resolved') DESC, created_at DESC LIMIT 1;

  v_allowed := public._repas_ops_allowed_actions(p_order_id, v_uid, v_role);
  IF NOT (p_action = ANY(v_allowed)) THEN
    RAISE EXCEPTION 'ACTION_NOT_ALLOWED' USING DETAIL = p_action;
  END IF;

  v_before := jsonb_build_object(
    'order_state', v_o.state::text,
    'case_status', v_case.status,
    'case_id', v_case.id);

  -- ---------- A/D: case lifecycle ----------
  IF p_action = 'open_case' THEN
    IF p_reason_code IS NULL THEN RAISE EXCEPTION 'REASON_CODE_REQUIRED'; END IF;
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    INSERT INTO public.repas_ops_cases(food_order_id, reason_code, note, created_by, severity)
    VALUES (p_order_id, p_reason_code, btrim(p_note), v_uid,
            COALESCE(NULLIF(p_params->>'severity',''), 'normal'))
    RETURNING * INTO v_case;
    v_after := jsonb_build_object('case_id', v_case.id, 'case_status', v_case.status);

  ELSIF p_action IN ('add_note','contact_customer','contact_merchant','contact_courier') THEN
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    v_after := jsonb_build_object('case_id', v_case.id, 'case_status', v_case.status,
                                  'logged', p_action);

  ELSIF p_action = 'escalate' THEN
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    UPDATE public.repas_ops_cases SET status = 'escalated', severity = 'high'
     WHERE id = v_case.id RETURNING * INTO v_case;
    v_after := jsonb_build_object('case_id', v_case.id, 'case_status', v_case.status);

  ELSIF p_action = 'resolve' THEN
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    IF p_reason_code IS NULL THEN RAISE EXCEPTION 'RESOLUTION_CODE_REQUIRED'; END IF;
    UPDATE public.repas_ops_cases
       SET status = 'resolved', resolved_by = v_uid, resolved_at = now(),
           resolution_code = p_reason_code
     WHERE id = v_case.id RETURNING * INTO v_case;
    v_after := jsonb_build_object('case_id', v_case.id, 'case_status', v_case.status,
                                  'resolution_code', v_case.resolution_code);

  ELSIF p_action = 'reopen' THEN
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    IF p_reason_code IS NULL THEN RAISE EXCEPTION 'REASON_CODE_REQUIRED'; END IF;
    -- Never overwrite a prior resolution: a reopen creates a NEW case row.
    INSERT INTO public.repas_ops_cases(food_order_id, reason_code, note, created_by, severity)
    VALUES (p_order_id, p_reason_code, btrim(p_note), v_uid, 'normal')
    RETURNING * INTO v_case;
    v_after := jsonb_build_object('case_id', v_case.id, 'case_status', v_case.status,
                                  'reopened_from', v_before->>'case_id');

  -- ---------- E: custody credential reissue (no bypass) ----------
  ELSIF p_action = 'custody_reissue' THEN
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    SELECT * INTO v_cred FROM public.repas_custody_credentials
     WHERE order_id = p_order_id AND consumed_at IS NULL
     ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
    IF v_cred.id IS NULL THEN RAISE EXCEPTION 'NO_PENDING_CUSTODY_CREDENTIAL'; END IF;
    IF v_o.state::text <> 'ready' THEN
      RAISE EXCEPTION 'CUSTODY_REISSUE_WRONG_PHASE' USING DETAIL = v_o.state::text;
    END IF;
    PERFORM public._repas_custody_purge_secret(v_cred.id);
    DELETE FROM public.repas_custody_credentials WHERE id = v_cred.id;
    PERFORM public._repas_custody_issue(p_order_id, v_cred.kind, v_cred.holder_user_id);
    v_after := jsonb_build_object('reissued', true, 'kind', v_cred.kind,
                                  'holder_unchanged', true,
                                  'order_state', v_o.state::text,
                                  'case_id', v_case.id);

  -- ---------- F: economic adapters (canonical engines only) ----------
  ELSIF p_action = 'cancel_order' THEN
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    v_party := COALESCE(NULLIF(p_params->>'responsible_party',''), 'platform');
    IF v_party NOT IN ('customer','merchant','driver','platform') THEN
      RAISE EXCEPTION 'INVALID_RESPONSIBLE_PARTY' USING DETAIL = v_party;
    END IF;
    IF v_o.payment_method::text <> 'choppay' THEN
      RAISE EXCEPTION 'OPS_CANCEL_UNSUPPORTED_TENDER' USING DETAIL = v_o.payment_method::text;
    END IF;
    v_fin := public.admin_chop_pay_cancel('repas', p_order_id, v_party,
               COALESCE(p_reason_code,'ops_cancel')||': '||btrim(p_note));
    PERFORM set_config('chopchop.cash_engine','1',true);
    UPDATE public.food_orders SET state = 'cancelled', updated_at = now()
     WHERE id = p_order_id AND state <> 'cancelled';
    PERFORM set_config('chopchop.cash_engine','0',true);
    UPDATE public.missions SET state = 'failed', updated_at = now()
     WHERE ref_food_order_id = p_order_id AND courier_id IS NULL AND state = 'assigned';
    v_after := jsonb_build_object('order_state', 'cancelled', 'case_id', v_case.id,
                                  'responsible_party', v_party);

  ELSIF p_action = 'dispute_resolve' THEN
    IF COALESCE(length(btrim(p_note)),0) < 3 THEN RAISE EXCEPTION 'NOTE_REQUIRED'; END IF;
    v_outcome := NULLIF(p_params->>'outcome','');
    IF v_outcome IS NULL THEN RAISE EXCEPTION 'OUTCOME_REQUIRED'; END IF;
    IF EXISTS (SELECT 1 FROM public.chop_pay_order_runtime
                WHERE source_module='repas' AND source_id=p_order_id) THEN
      v_fin := public.admin_chop_pay_dispute_resolve('repas', p_order_id, v_outcome,
                 COALESCE(p_reason_code,'ops_dispute')||': '||btrim(p_note));
    ELSE
      v_fin := public.admin_cash_order_dispute_resolve('repas', p_order_id, v_outcome,
                 COALESCE(p_reason_code,'ops_dispute')||': '||btrim(p_note));
    END IF;
    v_after := jsonb_build_object('dispute_outcome', v_outcome, 'case_id', v_case.id);
  END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  v_after := v_after || jsonb_build_object('order_state_after', v_o.state::text);

  INSERT INTO public.repas_ops_events(
    case_id, food_order_id, action, actor_user_id, actor_role,
    reason_code, note, request_id, before_state, after_state, finance_result)
  VALUES (v_case.id, p_order_id, p_action, v_uid, v_role,
          p_reason_code, NULLIF(btrim(COALESCE(p_note,'')),''), p_request_id,
          v_before, v_after, v_fin)
  RETURNING id INTO v_ev;

  PERFORM public.log_admin_action('repas_ops', p_action, 'food_order', p_order_id::text,
            v_before, v_after, NULLIF(btrim(COALESCE(p_note,'')),''));

  RETURN jsonb_build_object('ok', true, 'replay', false, 'action', p_action,
    'event_id', v_ev, 'case_id', v_case.id, 'result', v_after, 'finance_result', v_fin);
END; $$;

-- ------------------------------------------------------------
-- H. GRANTS — RPC-only access, anon fully closed
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.repas_ops_queue(text,text,int) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.repas_ops_case_detail(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.repas_ops_command(uuid,text,uuid,text,text,jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._repas_ops_actor_role(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._repas_ops_allowed_actions(uuid,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._repas_ops_flags(text,text,timestamptz,text,uuid,text,boolean,boolean) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.repas_ops_queue(text,text,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.repas_ops_case_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.repas_ops_command(uuid,text,uuid,text,text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.repas_ops_queue(text,text,int) TO service_role;
GRANT EXECUTE ON FUNCTION public.repas_ops_case_detail(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.repas_ops_command(uuid,text,uuid,text,text,jsonb) TO service_role;