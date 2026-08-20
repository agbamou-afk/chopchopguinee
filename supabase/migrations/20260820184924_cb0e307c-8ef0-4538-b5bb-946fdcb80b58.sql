-- ============================================================
-- NODE 4 · MARCHÉ R12 — OPERATIONS + EXCEPTIONS (schema + rails)
-- Prospective controls only. No historical truth is rewritten.
-- ============================================================

-- ---------- A. CASE TRUTH ----------
CREATE TABLE public.marche_ops_cases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_type text NOT NULL,
  severity text NOT NULL DEFAULT 'normal',
  status text NOT NULL DEFAULT 'open',
  subject_store_id uuid REFERENCES public.merchant_stores(id),
  subject_listing_id uuid REFERENCES public.marketplace_listings(id),
  subject_order_id uuid REFERENCES public.marche_orders(id),
  subject_mission_id uuid REFERENCES public.marche_procurement_missions(id),
  subject_customer_user_id uuid,
  subject_shopper_user_id uuid,
  subject_reputation_event_id uuid REFERENCES public.marche_reputation_events(id),
  source text NOT NULL DEFAULT 'manual',
  detector_key text,
  reason_code text NOT NULL,
  note text NOT NULL DEFAULT '',
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  assigned_to uuid,
  opened_by uuid,
  opened_at timestamptz NOT NULL DEFAULT now(),
  resolution_code text,
  resolved_at timestamptz,
  resolved_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_ops_cases_type_chk CHECK (case_type = ANY (ARRAY[
    'merchant_suspension','catalog_violation','price_anomaly','fraud',
    'procurement_anomaly','customer_dispute','shopper_dispute',
    'rating_abuse','stock_accuracy','merchant_reliability'])),
  CONSTRAINT marche_ops_cases_severity_chk CHECK (severity = ANY (ARRAY['low','normal','high','critical'])),
  CONSTRAINT marche_ops_cases_status_chk CHECK (status = ANY (ARRAY['open','in_review','resolved','dismissed'])),
  CONSTRAINT marche_ops_cases_source_chk CHECK (source = ANY (ARRAY['manual','detector'])),
  CONSTRAINT marche_ops_cases_reason_chk CHECK (length(btrim(reason_code)) >= 3),
  CONSTRAINT marche_ops_cases_subject_chk CHECK (
    subject_store_id IS NOT NULL OR subject_listing_id IS NOT NULL
    OR subject_order_id IS NOT NULL OR subject_mission_id IS NOT NULL
    OR subject_customer_user_id IS NOT NULL OR subject_shopper_user_id IS NOT NULL
    OR subject_reputation_event_id IS NOT NULL),
  CONSTRAINT marche_ops_cases_resolution_chk CHECK (
    (status IN ('resolved','dismissed')) = (resolution_code IS NOT NULL)
    AND (status IN ('resolved','dismissed')) = (resolved_at IS NOT NULL))
);
CREATE UNIQUE INDEX marche_ops_cases_detector_active
  ON public.marche_ops_cases(detector_key)
  WHERE detector_key IS NOT NULL AND status IN ('open','in_review');
CREATE INDEX marche_ops_cases_status_idx ON public.marche_ops_cases(status, opened_at DESC);
CREATE INDEX marche_ops_cases_store_idx ON public.marche_ops_cases(subject_store_id) WHERE subject_store_id IS NOT NULL;

GRANT ALL ON public.marche_ops_cases TO service_role;
ALTER TABLE public.marche_ops_cases ENABLE ROW LEVEL SECURITY;

CREATE TRIGGER marche_ops_cases_updated BEFORE UPDATE ON public.marche_ops_cases
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ---------- A2. APPEND-ONLY EVENT STREAM ----------
CREATE TABLE public.marche_ops_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id uuid NOT NULL REFERENCES public.marche_ops_cases(id),
  action text NOT NULL,
  actor_user_id uuid,
  actor_role text NOT NULL,
  reason_code text,
  note text,
  request_id uuid NOT NULL,
  before_state jsonb,
  after_state jsonb,
  finance_ref jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_ops_events_action_chk CHECK (action = ANY (ARRAY[
    'open_case','add_note','assign','start_review','request_evidence','escalate',
    'suspend_merchant','restore_merchant','quarantine_listing','restore_listing',
    'restrict_user','unrestrict_user','moderate_rating','restore_rating',
    'record_finance_resolution','resolve','dismiss','reopen','detector_signal']))
);
CREATE UNIQUE INDEX marche_ops_events_request_key ON public.marche_ops_events(action, request_id);
CREATE INDEX marche_ops_events_case_idx ON public.marche_ops_events(case_id, created_at);

