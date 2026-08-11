-- =========================================================
-- SLICE 7 — CHOP PAY + MERCHANT LEDGER-TRUTH READ MODELS
-- Read-only surfaces + merchant settlement REQUEST model.
-- No money movement. No rail activation.
-- =========================================================

-- ---------- 1. MERCHANT SETTLEMENT REQUESTS (request-only) ----------
CREATE TABLE IF NOT EXISTS public.merchant_settlement_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_key text NOT NULL UNIQUE,
  merchant_store_id uuid NOT NULL,
  merchant_user_id uuid NOT NULL,
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  eligible_snapshot_gnf bigint NOT NULL CHECK (eligible_snapshot_gnf >= 0),
  currency text NOT NULL DEFAULT 'GNF',
  status text NOT NULL DEFAULT 'requested'
    CHECK (status IN ('requested','pending_review','rejected','cancelled','settled')),
  channel text NOT NULL DEFAULT 'manual_review',
  note text,
  reject_reason text,
  evidence_ref text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  settled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.merchant_settlement_requests TO authenticated;
GRANT ALL ON public.merchant_settlement_requests TO service_role;

ALTER TABLE public.merchant_settlement_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants read own settlement requests" ON public.merchant_settlement_requests;
CREATE POLICY "Merchants read own settlement requests"
  ON public.merchant_settlement_requests FOR SELECT TO authenticated
  USING (
    merchant_user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.merchant_stores ms
                WHERE ms.id = merchant_settlement_requests.merchant_store_id
                  AND ms.owner_user_id = auth.uid())
  );

DROP POLICY IF EXISTS "Finance admins read settlement requests" ON public.merchant_settlement_requests;
CREATE POLICY "Finance admins read settlement requests"
  ON public.merchant_settlement_requests FOR SELECT TO authenticated
  USING (
    public.is_god_admin(auth.uid())
    OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role)
    OR public.has_admin_role(auth.uid(), 'operations_admin'::admin_role)
  );

