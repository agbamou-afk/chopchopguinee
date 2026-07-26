
-- ============================================================
-- Slice D: sandbox_test_runs registry + archive + admin views
-- ============================================================

-- 1) Tighten mock-driver: God Admin only
CREATE OR REPLACE FUNCTION public.om_sandbox_assign_mock_driver(
  p_ride_id uuid,
  p_driver_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public.is_god_admin(v_uid) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_require_active();
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF COALESCE((v_ride.metadata->>'sandbox')::boolean, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'not_a_sandbox_ride'; END IF;
  IF v_ride.status <> 'pending' THEN
    RAISE EXCEPTION 'ride_not_pending: status=%', v_ride.status; END IF;
  IF p_driver_user_id IS NULL THEN RAISE EXCEPTION 'driver_user_id_required'; END IF;

  UPDATE public.rides
     SET driver_id = p_driver_user_id,
         metadata  = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
                       'sandbox_mock_driver_id', p_driver_user_id,
                       'sandbox_mock_assigned_at', now(),
                       'sandbox_mock_assigned_by', v_uid),
         updated_at = now()
   WHERE id = p_ride_id;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.ride.mock_driver_assigned',
          'ride', p_ride_id::text,
          jsonb_build_object('mock_driver_id', p_driver_user_id, 'actor', v_uid));

  RETURN jsonb_build_object('ride_id', p_ride_id, 'driver_id', p_driver_user_id, 'is_sandbox', true);
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_assign_mock_driver(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_assign_mock_driver(uuid,uuid) TO authenticated;

-- 2) sandbox_test_runs registry
CREATE TABLE IF NOT EXISTS public.sandbox_test_runs (
  id          uuid PRIMARY KEY,
  label       text,
  status      text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','completed','archived','needs_review')),
  created_by  uuid,
  started_at  timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  completed_by uuid,
  archived_at  timestamptz,
  archived_by  uuid,
  notes        text,
  metadata     jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.sandbox_test_runs TO authenticated;
GRANT ALL ON public.sandbox_test_runs TO service_role;

ALTER TABLE public.sandbox_test_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sandbox_runs_admin_read ON public.sandbox_test_runs;
CREATE POLICY sandbox_runs_admin_read ON public.sandbox_test_runs
  FOR SELECT TO authenticated
  USING (public.is_god_admin(auth.uid())
         OR public.has_role(auth.uid(), 'finance_admin'::public.app_role));

DROP TRIGGER IF EXISTS trg_sandbox_runs_touch ON public.sandbox_test_runs;
CREATE TRIGGER trg_sandbox_runs_touch
  BEFORE UPDATE ON public.sandbox_test_runs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX IF NOT EXISTS idx_sandbox_runs_status
  ON public.sandbox_test_runs(status, started_at DESC);

-- 3) Auto-register helper (called from creator RPCs going forward; also used by backfill)
CREATE OR REPLACE FUNCTION public._om_sandbox_register_test_run(
  p_test_run_id uuid,
  p_actor uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF p_test_run_id IS NULL THEN RETURN; END IF;
  INSERT INTO public.sandbox_test_runs(id, created_by, status, started_at, metadata)
  VALUES (p_test_run_id, p_actor, 'active', now(),
          jsonb_build_object('auto_registered', true))
  ON CONFLICT (id) DO NOTHING;
END $$;

REVOKE ALL ON FUNCTION public._om_sandbox_register_test_run(uuid,uuid) FROM PUBLIC;

-- 4) Backfill from existing sandbox intents
INSERT INTO public.sandbox_test_runs(id, created_by, status, started_at, metadata)
SELECT DISTINCT ON (pi.test_run_id)
  pi.test_run_id,
  pi.user_id,
  'active',
  MIN(pi.created_at) OVER (PARTITION BY pi.test_run_id),
  jsonb_build_object('backfilled', true)
FROM public.payment_intents pi
WHERE pi.is_sandbox = true AND pi.test_run_id IS NOT NULL
ON CONFLICT (id) DO NOTHING;