GRANT ALL ON public.marche_ops_events TO service_role;
ALTER TABLE public.marche_ops_events ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._marche_ops_events_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'MARCHE_OPS_EVENTS_APPEND_ONLY';
END $$;
CREATE TRIGGER marche_ops_events_immutable BEFORE UPDATE OR DELETE ON public.marche_ops_events
  FOR EACH ROW EXECUTE FUNCTION public._marche_ops_events_append_only();

-- ---------- A3. PROSPECTIVE OPERATIONAL CONTROLS ----------
CREATE TABLE public.marche_ops_controls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  control_kind text NOT NULL,
  case_id uuid NOT NULL REFERENCES public.marche_ops_cases(id),
  subject_store_id uuid REFERENCES public.merchant_stores(id),
  subject_listing_id uuid REFERENCES public.marketplace_listings(id),
  subject_user_id uuid,
  reason_code text NOT NULL,
  note text,
  effective_from timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  applied_by uuid NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now(),
  lifted_at timestamptz,
  lifted_by uuid,
  lift_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_ops_controls_kind_chk CHECK (control_kind = ANY (ARRAY[
    'store_suspension','listing_quarantine','user_restriction'])),
  CONSTRAINT marche_ops_controls_subject_chk CHECK (
    (control_kind = 'store_suspension' AND subject_store_id IS NOT NULL AND subject_listing_id IS NULL AND subject_user_id IS NULL)
    OR (control_kind = 'listing_quarantine' AND subject_listing_id IS NOT NULL AND subject_store_id IS NULL AND subject_user_id IS NULL)
    OR (control_kind = 'user_restriction' AND subject_user_id IS NOT NULL AND subject_store_id IS NULL AND subject_listing_id IS NULL))
);
CREATE UNIQUE INDEX marche_ops_controls_active_store ON public.marche_ops_controls(subject_store_id)
  WHERE control_kind = 'store_suspension' AND lifted_at IS NULL;
CREATE UNIQUE INDEX marche_ops_controls_active_listing ON public.marche_ops_controls(subject_listing_id)
  WHERE control_kind = 'listing_quarantine' AND lifted_at IS NULL;
CREATE UNIQUE INDEX marche_ops_controls_active_user ON public.marche_ops_controls(subject_user_id)
  WHERE control_kind = 'user_restriction' AND lifted_at IS NULL;

GRANT ALL ON public.marche_ops_controls TO service_role;
ALTER TABLE public.marche_ops_controls ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER marche_ops_controls_updated BEFORE UPDATE ON public.marche_ops_controls
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ---------- A4. NON-DESTRUCTIVE REPUTATION MODERATION ----------
CREATE TABLE public.marche_ops_reputation_moderations (
  event_id uuid PRIMARY KEY REFERENCES public.marche_reputation_events(id),
  case_id uuid NOT NULL REFERENCES public.marche_ops_cases(id),
  reason_code text NOT NULL,
  note text,
  moderated_by uuid NOT NULL,
  moderated_at timestamptz NOT NULL DEFAULT now(),
  restored_at timestamptz,
  restored_by uuid,
  restore_reason text
);
GRANT ALL ON public.marche_ops_reputation_moderations TO service_role;
ALTER TABLE public.marche_ops_reputation_moderations ENABLE ROW LEVEL SECURITY;

-- ---------- B. CONTROL PREDICATES ----------
CREATE OR REPLACE FUNCTION public.marche_ops_store_suspended(p_store_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.marche_ops_controls c
    WHERE c.control_kind='store_suspension' AND c.subject_store_id = p_store_id
      AND c.lifted_at IS NULL AND c.effective_from <= now()
      AND (c.expires_at IS NULL OR c.expires_at > now()));
$$;

CREATE OR REPLACE FUNCTION public.marche_ops_listing_quarantined(p_listing_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.marche_ops_controls c
    WHERE c.control_kind='listing_quarantine' AND c.subject_listing_id = p_listing_id
      AND c.lifted_at IS NULL AND c.effective_from <= now()
      AND (c.expires_at IS NULL OR c.expires_at > now()));
$$;

CREATE OR REPLACE FUNCTION public.marche_ops_user_restricted(p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.marche_ops_controls c
    WHERE c.control_kind='user_restriction' AND c.subject_user_id = p_user_id
      AND c.lifted_at IS NULL AND c.effective_from <= now()
      AND (c.expires_at IS NULL OR c.expires_at > now()));
$$;