CREATE INDEX IF NOT EXISTS idx_msr_store ON public.merchant_settlement_requests (merchant_store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_msr_status ON public.merchant_settlement_requests (status);

CREATE OR REPLACE FUNCTION public._msr_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.request_key IS DISTINCT FROM OLD.request_key
     OR NEW.amount_gnf IS DISTINCT FROM OLD.amount_gnf
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.merchant_user_id IS DISTINCT FROM OLD.merchant_user_id
     OR NEW.eligible_snapshot_gnf IS DISTINCT FROM OLD.eligible_snapshot_gnf
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'MERCHANT_SETTLEMENT_REQUEST_IMMUTABLE';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_msr_immutable ON public.merchant_settlement_requests;
CREATE TRIGGER trg_msr_immutable BEFORE UPDATE ON public.merchant_settlement_requests
  FOR EACH ROW EXECUTE FUNCTION public._msr_immutable();

-- ---------- 2. CUSTOMER READ MODELS ----------

CREATE OR REPLACE FUNCTION public.customer_finance_overview()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_w public.wallets;
  v_spend bigint := 0; v_refund bigint := 0;
  v_topup_credited bigint := 0; v_topup_pending bigint := 0; v_topup_pending_n int := 0;
  v_open_holds bigint := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'client';

  -- Ecosystem spend: captured/settled outbound spend only.
  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_spend
    FROM public.wallet_transactions
   WHERE from_wallet_id = v_w.id
     AND status = 'completed'
     AND type IN ('payment','capture','commission');

  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_refund
    FROM public.wallet_transactions
   WHERE to_wallet_id = v_w.id AND status = 'completed' AND type = 'refund';

  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_topup_credited
    FROM public.wallet_transactions
   WHERE to_wallet_id = v_w.id AND status = 'completed' AND type = 'topup';

  SELECT COALESCE(SUM(amount_gnf), 0), COUNT(*)
    INTO v_topup_pending, v_topup_pending_n
    FROM public.topup_requests
   WHERE client_user_id = v_uid
     AND COALESCE(target_party_type,'client') = 'client'
     AND status IN ('pending','matched','needs_review');

  SELECT COALESCE(SUM(amount_gnf - captured_gnf - released_gnf), 0) INTO v_open_holds
    FROM public.mission_financial_holds
   WHERE party_user_id = v_uid AND party_type = 'client'
     AND state IN ('held','frozen','partially_captured');

  RETURN jsonb_build_object(
    'wallet_id', v_w.id,
    'has_wallet', v_w.id IS NOT NULL,
    'status', COALESCE(v_w.status::text, 'active'),
    'balance_gnf', COALESCE(v_w.balance_gnf, 0),
    'held_gnf', COALESCE(v_w.held_gnf, 0),
    'available_gnf', GREATEST(COALESCE(v_w.balance_gnf,0) - COALESCE(v_w.held_gnf,0), 0),
    'open_hold_gnf', v_open_holds,
    'holds_reconciled', v_open_holds = COALESCE(v_w.held_gnf, 0),
    'ecosystem_spend_gnf', v_spend,
    'refund_total_gnf', v_refund,
    'topup_credited_gnf', v_topup_credited,
    'topup_pending_gnf', v_topup_pending,
    'topup_pending_count', v_topup_pending_n
  );
END $$;

CREATE OR REPLACE FUNCTION public.customer_finance_history(p_limit integer DEFAULT 50)
RETURNS TABLE(
  event_id uuid, source text, reference text, kind text, direction text,
  amount_gnf bigint, status text, label text, module text,
  counts_as_balance boolean, occurred_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wid uuid;
  v_lim integer := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT id INTO v_wid FROM public.wallets WHERE owner_user_id = v_uid AND party_type = 'client';

  RETURN QUERY
  SELECT * FROM (
    SELECT t.id, 'wallet_transaction'::text, t.reference, t.type::text,
           CASE WHEN t.to_wallet_id = v_wid THEN 'in' ELSE 'out' END::text,
           t.amount_gnf, t.status::text,
           COALESCE(t.description, t.reference),
           COALESCE(t.related_entity, 'wallet'),
           (t.status = 'completed'),
           t.created_at
      FROM public.wallet_transactions t
     WHERE v_wid IS NOT NULL AND (t.from_wallet_id = v_wid OR t.to_wallet_id = v_wid)
    UNION ALL
    SELECT r.id, 'topup_request'::text, r.reference, 'topup'::text, 'in'::text,
           r.amount_gnf, r.status::text,
           'Recharge ' || r.provider, 'topup'::text,
           false, r.created_at
      FROM public.topup_requests r
     WHERE r.client_user_id = v_uid
       AND COALESCE(r.target_party_type,'client') = 'client'
       AND r.status IN ('pending','matched','needs_review','cancelled','expired','failed')
  ) e(event_id, source, reference, kind, direction, amount_gnf, status, label, module, counts_as_balance, occurred_at)
  ORDER BY e.occurred_at DESC
  LIMIT v_lim;
END $$;

CREATE OR REPLACE FUNCTION public.customer_receipt(p_transaction_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wid uuid;
  v_t public.wallet_transactions;
  v_journal jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT id INTO v_wid FROM public.wallets WHERE owner_user_id = v_uid AND party_type = 'client';
  SELECT * INTO v_t FROM public.wallet_transactions
   WHERE id = p_transaction_id
     AND (from_wallet_id = v_wid OR to_wallet_id = v_wid);
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'RECEIPT_NOT_FOUND'; END IF;

  SELECT to_jsonb(j) INTO v_journal
    FROM (SELECT lj.id, lj.journal_key, lj.created_at
            FROM public.ledger_journals lj
           WHERE lj.journal_key = v_t.reference
           LIMIT 1) j;

  RETURN jsonb_build_object(
    'transaction_id', v_t.id,
    'reference', v_t.reference,
    'kind', v_t.type::text,
    'status', v_t.status::text,
    'amount_gnf', v_t.amount_gnf,
    'direction', CASE WHEN v_t.to_wallet_id = v_wid THEN 'in' ELSE 'out' END,
    'description', v_t.description,
    'module', COALESCE(v_t.related_entity, 'wallet'),
    'created_at', v_t.created_at,
    'completed_at', v_t.completed_at,
    'journal', v_journal,
    'has_journal_provenance', v_journal IS NOT NULL
  );
END $$;

-- Customer top-up history must exclude driver-target top-ups.
CREATE OR REPLACE FUNCTION public.list_my_topup_requests(p_limit integer DEFAULT 20)
RETURNS TABLE(id uuid, reference text, amount_gnf bigint, status text, provider text,
  created_at timestamptz, updated_at timestamptz, expires_at timestamptz,
  confirmed_at timestamptz, cancelled_reason text, customer_code_submitted_at timestamptz,
  receiving_label text, receiving_phone text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.reference, t.amount_gnf, t.status::text, t.provider,
         t.created_at, t.updated_at, t.expires_at, t.confirmed_at,
         t.cancelled_reason, t.customer_om_code_submitted_at,
         a.label, a.phone_e164
    FROM public.topup_requests t
    LEFT JOIN public.payment_receiving_accounts a ON a.id = t.receiving_account_id
   WHERE t.client_user_id = auth.uid()
     AND COALESCE(t.target_party_type,'client') = 'client'
   ORDER BY t.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100));
$$;

-- ---------- 3. DRIVER TOP-UP HISTORY (driver-target scoped) ----------
CREATE OR REPLACE FUNCTION public.driver_topup_history(p_limit integer DEFAULT 20)
RETURNS TABLE(id uuid, reference text, amount_gnf bigint, status text, provider text,
  created_at timestamptz, confirmed_at timestamptz, cancelled_reason text,
  credited_transaction_id uuid, credited boolean,
  receiving_label text, receiving_phone text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.reference, t.amount_gnf, t.status::text, t.provider,
         t.created_at, t.confirmed_at, t.cancelled_reason,
         t.transaction_id,
         (t.transaction_id IS NOT NULL AND t.status IN ('confirmed','credited')),
         a.label, a.phone_e164
    FROM public.topup_requests t
    LEFT JOIN public.payment_receiving_accounts a ON a.id = t.receiving_account_id
   WHERE t.client_user_id = auth.uid()
     AND t.target_party_type = 'driver'
   ORDER BY t.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100));
$$;

-- ---------- 4. MERCHANT READ MODELS ----------
CREATE OR REPLACE FUNCTION public.merchant_finance_overview(p_store_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_store uuid := p_store_id;
  v_owner uuid;
  v_w public.wallets;
  v_pending bigint := 0; v_funded bigint := 0; v_settled bigint := 0;
  v_reversed bigint := 0; v_held_state bigint := 0;
  v_open_req bigint := 0; v_eligible bigint := 0; v_avail bigint := 0;
  v_settlement_on boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  IF v_store IS NULL THEN
    SELECT id INTO v_store FROM public.merchant_stores WHERE owner_user_id = v_uid LIMIT 1;
  END IF;
  IF v_store IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_NOT_FOUND'; END IF;

  SELECT owner_user_id INTO v_owner FROM public.merchant_stores WHERE id = v_store;
  IF v_owner IS DISTINCT FROM v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_w FROM public.wallets WHERE owner_user_id = v_owner AND party_type = 'merchant';
  v_avail := GREATEST(COALESCE(v_w.balance_gnf,0) - COALESCE(v_w.held_gnf,0), 0);

  SELECT
    COALESCE(SUM(amount_gnf - settled_gnf) FILTER (WHERE state IN ('pending_funding','funded','due')), 0),
    COALESCE(SUM(amount_gnf - settled_gnf) FILTER (WHERE state IN ('funded','due')), 0),
    COALESCE(SUM(settled_gnf) FILTER (WHERE state = 'settled'), 0),
    COALESCE(SUM(amount_gnf) FILTER (WHERE state = 'reversed'), 0),
    COALESCE(SUM(amount_gnf - settled_gnf) FILTER (WHERE state = 'settlement_held'), 0)
  INTO v_pending, v_funded, v_settled, v_reversed, v_held_state
  FROM public.merchant_payables
  WHERE merchant_store_id = v_store;

  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_open_req
    FROM public.merchant_settlement_requests
   WHERE merchant_store_id = v_store AND status IN ('requested','pending_review');

  v_eligible := GREATEST(LEAST(v_avail, v_funded) - v_open_req, 0);

  SELECT COALESCE(enabled, false) INTO v_settlement_on
    FROM public.feature_flags WHERE key = 'merchant_om_settlement_enabled';

  RETURN jsonb_build_object(
    'store_id', v_store,
    'wallet_id', v_w.id,
    'wallet_status', COALESCE(v_w.status::text,'active'),
    'sales_balance_gnf', COALESCE(v_w.balance_gnf, 0),
    'held_gnf', COALESCE(v_w.held_gnf, 0),
    'available_gnf', v_avail,
    'pending_payable_gnf', v_pending,
    'funded_unsettled_gnf', v_funded,
    'settlement_held_gnf', v_held_state,
    'settled_total_gnf', v_settled,
    'reversed_total_gnf', v_reversed,
    'open_request_gnf', v_open_req,
    'eligible_settlement_gnf', v_eligible,
    'settlement_rail_enabled', COALESCE(v_settlement_on, false)
  );
END $$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_requests_list(
  p_store_id uuid DEFAULT NULL, p_limit integer DEFAULT 20)
RETURNS TABLE(id uuid, request_key text, amount_gnf bigint, status text, channel text,
  note text, reject_reason text, evidence_ref text, settled_at timestamptz,
  reviewed_at timestamptz, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_store uuid := p_store_id;
  v_owner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v_store IS NULL THEN
    SELECT ms.id INTO v_store FROM public.merchant_stores ms WHERE ms.owner_user_id = v_uid LIMIT 1;
  END IF;
  IF v_store IS NULL THEN RETURN; END IF;
  SELECT ms.owner_user_id INTO v_owner FROM public.merchant_stores ms WHERE ms.id = v_store;
  IF v_owner IS DISTINCT FROM v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
    SELECT r.id, r.request_key, r.amount_gnf, r.status, r.channel, r.note,
           r.reject_reason, r.evidence_ref, r.settled_at, r.reviewed_at, r.created_at
      FROM public.merchant_settlement_requests r
     WHERE r.merchant_store_id = v_store
     ORDER BY r.created_at DESC
     LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100));
END $$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_request_create(
  p_amount_gnf bigint, p_idempotency_key text, p_store_id uuid DEFAULT NULL, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_store uuid := p_store_id;
  v_owner uuid;
  v_ov jsonb;
  v_eligible bigint;
  v_key text;
  v_row public.merchant_settlement_requests;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;
  IF p_idempotency_key IS NULL OR length(trim(p_idempotency_key)) < 8 THEN
    RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED';
  END IF;

  IF v_store IS NULL THEN
    SELECT id INTO v_store FROM public.merchant_stores WHERE owner_user_id = v_uid LIMIT 1;
  END IF;
  IF v_store IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_NOT_FOUND'; END IF;
  SELECT owner_user_id INTO v_owner FROM public.merchant_stores WHERE id = v_store;
  IF v_owner IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  v_key := v_store::text || ':' || trim(p_idempotency_key);

  SELECT * INTO v_row FROM public.merchant_settlement_requests WHERE request_key = v_key;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object('request_id', v_row.id, 'status', v_row.status,
      'amount_gnf', v_row.amount_gnf, 'duplicate', true);
  END IF;

  v_ov := public.merchant_finance_overview(v_store);
  v_eligible := (v_ov->>'eligible_settlement_gnf')::bigint;
  IF p_amount_gnf > v_eligible THEN
    RAISE EXCEPTION 'AMOUNT_EXCEEDS_ELIGIBLE: % > %', p_amount_gnf, v_eligible;
  END IF;

  INSERT INTO public.merchant_settlement_requests
    (request_key, merchant_store_id, merchant_user_id, amount_gnf, eligible_snapshot_gnf, note)
  VALUES (v_key, v_store, v_uid, p_amount_gnf, v_eligible, p_note)
  RETURNING * INTO v_row;

  INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  VALUES (v_uid, 'merchant.settlement_request.created', 'merchant_settlement_request', v_row.id,
          jsonb_build_object('store_id', v_store, 'amount_gnf', p_amount_gnf,
                             'eligible_gnf', v_eligible, 'rail_enabled', v_ov->'settlement_rail_enabled'));

  RETURN jsonb_build_object('request_id', v_row.id, 'status', v_row.status,
    'amount_gnf', v_row.amount_gnf, 'duplicate', false);
END $$;

-- ---------- 5. PRIVILEGES ----------
REVOKE ALL ON FUNCTION public.customer_finance_overview() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.customer_finance_history(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.customer_receipt(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.list_my_topup_requests(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_topup_history(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.merchant_finance_overview(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.merchant_settlement_requests_list(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.merchant_settlement_request_create(bigint, text, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._msr_immutable() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.customer_finance_overview() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.customer_finance_history(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.customer_receipt(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_my_topup_requests(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.driver_topup_history(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.merchant_finance_overview(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.merchant_settlement_requests_list(uuid, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.merchant_settlement_request_create(bigint, text, uuid, text) TO authenticated, service_role;