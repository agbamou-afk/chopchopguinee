-- ============================================================
-- Node 4 — Marché R9: VERIFIED REPUTATION (canonical model)
-- ============================================================

CREATE TABLE public.marche_reputation_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_kind text NOT NULL,
  transaction_id uuid NOT NULL,
  rater_user_id uuid NOT NULL,
  subject_kind text NOT NULL,
  subject_store_id uuid,
  subject_user_id uuid,
  overall_score integer NOT NULL,
  comment text,
  provenance jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_reputation_kind_chk
    CHECK (transaction_kind IN ('merchant_order','procurement')),
  CONSTRAINT marche_reputation_subject_kind_chk
    CHECK (subject_kind IN ('merchant_store','delivery_driver','shopper')),
  CONSTRAINT marche_reputation_score_chk
    CHECK (overall_score BETWEEN 1 AND 5),
  CONSTRAINT marche_reputation_comment_chk
    CHECK (comment IS NULL OR char_length(comment) <= 1000),
  CONSTRAINT marche_reputation_subject_identity_chk CHECK (
    (subject_kind = 'merchant_store' AND subject_store_id IS NOT NULL AND subject_user_id IS NULL)
    OR (subject_kind IN ('delivery_driver','shopper') AND subject_user_id IS NOT NULL AND subject_store_id IS NULL)
  ),
  CONSTRAINT marche_reputation_no_self_chk
    CHECK (subject_user_id IS NULL OR subject_user_id <> rater_user_id)
);

CREATE UNIQUE INDEX marche_reputation_unique_identity
  ON public.marche_reputation_events(transaction_kind, transaction_id, rater_user_id, subject_kind);
CREATE INDEX marche_reputation_subject_store_idx
  ON public.marche_reputation_events(subject_store_id) WHERE subject_store_id IS NOT NULL;
CREATE INDEX marche_reputation_subject_user_idx
  ON public.marche_reputation_events(subject_kind, subject_user_id) WHERE subject_user_id IS NOT NULL;

CREATE TABLE public.marche_reputation_dimensions (
  event_id uuid NOT NULL REFERENCES public.marche_reputation_events(id),
  dimension text NOT NULL,
  score integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, dimension),
  CONSTRAINT marche_reputation_dimension_score_chk CHECK (score BETWEEN 1 AND 5)
);

-- RPC-only: no direct client reach at all.
REVOKE ALL ON public.marche_reputation_events FROM anon, authenticated;
REVOKE ALL ON public.marche_reputation_dimensions FROM anon, authenticated;
GRANT ALL ON public.marche_reputation_events TO service_role;
GRANT ALL ON public.marche_reputation_dimensions TO service_role;
ALTER TABLE public.marche_reputation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marche_reputation_dimensions ENABLE ROW LEVEL SECURITY;

-- ---------- physical append-only law ----------
CREATE OR REPLACE FUNCTION public._marche_reputation_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  RAISE EXCEPTION 'REPUTATION_IMMUTABLE';
END $$;

CREATE TRIGGER trg_marche_reputation_events_immutable
  BEFORE UPDATE OR DELETE ON public.marche_reputation_events
  FOR EACH ROW EXECUTE FUNCTION public._marche_reputation_immutable();
CREATE TRIGGER trg_marche_reputation_dimensions_immutable
  BEFORE UPDATE OR DELETE ON public.marche_reputation_dimensions
  FOR EACH ROW EXECUTE FUNCTION public._marche_reputation_immutable();

-- ---------- exact allowed dimension vocabulary ----------
CREATE OR REPLACE FUNCTION public.marche_reputation_dimensions_for(p_subject_kind text)
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE p_subject_kind
    WHEN 'merchant_store'  THEN ARRAY['quality','accuracy','availability','packaging','preparation','value']
    WHEN 'delivery_driver' THEN ARRAY['courtesy','communication','timeliness','order_care']
    WHEN 'shopper'         THEN ARRAY['selection_quality','freshness','substitution_quality','shopping_accuracy']
    ELSE ARRAY[]::text[] END
$$;