REVOKE ALL ON FUNCTION public.marche_ops_store_suspended(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_ops_listing_quarantined(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_ops_user_restricted(uuid) FROM PUBLIC, anon, authenticated;

-- ---------- B2. CANONICAL ORDERABILITY TRUTH (prospective only) ----------
CREATE OR REPLACE VIEW public.v_marche_listing_truth AS
 SELECT listing_id, seller_id, store_id, kind, status, visibility, availability,
        quantity_in_stock, photo_count, price_gnf, pricing_mode, store_ok, is_demo,
        seller_banned, refusal_reason, refusal_reason IS NULL AS is_orderable,
        quantity_reserved, quantity_available
   FROM ( SELECT l.id AS listing_id, l.seller_id, l.store_id, l.kind, l.status,
            l.visibility, l.availability, l.quantity_in_stock, l.photo_count,
            l.price_gnf, l.pricing_mode,
            s.id IS NOT NULL AND s.status = 'active'::text AND s.onboarding_status = 'approved'::text AS store_ok,
            marche_is_demo_seller(l.seller_id) AS is_demo,
            marche_seller_banned(l.seller_id) AS seller_banned,
            l.quantity_reserved,
            CASE WHEN l.quantity_in_stock IS NULL THEN NULL::integer
                 ELSE l.quantity_in_stock - COALESCE(l.quantity_reserved, 0) END AS quantity_available,
            CASE
              WHEN l.store_id IS NULL OR l.kind <> 'merchant'::listing_kind THEN 'MERCHANT_STORE_REQUIRED'::text
              WHEN l.status = 'removed'::listing_status THEN 'LISTING_REMOVED'::text
              WHEN l.status = 'sold'::listing_status OR l.availability = 'sold'::listing_availability THEN 'LISTING_SOLD'::text
              WHEN l.status = 'paused'::listing_status THEN 'LISTING_PAUSED'::text
              WHEN l.visibility <> 'public'::text THEN 'LISTING_PRIVATE'::text
              WHEN marche_seller_banned(l.seller_id) THEN 'SELLER_NOT_ELIGIBLE'::text
              WHEN marche_ops_listing_quarantined(l.id) THEN 'LISTING_QUARANTINED'::text
              WHEN l.store_id IS NOT NULL AND marche_ops_store_suspended(l.store_id) THEN 'STORE_SUSPENDED'::text
              WHEN NOT (s.id IS NOT NULL AND s.status = 'active'::text AND s.onboarding_status = 'approved'::text) THEN 'STORE_NOT_APPROVED'::text
              WHEN marche_is_demo_seller(l.seller_id) THEN 'DEMO_SUPPLY'::text
              WHEN l.quantity_in_stock IS NOT NULL AND (l.quantity_in_stock - COALESCE(l.quantity_reserved, 0)) <= 0 THEN 'OUT_OF_STOCK'::text
              WHEN l.pricing_mode = 'fixed'::text AND l.kind = 'merchant'::listing_kind AND COALESCE(l.price_gnf, 0::bigint) <= 0 THEN 'INVALID_PRICE'::text
              ELSE NULL::text
            END AS refusal_reason
           FROM marketplace_listings l
             LEFT JOIN merchant_stores s ON s.id = l.store_id) t;

-- ---------- B3. R9 DERIVED REPUTATION EXCLUDES MODERATED EVIDENCE ----------
CREATE OR REPLACE FUNCTION public.marche_reputation_summary(p_subject_kind text, p_subject_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_count bigint; v_avg numeric; v_last timestamptz; v_dims jsonb;
BEGIN
  IF p_subject_kind NOT IN ('merchant_store','delivery_driver','shopper') THEN
    RAISE EXCEPTION 'INVALID_SUBJECT_KIND';
  END IF;
  IF p_subject_id IS NULL THEN RAISE EXCEPTION 'SUBJECT_REQUIRED'; END IF;

  SELECT count(*), avg(overall_score), max(created_at)
    INTO v_count, v_avg, v_last
    FROM public.marche_reputation_events e
   WHERE e.subject_kind = p_subject_kind
     AND ((p_subject_kind = 'merchant_store' AND e.subject_store_id = p_subject_id)
       OR (p_subject_kind <> 'merchant_store' AND e.subject_user_id = p_subject_id))
     AND NOT EXISTS (SELECT 1 FROM public.marche_ops_reputation_moderations m
                      WHERE m.event_id = e.id AND m.restored_at IS NULL);

  IF COALESCE(v_count,0) = 0 THEN
    RETURN jsonb_build_object(
      'subject_kind', p_subject_kind, 'subject_id', p_subject_id,
      'has_reputation', false, 'rating_count', 0,
      'overall_average', NULL, 'last_rated_at', NULL,
      'dimensions', '[]'::jsonb);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'dimension', d.dimension, 'average', round(d.avg_score, 2), 'count', d.cnt)
           ORDER BY d.dimension), '[]'::jsonb)
    INTO v_dims
    FROM (
      SELECT dm.dimension, avg(dm.score) avg_score, count(*) cnt
        FROM public.marche_reputation_dimensions dm
        JOIN public.marche_reputation_events e ON e.id = dm.event_id
       WHERE e.subject_kind = p_subject_kind
         AND ((p_subject_kind = 'merchant_store' AND e.subject_store_id = p_subject_id)
           OR (p_subject_kind <> 'merchant_store' AND e.subject_user_id = p_subject_id))
         AND NOT EXISTS (SELECT 1 FROM public.marche_ops_reputation_moderations m
                          WHERE m.event_id = e.id AND m.restored_at IS NULL)
       GROUP BY dm.dimension
    ) d;

  RETURN jsonb_build_object(
    'subject_kind', p_subject_kind, 'subject_id', p_subject_id,
    'has_reputation', true, 'rating_count', v_count,
    'overall_average', round(v_avg, 2), 'last_rated_at', v_last,
    'dimensions', v_dims);