-- 5) Complete + Archive RPCs (God Admin only)
CREATE OR REPLACE FUNCTION public.om_sandbox_complete_test_run(
  p_test_run_id uuid,
  p_notes text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_run public.sandbox_test_runs;
BEGIN
  IF v_uid IS NULL OR NOT public.is_god_admin(v_uid) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_register_test_run(p_test_run_id, v_uid);
  SELECT * INTO v_run FROM public.sandbox_test_runs WHERE id = p_test_run_id FOR UPDATE;
  IF v_run.id IS NULL THEN RAISE EXCEPTION 'unknown_test_run'; END IF;
  IF v_run.status = 'archived' THEN RAISE EXCEPTION 'test_run_archived'; END IF;
  IF v_run.status = 'completed' THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'status', 'completed');
  END IF;
  UPDATE public.sandbox_test_runs
     SET status='completed', completed_at=now(), completed_by=v_uid,
         notes = COALESCE(p_notes, notes)
   WHERE id = p_test_run_id;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.test_run.completed',
          'sandbox_test_run', p_test_run_id::text,
          jsonb_build_object('notes', p_notes));

  RETURN jsonb_build_object('ok', true, 'status', 'completed');
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_complete_test_run(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_complete_test_run(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.om_sandbox_archive_test_run(
  p_test_run_id uuid,
  p_notes text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_run public.sandbox_test_runs;
  v_intents_count int := 0;
  v_refunds_count int := 0;
  v_events_count  int := 0;
  v_recon_count   int := 0;
  v_support_count int := 0;
  v_live_leak     int := 0;
BEGIN
  IF v_uid IS NULL OR NOT public.is_god_admin(v_uid) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  PERFORM public._om_sandbox_register_test_run(p_test_run_id, v_uid);
  SELECT * INTO v_run FROM public.sandbox_test_runs WHERE id = p_test_run_id FOR UPDATE;
  IF v_run.id IS NULL THEN RAISE EXCEPTION 'unknown_test_run'; END IF;

  -- Idempotent replay
  IF v_run.status = 'archived' THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'status', 'archived',
                              'archived_at', v_run.archived_at);
  END IF;

  -- Reject mixed / live-leak test runs
  SELECT COUNT(*) INTO v_live_leak
  FROM public.payment_intents
  WHERE test_run_id = p_test_run_id
    AND (is_sandbox = false OR environment = 'production');
  IF v_live_leak > 0 THEN
    RAISE EXCEPTION 'refuse_archive_mixed_or_live_run: live_rows=%', v_live_leak;
  END IF;

  -- Allow archive helper to bypass the "block archived mutations" trigger
  PERFORM set_config('om.archiving', '1', true);

  -- Mark records archived via metadata (never delete)
  UPDATE public.payment_intents
     SET metadata = COALESCE(metadata,'{}'::jsonb)
                    || jsonb_build_object('sandbox_archived_at', now(),
                                          'sandbox_archived_by', v_uid)
   WHERE test_run_id = p_test_run_id AND is_sandbox = true;
  GET DIAGNOSTICS v_intents_count = ROW_COUNT;

  UPDATE public.payment_refund_requests
     SET metadata = COALESCE(metadata,'{}'::jsonb)
                    || jsonb_build_object('sandbox_archived_at', now(),
                                          'sandbox_archived_by', v_uid)
   WHERE test_run_id = p_test_run_id AND is_sandbox = true;
  GET DIAGNOSTICS v_refunds_count = ROW_COUNT;

  UPDATE public.payment_provider_events
     SET raw_payload = COALESCE(raw_payload,'{}'::jsonb)
                       || jsonb_build_object('sandbox_archived_at', now())
   WHERE test_run_id = p_test_run_id AND is_sandbox = true;
  GET DIAGNOSTICS v_events_count = ROW_COUNT;

  UPDATE public.payment_reconciliation_events
     SET metadata = COALESCE(metadata,'{}'::jsonb)
                    || jsonb_build_object('sandbox_archived_at', now())
   WHERE test_run_id = p_test_run_id AND is_sandbox = true;
  GET DIAGNOSTICS v_recon_count = ROW_COUNT;

  SELECT COUNT(*) INTO v_support_count
  FROM public.support_issues
  WHERE (metadata->>'test_run_id')::uuid = p_test_run_id
    AND COALESCE((metadata->>'is_sandbox')::boolean, false) = true;

  UPDATE public.sandbox_test_runs
     SET status='archived', archived_at=now(), archived_by=v_uid,
         notes = COALESCE(p_notes, notes),
         metadata = COALESCE(metadata,'{}'::jsonb)
                    || jsonb_build_object(
                      'archive_counts',
                      jsonb_build_object(
                        'payment_intents', v_intents_count,
                        'refund_requests', v_refunds_count,
                        'provider_events', v_events_count,
                        'reconciliation_events', v_recon_count,
                        'support_issues', v_support_count
                      ))
   WHERE id = p_test_run_id;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.test_run.archived',
          'sandbox_test_run', p_test_run_id::text,
          jsonb_build_object(
            'notes', p_notes,
            'counts', jsonb_build_object(
              'payment_intents', v_intents_count,
              'refund_requests', v_refunds_count,
              'provider_events', v_events_count,
              'reconciliation_events', v_recon_count,
              'support_issues', v_support_count)));

  RETURN jsonb_build_object(
    'ok', true, 'status', 'archived',
    'counts', jsonb_build_object(
      'payment_intents', v_intents_count,
      'refund_requests', v_refunds_count,
      'provider_events', v_events_count,
      'reconciliation_events', v_recon_count,
      'support_issues', v_support_count));
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_archive_test_run(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_archive_test_run(uuid,text) TO authenticated;

-- 6) Block further mutations on archived sandbox rows
CREATE OR REPLACE FUNCTION public._om_sandbox_block_archived()
RETURNS trigger LANGUAGE plpgsql SET search_path = public
AS $$
BEGIN
  IF current_setting('om.archiving', true) = '1' THEN
    RETURN NEW;
  END IF;
  IF NEW.test_run_id IS NULL OR COALESCE(NEW.is_sandbox, false) = false THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.sandbox_test_runs
    WHERE id = NEW.test_run_id AND status = 'archived'
  ) THEN
    RAISE EXCEPTION 'sandbox_test_run_archived' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_block_archived_intents ON public.payment_intents;