-- ---------- canonical completion truth + subject derivation ----------
CREATE OR REPLACE FUNCTION public._marche_reputation_resolve(p_kind text, p_tx uuid, p_caller uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o public.marche_orders; m public.missions; s public.merchant_stores;
  req public.marche_procurement_requests; pm public.marche_procurement_missions;
  subs jsonb := '[]'::jsonb; v_completed timestamptz; v_ok boolean := false;
  v_reason text := 'NOT_COMPLETED'; v_label text;
BEGIN
  IF p_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  IF p_kind = 'merchant_order' THEN
    SELECT * INTO o FROM public.marche_orders WHERE id = p_tx;
    IF o.id IS NULL THEN RAISE EXCEPTION 'TRANSACTION_NOT_FOUND'; END IF;
    IF o.buyer_user_id IS DISTINCT FROM p_caller THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
    IF o.status <> 'committed' THEN
      v_reason := 'ORDER_NOT_ACTIVE';
    ELSIF o.fulfillment_state = 'delivered' AND o.delivered_at IS NOT NULL THEN
      v_ok := true; v_reason := NULL; v_completed := o.delivered_at;
      SELECT * INTO s FROM public.merchant_stores WHERE id = o.merchant_store_id;
      IF o.merchant_user_id IS DISTINCT FROM p_caller
         AND COALESCE(s.owner_user_id, '00000000-0000-0000-0000-000000000000'::uuid) IS DISTINCT FROM p_caller THEN
        subs := subs || jsonb_build_array(jsonb_build_object(
          'subject_kind','merchant_store',
          'subject_store_id', o.merchant_store_id,
          'subject_user_id', NULL,
          'subject_label', COALESCE(s.name,'Boutique')));
      END IF;
      IF o.mission_id IS NOT NULL THEN
        SELECT * INTO m FROM public.missions WHERE id = o.mission_id;
        IF m.id IS NOT NULL AND m.courier_id IS NOT NULL
           AND m.state = 'delivered' AND m.courier_id <> p_caller THEN
          SELECT NULLIF(btrim(COALESCE(first_name,'') || ' ' || COALESCE(last_name,'')), '')
            INTO v_label FROM public.profiles WHERE user_id = m.courier_id;
          subs := subs || jsonb_build_array(jsonb_build_object(
            'subject_kind','delivery_driver',
            'subject_store_id', NULL,
            'subject_user_id', m.courier_id,
            'subject_label', COALESCE(v_label,'Livreur')));
        END IF;
      END IF;
    END IF;

  ELSIF p_kind = 'procurement' THEN
    SELECT * INTO req FROM public.marche_procurement_requests WHERE id = p_tx;
    IF req.id IS NULL THEN RAISE EXCEPTION 'TRANSACTION_NOT_FOUND'; END IF;
    IF req.buyer_user_id IS DISTINCT FROM p_caller THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
    SELECT * INTO pm FROM public.marche_procurement_missions WHERE request_id = p_tx;
    IF pm.id IS NULL THEN
      v_reason := 'PROCUREMENT_NOT_STARTED';
    ELSIF pm.state = 'completed' AND pm.completed_at IS NOT NULL THEN
      v_ok := true; v_reason := NULL; v_completed := pm.completed_at;
      IF pm.shopper_user_id IS NOT NULL AND pm.shopper_user_id <> p_caller THEN
        SELECT NULLIF(btrim(COALESCE(first_name,'') || ' ' || COALESCE(last_name,'')), '')
          INTO v_label FROM public.profiles WHERE user_id = pm.shopper_user_id;
        subs := subs || jsonb_build_array(jsonb_build_object(
          'subject_kind','shopper',
          'subject_store_id', NULL,
          'subject_user_id', pm.shopper_user_id,
          'subject_label', COALESCE(v_label,'Acheteur CHOP CHOP')));
      END IF;
    END IF;

  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_TRANSACTION_KIND';
  END IF;

  RETURN jsonb_build_object(
    'eligible', v_ok, 'reason', v_reason,
    'transaction_kind', p_kind, 'transaction_id', p_tx,
    'completed_at', v_completed, 'subjects', subs);
END $$;

REVOKE ALL ON FUNCTION public._marche_reputation_resolve(text,uuid,uuid) FROM PUBLIC, anon, authenticated;

-- ---------- customer-facing eligibility (no subject ids leaked) ----------
CREATE OR REPLACE FUNCTION public.marche_reputation_eligibility(p_transaction_kind text, p_transaction_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  caller uuid := auth.uid(); base jsonb; sub jsonb; out_subs jsonb := '[]'::jsonb;
  v_ev public.marche_reputation_events;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  base := public._marche_reputation_resolve(p_transaction_kind, p_transaction_id, caller);

  FOR sub IN SELECT * FROM jsonb_array_elements(base->'subjects') LOOP
    SELECT * INTO v_ev FROM public.marche_reputation_events
     WHERE transaction_kind = p_transaction_kind AND transaction_id = p_transaction_id
       AND rater_user_id = caller AND subject_kind = sub->>'subject_kind';
    out_subs := out_subs || jsonb_build_array(jsonb_build_object(
      'subject_kind', sub->>'subject_kind',
      'subject_label', sub->>'subject_label',
      'dimensions', to_jsonb(public.marche_reputation_dimensions_for(sub->>'subject_kind')),
      'already_rated', v_ev.id IS NOT NULL,
      'my_overall_score', v_ev.overall_score));
  END LOOP;

  RETURN jsonb_build_object(
    'eligible', (base->>'eligible')::boolean,
    'reason', base->>'reason',
    'transaction_kind', p_transaction_kind,
    'transaction_id', p_transaction_id,
    'completed_at', base->>'completed_at',
    'subjects', out_subs);
END $$;

GRANT EXECUTE ON FUNCTION public.marche_reputation_eligibility(text,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.marche_reputation_eligibility(text,uuid) FROM anon;

-- ---------- submit ----------
CREATE OR REPLACE FUNCTION public.marche_reputation_submit(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  caller uuid := auth.uid();
  v_kind text := p_payload->>'transaction_kind';
  v_tx uuid;
  v_subject_kind text := p_payload->>'subject_kind';
  v_overall numeric;
  v_comment text;
  base jsonb; sub jsonb; chosen jsonb;
  allowed text[]; k text; v_val jsonb;
  v_event uuid;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_payload ? 'subject_store_id' OR p_payload ? 'subject_user_id'
     OR p_payload ? 'subject_id' THEN
    RAISE EXCEPTION 'CLIENT_SUBJECT_NOT_ALLOWED';
  END IF;
  IF p_payload ? 'overall_average' OR p_payload ? 'rating_count' THEN
    RAISE EXCEPTION 'CLIENT_AGGREGATE_NOT_ALLOWED';
  END IF;
  IF (p_payload->>'transaction_id') IS NULL THEN RAISE EXCEPTION 'TRANSACTION_REQUIRED'; END IF;
  v_tx := (p_payload->>'transaction_id')::uuid;
  IF v_subject_kind IS NULL OR NOT (v_subject_kind IN ('merchant_store','delivery_driver','shopper')) THEN
    RAISE EXCEPTION 'INVALID_SUBJECT_KIND';
  END IF;

  IF jsonb_typeof(p_payload->'overall_score') <> 'number' THEN RAISE EXCEPTION 'INVALID_SCORE'; END IF;
  v_overall := (p_payload->>'overall_score')::numeric;
  IF v_overall <> trunc(v_overall) OR v_overall < 1 OR v_overall > 5 THEN
    RAISE EXCEPTION 'INVALID_SCORE';
  END IF;

  v_comment := NULLIF(btrim(COALESCE(p_payload->>'comment','')), '');
  IF v_comment IS NOT NULL AND char_length(v_comment) > 1000 THEN
    RAISE EXCEPTION 'COMMENT_TOO_LONG';
  END IF;

  base := public._marche_reputation_resolve(v_kind, v_tx, caller);
  IF NOT (base->>'eligible')::boolean THEN
    RAISE EXCEPTION 'TRANSACTION_NOT_COMPLETED' USING DETAIL = COALESCE(base->>'reason','');
  END IF;

  FOR sub IN SELECT * FROM jsonb_array_elements(base->'subjects') LOOP
    IF sub->>'subject_kind' = v_subject_kind THEN chosen := sub; END IF;
  END LOOP;
  IF chosen IS NULL THEN RAISE EXCEPTION 'SUBJECT_NOT_AVAILABLE'; END IF;

  allowed := public.marche_reputation_dimensions_for(v_subject_kind);
  IF p_payload ? 'dimensions' AND jsonb_typeof(p_payload->'dimensions') <> 'null' THEN
    IF jsonb_typeof(p_payload->'dimensions') <> 'object' THEN RAISE EXCEPTION 'INVALID_DIMENSION'; END IF;
    FOR k, v_val IN SELECT * FROM jsonb_each(p_payload->'dimensions') LOOP
      IF NOT (k = ANY(allowed)) THEN RAISE EXCEPTION 'INVALID_DIMENSION' USING DETAIL = k; END IF;
      IF jsonb_typeof(v_val) <> 'number' THEN RAISE EXCEPTION 'INVALID_SCORE' USING DETAIL = k; END IF;
      IF (v_val::text)::numeric <> trunc((v_val::text)::numeric)
         OR (v_val::text)::numeric < 1 OR (v_val::text)::numeric > 5 THEN
        RAISE EXCEPTION 'INVALID_SCORE' USING DETAIL = k;
      END IF;
    END LOOP;
  END IF;

  INSERT INTO public.marche_reputation_events(
    transaction_kind, transaction_id, rater_user_id, subject_kind,
    subject_store_id, subject_user_id, overall_score, comment, provenance)
  VALUES (
    v_kind, v_tx, caller, v_subject_kind,
    NULLIF(chosen->>'subject_store_id','')::uuid,
    NULLIF(chosen->>'subject_user_id','')::uuid,
    v_overall::int, v_comment,
    jsonb_build_object('completed_at', base->>'completed_at',
                       'transaction_kind', v_kind,
                       'verified', true,
                       'recorded_by','marche_reputation_submit'))
  ON CONFLICT (transaction_kind, transaction_id, rater_user_id, subject_kind) DO NOTHING
  RETURNING id INTO v_event;

  IF v_event IS NULL THEN
    SELECT id INTO v_event FROM public.marche_reputation_events
     WHERE transaction_kind = v_kind AND transaction_id = v_tx
       AND rater_user_id = caller AND subject_kind = v_subject_kind;
    RETURN jsonb_build_object('event_id', v_event, 'status','ALREADY_RATED',
                              'already_rated', true, 'subject_kind', v_subject_kind);
  END IF;

  IF p_payload ? 'dimensions' AND jsonb_typeof(p_payload->'dimensions') = 'object' THEN
    INSERT INTO public.marche_reputation_dimensions(event_id, dimension, score)
    SELECT v_event, key, (value::text)::int FROM jsonb_each(p_payload->'dimensions');
  END IF;

  RETURN jsonb_build_object('event_id', v_event, 'status','RECORDED',
                            'already_rated', false, 'subject_kind', v_subject_kind,
                            'overall_score', v_overall::int);
END $$;

GRANT EXECUTE ON FUNCTION public.marche_reputation_submit(jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.marche_reputation_submit(jsonb) FROM anon;

-- ---------- sanitized public aggregate ----------
CREATE OR REPLACE FUNCTION public.marche_reputation_summary(p_subject_kind text, p_subject_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_count bigint; v_avg numeric; v_last timestamptz; v_dims jsonb;
BEGIN
  IF p_subject_kind NOT IN ('merchant_store','delivery_driver','shopper') THEN
    RAISE EXCEPTION 'INVALID_SUBJECT_KIND';
  END IF;
  IF p_subject_id IS NULL THEN RAISE EXCEPTION 'SUBJECT_REQUIRED'; END IF;

  SELECT count(*), avg(overall_score), max(created_at)
    INTO v_count, v_avg, v_last
    FROM public.marche_reputation_events
   WHERE subject_kind = p_subject_kind
     AND ((p_subject_kind = 'merchant_store' AND subject_store_id = p_subject_id)
       OR (p_subject_kind <> 'merchant_store' AND subject_user_id = p_subject_id));

  IF COALESCE(v_count,0) = 0 THEN
    RETURN jsonb_build_object(
      'subject_kind', p_subject_kind, 'subject_id', p_subject_id,
      'has_reputation', false, 'rating_count', 0,
      'overall_average', NULL, 'last_rated_at', NULL,
      'dimensions', '[]'::jsonb);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'dimension', d.dimension,
           'average', round(d.avg_score, 2),
           'count', d.cnt) ORDER BY d.dimension), '[]'::jsonb)
    INTO v_dims
    FROM (
      SELECT dm.dimension, avg(dm.score) avg_score, count(*) cnt
        FROM public.marche_reputation_dimensions dm
        JOIN public.marche_reputation_events e ON e.id = dm.event_id
       WHERE e.subject_kind = p_subject_kind
         AND ((p_subject_kind = 'merchant_store' AND e.subject_store_id = p_subject_id)
           OR (p_subject_kind <> 'merchant_store' AND e.subject_user_id = p_subject_id))
       GROUP BY dm.dimension
    ) d;

  RETURN jsonb_build_object(
    'subject_kind', p_subject_kind, 'subject_id', p_subject_id,
    'has_reputation', true, 'rating_count', v_count,
    'overall_average', round(v_avg, 2), 'last_rated_at', v_last,
    'dimensions', v_dims);
END $$;

GRANT EXECUTE ON FUNCTION public.marche_reputation_summary(text,uuid) TO anon, authenticated;