END $function$;

-- ---------- C. ACTOR ROLE ----------
CREATE OR REPLACE FUNCTION public._marche_ops_actor_role(p_uid uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN a.admin_role IN ('god_admin','super_admin') THEN 'god_admin'
    WHEN a.admin_role = 'operations_admin' THEN 'operations_admin'
    WHEN a.admin_role = 'finance_admin' THEN 'finance_admin'
    ELSE NULL END
  FROM public.admin_users a
  WHERE a.user_id = p_uid AND a.status = 'active'
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public._marche_ops_actor_role(uuid) FROM PUBLIC, anon, authenticated;

-- ---------- D. SERVER-COMPUTED ALLOWED ACTIONS ----------
CREATE OR REPLACE FUNCTION public._marche_ops_allowed_actions(p_case public.marche_ops_cases, p_role text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE a text[] := ARRAY[]::text[]; v_ops boolean; v_fin boolean;
BEGIN
  IF p_role IS NULL THEN RETURN '[]'::jsonb; END IF;
  v_ops := p_role IN ('operations_admin','god_admin');
  v_fin := p_role IN ('finance_admin','god_admin');

  IF p_case.status IN ('resolved','dismissed') THEN
    IF v_ops THEN a := a || 'reopen'; END IF;
    RETURN to_jsonb(a);
  END IF;

  IF v_ops THEN
    a := a || 'add_note' || 'assign' || 'request_evidence' || 'escalate';
    IF p_case.status = 'open' THEN a := a || 'start_review'; END IF;

    IF p_case.case_type IN ('merchant_suspension','fraud','merchant_reliability','catalog_violation')
       AND p_case.subject_store_id IS NOT NULL THEN
      IF public.marche_ops_store_suspended(p_case.subject_store_id)
        THEN a := a || 'restore_merchant';
        ELSE a := a || 'suspend_merchant';
      END IF;
    END IF;

    IF p_case.case_type IN ('catalog_violation','price_anomaly','stock_accuracy','fraud')
       AND p_case.subject_listing_id IS NOT NULL THEN
      IF public.marche_ops_listing_quarantined(p_case.subject_listing_id)
        THEN a := a || 'restore_listing';
        ELSE a := a || 'quarantine_listing';
      END IF;
    END IF;

    IF p_case.case_type IN ('fraud','customer_dispute','shopper_dispute','procurement_anomaly')
       AND COALESCE(p_case.subject_shopper_user_id, p_case.subject_customer_user_id) IS NOT NULL THEN
      IF public.marche_ops_user_restricted(COALESCE(p_case.subject_shopper_user_id, p_case.subject_customer_user_id))
        THEN a := a || 'unrestrict_user';
        ELSE a := a || 'restrict_user';
      END IF;
    END IF;

    IF p_case.case_type = 'rating_abuse' AND p_case.subject_reputation_event_id IS NOT NULL THEN
      IF EXISTS (SELECT 1 FROM public.marche_ops_reputation_moderations m
                  WHERE m.event_id = p_case.subject_reputation_event_id AND m.restored_at IS NULL)
        THEN a := a || 'restore_rating';
        ELSE a := a || 'moderate_rating';
      END IF;
    END IF;

    a := a || 'resolve' || 'dismiss';
  ELSIF v_fin THEN
    a := a || 'add_note';
  END IF;

  IF v_fin THEN a := a || 'record_finance_resolution'; END IF;

  RETURN to_jsonb(a);
END $function$;
REVOKE ALL ON FUNCTION public._marche_ops_allowed_actions(public.marche_ops_cases, text) FROM PUBLIC, anon, authenticated;

-- ---------- E. CASE DETAIL ----------
CREATE OR REPLACE FUNCTION public.marche_ops_case_detail(p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE caller uuid := auth.uid(); v_role text; c public.marche_ops_cases%ROWTYPE;
        v_store jsonb; v_listing jsonb; v_order jsonb; v_mission jsonb;
        v_rep jsonb; v_timeline jsonb; v_controls jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  v_role := public._marche_ops_actor_role(caller);
  IF v_role IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT * INTO c FROM public.marche_ops_cases WHERE id = p_case_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'CASE_NOT_FOUND'; END IF;

  SELECT jsonb_build_object('id', s.id, 'name', s.name, 'slug', s.slug,
           'status', s.status, 'onboarding_status', s.onboarding_status,
           'ops_suspended', public.marche_ops_store_suspended(s.id))
    INTO v_store FROM public.merchant_stores s WHERE s.id = c.subject_store_id;

  SELECT jsonb_build_object('id', t.listing_id, 'title', l.title, 'status', t.status,
           'visibility', t.visibility, 'is_orderable', t.is_orderable,
           'refusal_reason', t.refusal_reason, 'price_gnf', t.price_gnf,
           'quantity_available', t.quantity_available,
           'ops_quarantined', public.marche_ops_listing_quarantined(t.listing_id))
    INTO v_listing FROM public.v_marche_listing_truth t
    JOIN public.marketplace_listings l ON l.id = t.listing_id
   WHERE t.listing_id = c.subject_listing_id;

  SELECT jsonb_build_object('id', o.id, 'status', o.status,
           'fulfillment_state', o.fulfillment_state,
           'merchandise_subtotal_gnf', o.merchandise_subtotal_gnf,
           'merchant_payable_gnf', CASE WHEN v_role IN ('finance_admin','god_admin')
                                        THEN o.merchant_payable_gnf ELSE NULL END,
           'created_at', o.created_at)
    INTO v_order FROM public.marche_orders o WHERE o.id = c.subject_order_id;

  SELECT jsonb_build_object('id', m.id, 'state', m.state,
           'verified_spend_gnf', m.verified_spend_gnf, 'created_at', m.created_at)
    INTO v_mission FROM public.marche_procurement_missions m WHERE m.id = c.subject_mission_id;

  SELECT jsonb_build_object('id', e.id, 'subject_kind', e.subject_kind,
           'overall_score', e.overall_score, 'created_at', e.created_at,
           'moderated', EXISTS (SELECT 1 FROM public.marche_ops_reputation_moderations m
                                 WHERE m.event_id = e.id AND m.restored_at IS NULL))
    INTO v_rep FROM public.marche_reputation_events e WHERE e.id = c.subject_reputation_event_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', ev.id, 'action', ev.action, 'actor_role', ev.actor_role,
           'reason_code', ev.reason_code, 'note', ev.note,
           'before_state', ev.before_state, 'after_state', ev.after_state,
           'finance_ref', ev.finance_ref, 'created_at', ev.created_at)
           ORDER BY ev.created_at, ev.id), '[]'::jsonb)
    INTO v_timeline FROM public.marche_ops_events ev WHERE ev.case_id = c.id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', k.id, 'control_kind', k.control_kind, 'reason_code', k.reason_code,
           'applied_at', k.applied_at, 'lifted_at', k.lifted_at,
           'active', k.lifted_at IS NULL) ORDER BY k.applied_at), '[]'::jsonb)
    INTO v_controls FROM public.marche_ops_controls k WHERE k.case_id = c.id;

  RETURN jsonb_build_object(
    'case_id', c.id, 'case_type', c.case_type, 'severity', c.severity,
    'status', c.status, 'source', c.source, 'detector_key', c.detector_key,
    'reason_code', c.reason_code, 'note', c.note, 'evidence', c.evidence,
    'assigned_to', c.assigned_to, 'opened_by', c.opened_by, 'opened_at', c.opened_at,
    'resolution_code', c.resolution_code, 'resolved_at', c.resolved_at,
    'resolved_by', c.resolved_by,
    'subjects', jsonb_build_object(
      'store', v_store, 'listing', v_listing, 'order', v_order,
      'mission', v_mission, 'reputation_event', v_rep,
      'customer_user_id', c.subject_customer_user_id,
      'shopper_user_id', c.subject_shopper_user_id),
    'controls', v_controls,
    'timeline', v_timeline,
    'actor_role', v_role,
    'allowed_actions', public._marche_ops_allowed_actions(c, v_role));