CREATE TRIGGER trg_block_archived_intents
  BEFORE INSERT OR UPDATE ON public.payment_intents
  FOR EACH ROW EXECUTE FUNCTION public._om_sandbox_block_archived();

DROP TRIGGER IF EXISTS trg_block_archived_refunds ON public.payment_refund_requests;
CREATE TRIGGER trg_block_archived_refunds
  BEFORE INSERT OR UPDATE ON public.payment_refund_requests
  FOR EACH ROW EXECUTE FUNCTION public._om_sandbox_block_archived();

-- 7) Read-only admin helpers
CREATE OR REPLACE FUNCTION public.om_sandbox_admin_metrics()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_res jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT (public.is_god_admin(v_uid)
          OR public.has_role(v_uid, 'finance_admin'::public.app_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT jsonb_build_object(
    'total_runs',    (SELECT COUNT(*) FROM public.sandbox_test_runs),
    'active_runs',   (SELECT COUNT(*) FROM public.sandbox_test_runs WHERE status='active'),
    'completed_runs',(SELECT COUNT(*) FROM public.sandbox_test_runs WHERE status='completed'),
    'archived_runs', (SELECT COUNT(*) FROM public.sandbox_test_runs WHERE status='archived'),
    'intents_by_state', COALESCE((
      SELECT jsonb_object_agg(state, c) FROM (
        SELECT state::text AS state, COUNT(*) AS c FROM public.payment_intents
        WHERE is_sandbox=true GROUP BY state
      ) s), '{}'::jsonb),
    'refunds_by_state', COALESCE((
      SELECT jsonb_object_agg(status, c) FROM (
        SELECT status, COUNT(*) AS c FROM public.payment_refund_requests
        WHERE is_sandbox=true GROUP BY status
      ) s), '{}'::jsonb),
    'events_total',  (SELECT COUNT(*) FROM public.payment_provider_events WHERE is_sandbox=true),
    'needs_review',  (SELECT COUNT(*) FROM public.payment_intents WHERE is_sandbox=true AND state='needs_review'),
    'finalize_fails',(SELECT COUNT(*) FROM public.payment_intents WHERE is_sandbox=true AND metadata ? 'sandbox_finalize_failed'),
    'module_counts', COALESCE((
      SELECT jsonb_object_agg(source_module, c) FROM (
        SELECT COALESCE(source_module,'unknown') AS source_module, COUNT(*) AS c
        FROM public.payment_intents WHERE is_sandbox=true GROUP BY 1
      ) m), '{}'::jsonb),
    'oldest_unresolved', (
      SELECT MIN(created_at) FROM public.payment_intents
      WHERE is_sandbox=true AND state IN ('pending','processing','proof_submitted','in_review','needs_review','authorized')
    )
  ) INTO v_res;
  RETURN v_res;
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_admin_metrics() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_admin_metrics() TO authenticated;

CREATE OR REPLACE FUNCTION public.om_sandbox_admin_list_runs(p_limit int DEFAULT 100)
RETURNS TABLE (
  id uuid, label text, status text,
  started_at timestamptz, last_activity_at timestamptz,
  created_by uuid,
  intent_count int, refund_count int, event_count int,
  support_count int, unresolved_count int,
  modules text[], archived_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT (public.is_god_admin(v_uid)
          OR public.has_role(v_uid, 'finance_admin'::public.app_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  RETURN QUERY
  SELECT r.id, r.label, r.status, r.started_at,
    GREATEST(
      r.started_at,
      COALESCE((SELECT MAX(created_at) FROM public.payment_intents WHERE test_run_id=r.id), r.started_at),
      COALESCE((SELECT MAX(created_at) FROM public.payment_provider_events WHERE test_run_id=r.id), r.started_at)
    ) AS last_activity_at,
    r.created_by,
    COALESCE((SELECT COUNT(*)::int FROM public.payment_intents WHERE test_run_id=r.id AND is_sandbox=true),0),
    COALESCE((SELECT COUNT(*)::int FROM public.payment_refund_requests WHERE test_run_id=r.id AND is_sandbox=true),0),
    COALESCE((SELECT COUNT(*)::int FROM public.payment_provider_events WHERE test_run_id=r.id AND is_sandbox=true),0),
    COALESCE((SELECT COUNT(*)::int FROM public.support_issues WHERE (metadata->>'test_run_id')::uuid = r.id),0),
    COALESCE((SELECT COUNT(*)::int FROM public.payment_intents
              WHERE test_run_id=r.id AND is_sandbox=true
                AND state IN ('pending','processing','proof_submitted','in_review','needs_review','authorized')),0),
    COALESCE(ARRAY(
      SELECT DISTINCT COALESCE(source_module,'unknown')
      FROM public.payment_intents WHERE test_run_id=r.id AND is_sandbox=true
    ), ARRAY[]::text[]),
    r.archived_at
  FROM public.sandbox_test_runs r
  ORDER BY r.started_at DESC
  LIMIT p_limit;
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_admin_list_runs(int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_admin_list_runs(int) TO authenticated;

CREATE OR REPLACE FUNCTION public.om_sandbox_admin_run_detail(p_test_run_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_res jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT (public.is_god_admin(v_uid)
          OR public.has_role(v_uid, 'finance_admin'::public.app_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT jsonb_build_object(
    'run', to_jsonb(r),
    'intents', COALESCE((
      SELECT jsonb_agg(to_jsonb(i) ORDER BY i.created_at DESC)
      FROM public.payment_intents i WHERE i.test_run_id = p_test_run_id AND i.is_sandbox=true
    ), '[]'::jsonb),
    'refunds', COALESCE((
      SELECT jsonb_agg(to_jsonb(rf) ORDER BY rf.created_at DESC)
      FROM public.payment_refund_requests rf WHERE rf.test_run_id = p_test_run_id AND rf.is_sandbox=true
    ), '[]'::jsonb),
    'provider_events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', pe.id, 'provider', pe.provider, 'kind', pe.event_kind,
        'provider_transaction_id', pe.provider_transaction_id,
        'amount_gnf', pe.amount_gnf, 'created_at', pe.created_at,
        'payment_intent_id', pe.payment_intent_id
      ) ORDER BY pe.created_at DESC)
      FROM public.payment_provider_events pe WHERE pe.test_run_id = p_test_run_id AND pe.is_sandbox=true
    ), '[]'::jsonb),
    'reconciliation', COALESCE((
      SELECT jsonb_agg(to_jsonb(re) ORDER BY re.created_at DESC)
      FROM public.payment_reconciliation_events re WHERE re.test_run_id = p_test_run_id AND re.is_sandbox=true
    ), '[]'::jsonb),
    'support_issues', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', s.id, 'category', s.category, 'severity', s.severity,
        'status', s.status, 'created_at', s.created_at,
        'summary', s.summary
      ) ORDER BY s.created_at DESC)
      FROM public.support_issues s
      WHERE (s.metadata->>'test_run_id')::uuid = p_test_run_id
    ), '[]'::jsonb)
  ) INTO v_res
  FROM public.sandbox_test_runs r
  WHERE r.id = p_test_run_id;

  IF v_res IS NULL THEN RAISE EXCEPTION 'unknown_test_run'; END IF;
  RETURN v_res;
END $$;

REVOKE ALL ON FUNCTION public.om_sandbox_admin_run_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_admin_run_detail(uuid) TO authenticated;

-- 8) Own refund requests view for wallet UX (RLS already permits owner read on payment_refund_requests)
-- No new object needed; frontend queries the table directly with user_id filter.

COMMENT ON TABLE public.sandbox_test_runs IS
  'Sandbox-only registry of Orange Money test runs. God Admin manages lifecycle (active/completed/archived). Never contains production data.';