END $function$;
GRANT EXECUTE ON FUNCTION public.marche_ops_case_detail(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.marche_ops_case_detail(uuid) FROM anon;

-- ---------- F. QUEUE ----------
CREATE OR REPLACE FUNCTION public.marche_ops_queue(
  p_status text DEFAULT NULL, p_type text DEFAULT NULL,
  p_search text DEFAULT NULL, p_limit integer DEFAULT 50)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE caller uuid := auth.uid(); v_role text; v_items jsonb; v_counts jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  v_role := public._marche_ops_actor_role(caller);
  IF v_role IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('open','in_review','resolved','dismissed') THEN
    RAISE EXCEPTION 'UNKNOWN_STATUS';
  END IF;

  SELECT jsonb_object_agg(status, n) INTO v_counts
    FROM (SELECT status, count(*) n FROM public.marche_ops_cases GROUP BY status) q;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'opened_at' DESC), '[]'::jsonb) INTO v_items FROM (
    SELECT jsonb_build_object(
      'case_id', c.id, 'case_type', c.case_type, 'severity', c.severity,
      'status', c.status, 'source', c.source, 'reason_code', c.reason_code,
      'opened_at', c.opened_at, 'assigned_to', c.assigned_to,
      'age_hours', round(EXTRACT(epoch FROM (now() - c.opened_at))/3600.0, 1),
      'store_id', c.subject_store_id, 'store_name', s.name,
      'listing_id', c.subject_listing_id, 'order_id', c.subject_order_id,
      'mission_id', c.subject_mission_id) AS x
      FROM public.marche_ops_cases c
      LEFT JOIN public.merchant_stores s ON s.id = c.subject_store_id
     WHERE (p_status IS NULL OR c.status = p_status)
       AND (p_type IS NULL OR c.case_type = p_type)
       AND (p_search IS NULL OR btrim(p_search) = '' OR
            s.name ILIKE '%'||p_search||'%' OR c.reason_code ILIKE '%'||p_search||'%'
            OR c.note ILIKE '%'||p_search||'%')
     ORDER BY c.opened_at DESC
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit,50), 200))) q;

  RETURN jsonb_build_object('counts', COALESCE(v_counts,'{}'::jsonb),
                            'items', v_items, 'actor_role', v_role);
END $function$;
GRANT EXECUTE ON FUNCTION public.marche_ops_queue(text,text,text,integer) TO authenticated;
REVOKE ALL ON FUNCTION public.marche_ops_queue(text,text,text,integer) FROM anon;

-- ---------- G. CASE OPEN ----------
CREATE OR REPLACE FUNCTION public.marche_ops_case_open(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE caller uuid := auth.uid(); v_role text; v_id uuid; v_req uuid;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  v_role := public._marche_ops_actor_role(caller);
  IF v_role NOT IN ('operations_admin','god_admin') THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF COALESCE(btrim(p_payload->>'reason_code'),'') = '' THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  v_req := COALESCE((p_payload->>'request_id')::uuid, gen_random_uuid());

  INSERT INTO public.marche_ops_cases(
    case_type, severity, status, subject_store_id, subject_listing_id, subject_order_id,
    subject_mission_id, subject_customer_user_id, subject_shopper_user_id,
    subject_reputation_event_id, source, reason_code, note, evidence, opened_by)
  VALUES (
    p_payload->>'case_type', COALESCE(p_payload->>'severity','normal'), 'open',
    (p_payload->>'store_id')::uuid, (p_payload->>'listing_id')::uuid,
    (p_payload->>'order_id')::uuid, (p_payload->>'mission_id')::uuid,
    (p_payload->>'customer_user_id')::uuid, (p_payload->>'shopper_user_id')::uuid,
    (p_payload->>'reputation_event_id')::uuid, 'manual',
    btrim(p_payload->>'reason_code'), COALESCE(p_payload->>'note',''),
    COALESCE(p_payload->'evidence','{}'::jsonb), caller)
  RETURNING id INTO v_id;

  INSERT INTO public.marche_ops_events(case_id, action, actor_user_id, actor_role,
    reason_code, note, request_id, after_state)
  VALUES (v_id,'open_case', caller, v_role, btrim(p_payload->>'reason_code'),
          p_payload->>'note', v_req, jsonb_build_object('status','open'));

  RETURN public.marche_ops_case_detail(v_id);
END $function$;
GRANT EXECUTE ON FUNCTION public.marche_ops_case_open(jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.marche_ops_case_open(jsonb) FROM anon;

-- ---------- H. DETECTOR SIGNAL (idempotent, never sanctions) ----------
CREATE OR REPLACE FUNCTION public.marche_ops_signal(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE caller uuid := auth.uid(); v_role text; v_key text; v_id uuid; v_created boolean := false;
BEGIN
  v_role := public._marche_ops_actor_role(caller);
  IF v_role NOT IN ('operations_admin','god_admin') AND current_user <> 'service_role' THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  v_key := btrim(COALESCE(p_payload->>'detector_key',''));
  IF v_key = '' THEN RAISE EXCEPTION 'DETECTOR_KEY_REQUIRED'; END IF;

  SELECT id INTO v_id FROM public.marche_ops_cases
   WHERE detector_key = v_key AND status IN ('open','in_review') LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO public.marche_ops_cases(
      case_type, severity, status, subject_store_id, subject_listing_id, subject_order_id,
      subject_mission_id, subject_customer_user_id, subject_shopper_user_id,
      subject_reputation_event_id, source, detector_key, reason_code, note, evidence)
    VALUES (
      p_payload->>'case_type', COALESCE(p_payload->>'severity','normal'), 'open',
      (p_payload->>'store_id')::uuid, (p_payload->>'listing_id')::uuid,
      (p_payload->>'order_id')::uuid, (p_payload->>'mission_id')::uuid,
      (p_payload->>'customer_user_id')::uuid, (p_payload->>'shopper_user_id')::uuid,
      (p_payload->>'reputation_event_id')::uuid, 'detector', v_key,
      COALESCE(btrim(p_payload->>'reason_code'),'detector_signal'),
      COALESCE(p_payload->>'note',''), COALESCE(p_payload->'evidence','{}'::jsonb))
    RETURNING id INTO v_id;
    v_created := true;

    INSERT INTO public.marche_ops_events(case_id, action, actor_user_id, actor_role,
      reason_code, note, request_id, after_state, metadata)
    VALUES (v_id,'detector_signal', caller, COALESCE(v_role,'detector'),
            COALESCE(btrim(p_payload->>'reason_code'),'detector_signal'),
            p_payload->>'note', gen_random_uuid(),
            jsonb_build_object('status','open'),
            jsonb_build_object('detector_key', v_key));
  END IF;

  RETURN jsonb_build_object('case_id', v_id, 'created', v_created, 'detector_key', v_key);
END $function$;
REVOKE ALL ON FUNCTION public.marche_ops_signal(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_ops_signal(jsonb) TO authenticated;

-- ---------- I. COMMAND ----------
CREATE OR REPLACE FUNCTION public.marche_ops_command(
  p_case_id uuid, p_action text, p_request_id uuid,
  p_reason_code text DEFAULT NULL, p_note text DEFAULT NULL,
  p_params jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE caller uuid := auth.uid(); v_role text; c public.marche_ops_cases%ROWTYPE;
        v_allowed jsonb; v_before jsonb; v_after jsonb; v_fin jsonb; v_subject uuid;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  v_role := public._marche_ops_actor_role(caller);
  IF v_role IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'REQUEST_ID_REQUIRED'; END IF;

  -- Idempotent retry: the same (action, request_id) is a no-op replay.
  IF EXISTS (SELECT 1 FROM public.marche_ops_events
              WHERE action = p_action AND request_id = p_request_id) THEN
    RETURN public.marche_ops_case_detail(p_case_id);
  END IF;

  SELECT * INTO c FROM public.marche_ops_cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'CASE_NOT_FOUND'; END IF;

  v_allowed := public._marche_ops_allowed_actions(c, v_role);
  IF NOT (v_allowed @> to_jsonb(ARRAY[p_action])) THEN RAISE EXCEPTION 'ACTION_NOT_ALLOWED'; END IF;

  IF p_action IN ('suspend_merchant','restore_merchant','quarantine_listing','restore_listing',
                  'restrict_user','unrestrict_user','moderate_rating','restore_rating',
                  'resolve','dismiss','escalate','record_finance_resolution')
     AND COALESCE(btrim(p_reason_code),'') = '' THEN
    RAISE EXCEPTION 'REASON_REQUIRED';
  END IF;

  v_before := jsonb_build_object('status', c.status);

  IF p_action = 'start_review' THEN
    UPDATE public.marche_ops_cases SET status='in_review' WHERE id=c.id;
    v_after := jsonb_build_object('status','in_review');

  ELSIF p_action = 'assign' THEN
    UPDATE public.marche_ops_cases SET assigned_to=(p_params->>'assignee')::uuid WHERE id=c.id;
    v_after := jsonb_build_object('assigned_to', p_params->>'assignee');

  ELSIF p_action = 'suspend_merchant' THEN
    INSERT INTO public.marche_ops_controls(control_kind, case_id, subject_store_id,
      reason_code, note, expires_at, applied_by)
    VALUES ('store_suspension', c.id, c.subject_store_id, btrim(p_reason_code), p_note,
            (p_params->>'expires_at')::timestamptz, caller);
    v_after := jsonb_build_object('store_suspended', true);

  ELSIF p_action = 'restore_merchant' THEN
    UPDATE public.marche_ops_controls SET lifted_at=now(), lifted_by=caller, lift_reason=btrim(p_reason_code)
     WHERE control_kind='store_suspension' AND subject_store_id=c.subject_store_id AND lifted_at IS NULL;
    v_after := jsonb_build_object('store_suspended', false);

  ELSIF p_action = 'quarantine_listing' THEN
    INSERT INTO public.marche_ops_controls(control_kind, case_id, subject_listing_id,
      reason_code, note, expires_at, applied_by)
    VALUES ('listing_quarantine', c.id, c.subject_listing_id, btrim(p_reason_code), p_note,
            (p_params->>'expires_at')::timestamptz, caller);
    v_after := jsonb_build_object('listing_quarantined', true);

  ELSIF p_action = 'restore_listing' THEN
    UPDATE public.marche_ops_controls SET lifted_at=now(), lifted_by=caller, lift_reason=btrim(p_reason_code)
     WHERE control_kind='listing_quarantine' AND subject_listing_id=c.subject_listing_id AND lifted_at IS NULL;
    v_after := jsonb_build_object('listing_quarantined', false);

  ELSIF p_action = 'restrict_user' THEN
    v_subject := COALESCE(c.subject_shopper_user_id, c.subject_customer_user_id);
    INSERT INTO public.marche_ops_controls(control_kind, case_id, subject_user_id,
      reason_code, note, expires_at, applied_by)
    VALUES ('user_restriction', c.id, v_subject, btrim(p_reason_code), p_note,
            (p_params->>'expires_at')::timestamptz, caller);
    v_after := jsonb_build_object('user_restricted', true);

  ELSIF p_action = 'unrestrict_user' THEN
    v_subject := COALESCE(c.subject_shopper_user_id, c.subject_customer_user_id);
    UPDATE public.marche_ops_controls SET lifted_at=now(), lifted_by=caller, lift_reason=btrim(p_reason_code)
     WHERE control_kind='user_restriction' AND subject_user_id=v_subject AND lifted_at IS NULL;
    v_after := jsonb_build_object('user_restricted', false);

  ELSIF p_action = 'moderate_rating' THEN
    INSERT INTO public.marche_ops_reputation_moderations(event_id, case_id, reason_code, note, moderated_by)
    VALUES (c.subject_reputation_event_id, c.id, btrim(p_reason_code), p_note, caller)
    ON CONFLICT (event_id) DO UPDATE SET restored_at=NULL, restored_by=NULL, restore_reason=NULL,
      case_id=EXCLUDED.case_id, reason_code=EXCLUDED.reason_code, moderated_by=EXCLUDED.moderated_by,
      moderated_at=now();
    v_after := jsonb_build_object('rating_moderated', true);

  ELSIF p_action = 'restore_rating' THEN
    UPDATE public.marche_ops_reputation_moderations
       SET restored_at=now(), restored_by=caller, restore_reason=btrim(p_reason_code)
     WHERE event_id = c.subject_reputation_event_id AND restored_at IS NULL;
    v_after := jsonb_build_object('rating_moderated', false);

  ELSIF p_action = 'record_finance_resolution' THEN
    -- Operations never move money. Finance records the canonical reference only.
    v_fin := jsonb_build_object(
      'finance_kind', p_params->>'finance_kind',
      'finance_reference', p_params->>'finance_reference');
    v_after := jsonb_build_object('finance_recorded', true);

  ELSIF p_action IN ('resolve','dismiss') THEN
    UPDATE public.marche_ops_cases
       SET status = CASE WHEN p_action='resolve' THEN 'resolved' ELSE 'dismissed' END,
           resolution_code = btrim(p_reason_code), resolved_at = now(), resolved_by = caller
     WHERE id = c.id;
    v_after := jsonb_build_object('status', CASE WHEN p_action='resolve' THEN 'resolved' ELSE 'dismissed' END);

  ELSIF p_action = 'reopen' THEN
    UPDATE public.marche_ops_cases
       SET status='open', resolution_code=NULL, resolved_at=NULL, resolved_by=NULL
     WHERE id = c.id;
    v_after := jsonb_build_object('status','open');

  ELSE -- add_note, request_evidence, escalate
    v_after := jsonb_build_object('logged', p_action);
    IF p_action = 'escalate' AND c.severity <> 'critical' THEN
      UPDATE public.marche_ops_cases SET severity='critical' WHERE id=c.id;
      v_after := v_after || jsonb_build_object('severity','critical');
    END IF;
  END IF;

  INSERT INTO public.marche_ops_events(case_id, action, actor_user_id, actor_role,
    reason_code, note, request_id, before_state, after_state, finance_ref, metadata)
  VALUES (c.id, p_action, caller, v_role, btrim(p_reason_code), p_note, p_request_id,
          v_before, v_after, v_fin, COALESCE(p_params,'{}'::jsonb));

  RETURN public.marche_ops_case_detail(c.id);
END $function$;
GRANT EXECUTE ON FUNCTION public.marche_ops_command(uuid,text,uuid,text,text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.marche_ops_command(uuid,text,uuid,text,text,jsonb) FROM anon;