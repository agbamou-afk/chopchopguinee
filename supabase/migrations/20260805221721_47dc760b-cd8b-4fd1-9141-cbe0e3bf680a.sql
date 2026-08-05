-- =========================================================================
-- Slice 1 exit-gate correction / hardening. Still INERT: no flag changes.
-- Policy authority: docs/product/chop-pay-canonical-operating-policy.md
-- =========================================================================

-- -------------------------------------------------------------------------
-- 0. Capture attribution columns (exact restricted/unrestricted split)
-- -------------------------------------------------------------------------
ALTER TABLE public.mission_financial_holds
  ADD COLUMN IF NOT EXISTS captured_promo_gnf bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS captured_unrestricted_gnf bigint NOT NULL DEFAULT 0;

ALTER TABLE public.mission_financial_holds
  DROP CONSTRAINT IF EXISTS mfh_capture_split_chk;
ALTER TABLE public.mission_financial_holds
  ADD CONSTRAINT mfh_capture_split_chk CHECK (
    captured_promo_gnf >= 0 AND captured_unrestricted_gnf >= 0
    AND (captured_promo_gnf + captured_unrestricted_gnf) <= captured_gnf
  );

-- One pending payout hold per driver.
CREATE UNIQUE INDEX IF NOT EXISTS mfh_one_pending_cashout_per_driver
  ON public.mission_financial_holds (driver_user_id)
  WHERE kind = 'cashout' AND state = 'held';

-- -------------------------------------------------------------------------
-- 1. Shared, audited external evidence register (payouts + settlements)
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.finance_evidence_refs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  evidence_ref text NOT NULL,
  normalized_ref text GENERATED ALWAYS AS (lower(btrim(evidence_ref))) STORED,
  usage_kind text NOT NULL CHECK (usage_kind IN ('driver_payout','merchant_settlement')),
  target_id uuid NOT NULL,
  amount_gnf bigint NOT NULL DEFAULT 0,
  actor_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS finance_evidence_refs_unique
  ON public.finance_evidence_refs (normalized_ref);

GRANT SELECT ON public.finance_evidence_refs TO authenticated;
GRANT ALL ON public.finance_evidence_refs TO service_role;
ALTER TABLE public.finance_evidence_refs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Finance and god admins read evidence refs" ON public.finance_evidence_refs;
CREATE POLICY "Finance and god admins read evidence refs"
  ON public.finance_evidence_refs FOR SELECT TO authenticated
  USING (public.is_god_admin(auth.uid())
         OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role));

CREATE OR REPLACE FUNCTION public._finance_evidence_claim(
  p_evidence_ref text, p_usage_kind text, p_target uuid, p_amount bigint, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid;
BEGIN
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'EVIDENCE_REQUIRED';
  END IF;
  INSERT INTO public.finance_evidence_refs
    (evidence_ref, usage_kind, target_id, amount_gnf, actor_user_id)
  VALUES (btrim(p_evidence_ref), p_usage_kind, p_target, GREATEST(COALESCE(p_amount,0),0), p_actor)
  ON CONFLICT (normalized_ref) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'EVIDENCE_ALREADY_USED'
      USING DETAIL = format('reference=%s', btrim(p_evidence_ref));
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public._finance_evidence_claim(text,text,uuid,bigint,uuid) FROM public, anon, authenticated;

-- -------------------------------------------------------------------------
-- 2. Journal invariant: no empty, single-sided or unbalanced journals
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._ledger_assert_journal_complete()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
DECLARE v_sum bigint; v_cnt int;
BEGIN
  SELECT COALESCE(SUM(amount_gnf),0), count(*) INTO v_sum, v_cnt
    FROM public.ledger_postings WHERE journal_id = NEW.id;
  IF v_cnt < 2 THEN
    RAISE EXCEPTION 'LEDGER_EMPTY_JOURNAL: journal % has % posting(s); at least 2 required', NEW.id, v_cnt;
  END IF;
  IF v_sum <> 0 THEN
    RAISE EXCEPTION 'LEDGER_UNBALANCED: journal % sums to % GNF, expected 0', NEW.id, v_sum;
  END IF;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS trg_ledger_journal_complete ON public.ledger_journals;
CREATE CONSTRAINT TRIGGER trg_ledger_journal_complete
  AFTER INSERT ON public.ledger_journals
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public._ledger_assert_journal_complete();

CREATE OR REPLACE FUNCTION public._ledger_post(p_journal_key text, p_source_module text, p_source_id uuid, p_action text, p_lines jsonb, p_mission_type text DEFAULT NULL::text, p_actor uuid DEFAULT NULL::uuid, p_policy jsonb DEFAULT '{}'::jsonb, p_is_sandbox boolean DEFAULT false, p_reason text DEFAULT NULL::text, p_evidence text DEFAULT NULL::text, p_reverses uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_j public.ledger_journals;
  v_line jsonb;
  v_sum bigint := 0;
  v_nonzero int := 0;
BEGIN
  IF p_journal_key IS NULL OR btrim(p_journal_key) = '' THEN
    RAISE EXCEPTION 'LEDGER_KEY_REQUIRED';
  END IF;

  -- Reject empty / all-zero / single-sided payloads BEFORE any row is written.
  SELECT count(*), COALESCE(SUM((l->>'amount_gnf')::bigint),0)
    INTO v_nonzero, v_sum
    FROM jsonb_array_elements(COALESCE(p_lines,'[]'::jsonb)) l
   WHERE COALESCE((l->>'amount_gnf')::bigint,0) <> 0;
  IF v_nonzero < 2 THEN
    RAISE EXCEPTION 'LEDGER_EMPTY_JOURNAL: % non-zero posting(s) supplied for %; at least 2 required',
      v_nonzero, p_journal_key;
  END IF;
  IF v_sum <> 0 THEN
    RAISE EXCEPTION 'LEDGER_UNBALANCED: journal % sums to % GNF, expected 0', p_journal_key, v_sum;
  END IF;

  SELECT * INTO v_j FROM public.ledger_journals WHERE journal_key = p_journal_key;
  IF v_j.id IS NOT NULL THEN
    RETURN jsonb_build_object('status','replayed','journal_id',v_j.id,'journal_key',p_journal_key);
  END IF;

  INSERT INTO public.ledger_journals
    (journal_key, source_module, source_id, action, mission_type, actor_user_id,
     policy_snapshot, is_sandbox, reason, evidence_ref, reverses_journal_id)
  VALUES
    (p_journal_key, p_source_module, p_source_id, p_action, p_mission_type,
     COALESCE(p_actor, auth.uid()), COALESCE(p_policy,'{}'::jsonb),
     COALESCE(p_is_sandbox,false), p_reason, p_evidence, p_reverses)
  ON CONFLICT (journal_key) DO NOTHING
  RETURNING * INTO v_j;

  IF v_j.id IS NULL THEN
    SELECT * INTO v_j FROM public.ledger_journals WHERE journal_key = p_journal_key;
    RETURN jsonb_build_object('status','replayed','journal_id',v_j.id,'journal_key',p_journal_key);
  END IF;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    CONTINUE WHEN COALESCE((v_line->>'amount_gnf')::bigint, 0) = 0;
    INSERT INTO public.ledger_postings
      (journal_id, account_code, amount_gnf, party_type, party_user_id, merchant_store_id, memo)
    VALUES
      (v_j.id, v_line->>'account', (v_line->>'amount_gnf')::bigint,
       NULLIF(v_line->>'party_type','')::public.party_type,
       NULLIF(v_line->>'party_user_id','')::uuid,
       NULLIF(v_line->>'merchant_store_id','')::uuid,
       v_line->>'memo');
  END LOOP;

  RETURN jsonb_build_object('status','posted','journal_id',v_j.id,'journal_key',p_journal_key);
END; $$;

-- -------------------------------------------------------------------------
-- 3. Promotional restore primitive (reversal only, internal)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._promo_restore(p_driver uuid, p_amount bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_left bigint := GREATEST(COALESCE(p_amount,0),0);
  v_row public.driver_promo_credits;
  v_give bigint;
BEGIN
  FOR v_row IN
    SELECT * FROM public.driver_promo_credits
     WHERE driver_user_id = p_driver AND consumed_gnf > 0
     ORDER BY created_at DESC FOR UPDATE
  LOOP
    EXIT WHEN v_left <= 0;
    v_give := LEAST(v_left, v_row.consumed_gnf);
    UPDATE public.driver_promo_credits
       SET consumed_gnf = consumed_gnf - v_give,
           state = CASE WHEN (consumed_gnf - v_give) + reversed_gnf >= granted_gnf
                        THEN 'exhausted' ELSE 'active' END,
           updated_at = now()
     WHERE id = v_row.id;
    v_left := v_left - v_give;
  END LOOP;
  RETURN GREATEST(COALESCE(p_amount,0),0) - v_left;
END; $$;
REVOKE ALL ON FUNCTION public._promo_restore(uuid,bigint) FROM public, anon, authenticated;

-- -------------------------------------------------------------------------
-- 4. Store exact capture attribution on every driver-side capture
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_mission_commission_capture(p_source_module text, p_source_id uuid, p_final_value_gnf bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_snap jsonb; v_due bigint; v_capture bigint; v_excess bigint;
  v_cp bigint := 0; v_cu bigint := 0; v_rp bigint := 0; v_ru bigint := 0;
  v_dw public.wallets; v_master public.wallets; v_tx public.wallet_transactions;
BEGIN
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'commission'
   FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','captured_gnf',0); END IF;
  IF v_h.driver_user_id <> COALESCE(v_caller, v_h.driver_user_id)
     AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_h.state <> 'held' THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_snap := v_h.policy_snapshot;
  v_due := (GREATEST(COALESCE(p_final_value_gnf,0),0) * COALESCE((v_snap->>'commission_bps')::int,0)) / 10000
           + COALESCE((v_snap->>'fixed_commission_gnf')::bigint,0);
  v_capture := LEAST(v_due, v_h.amount_gnf);
  v_excess := v_h.amount_gnf - v_capture;

  v_cp := LEAST(v_h.promo_gnf, v_capture);
  v_cu := v_capture - v_cp;
  v_rp := v_h.promo_gnf - v_cp;
  v_ru := v_excess - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_dw.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_capture, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-capture:%s:%s', p_source_module, p_source_id), 'commission', 'completed',
     GREATEST(v_capture,1), v_dw.id, v_master.id, v_h.driver_user_id,
     p_source_module || ':' || p_source_id::text, 'Commission CHOPCHOP',
     jsonb_build_object('mission_type', v_h.mission_type, 'final_value_gnf', p_final_value_gnf,
                        'reserved_gnf', v_h.amount_gnf, 'captured_gnf', v_capture,
                        'released_excess_gnf', v_excess, 'promo_consumed_gnf', v_cp,
                        'unrestricted_consumed_gnf', v_cu, 'is_sandbox', v_h.is_sandbox), now())
  RETURNING * INTO v_tx;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  IF v_capture > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:commission', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_commission',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COMMISSION','amount_gnf',v_capture,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','consume commission hold'),
        jsonb_build_object('account','R_COMMISSION','amount_gnf',-v_capture,'memo','commission revenue')),
      v_h.mission_type, v_caller, v_snap, v_h.is_sandbox);
  END IF;

  IF v_excess > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:commission', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_commission',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COMMISSION','amount_gnf',v_excess,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release excess reserve'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, v_caller, v_snap, v_h.is_sandbox);
  END IF;

  UPDATE public.mission_financial_holds
     SET state = 'captured', captured_gnf = v_capture, released_gnf = v_excess,
         captured_promo_gnf = v_cp, captured_unrestricted_gnf = v_cu,
         resolution_tx_id = v_tx.id, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_capture,
                            'promo_consumed_gnf',v_cp,'unrestricted_consumed_gnf',v_cu,
                            'released_excess_gnf',v_excess);
END; $$;

CREATE OR REPLACE FUNCTION public.driver_mission_fee_capture(p_source_module text, p_source_id uuid, p_final_fee_basis_gnf bigint DEFAULT NULL::bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
  v_due bigint; v_cap bigint; v_ex bigint;
  v_cp bigint; v_cu bigint; v_rp bigint; v_ru bigint;
  v_dw public.wallets; v_master public.wallets;
BEGIN
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'platform_fee' FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','captured_gnf',0); END IF;
  IF v_h.driver_user_id <> COALESCE(v_caller, v_h.driver_user_id)
     AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_h.state <> 'held' THEN RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf); END IF;

  v_due := CASE WHEN p_final_fee_basis_gnf IS NULL THEN v_h.amount_gnf
           ELSE (GREATEST(p_final_fee_basis_gnf,0) *
                 COALESCE((v_h.policy_snapshot->>'transaction_fee_bps')::int,0)) / 10000 END;
  v_cap := LEAST(v_due, v_h.amount_gnf);
  v_ex := v_h.amount_gnf - v_cap;
  v_cp := LEAST(v_h.promo_gnf, v_cap); v_cu := v_cap - v_cp;
  v_rp := v_h.promo_gnf - v_cp; v_ru := v_ex - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf,0), updated_at = now() WHERE id = v_dw.id;
  IF v_cap > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_cap, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_cap, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;
    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:platform_fee', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_platform_fee',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_PLATFORM_FEE','amount_gnf',v_cap,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','fee reserve consumed'),
        jsonb_build_object('account','R_TRANSACTION_FEE','amount_gnf',-v_cap,'memo','transaction fee revenue')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;
  IF v_ex > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:platform_fee', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_platform_fee',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_PLATFORM_FEE','amount_gnf',v_ex,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','excess fee reserve'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored restricted'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored unrestricted')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;

  UPDATE public.wallet_transactions SET status='completed', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status='pending';
  UPDATE public.mission_financial_holds
     SET state='captured', captured_gnf = v_cap, released_gnf = v_ex,
         captured_promo_gnf = v_cp, captured_unrestricted_gnf = v_cu,
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_cap,'released_gnf',v_ex,
                            'promo_consumed_gnf',v_cp,'unrestricted_consumed_gnf',v_cu);
END; $$;

CREATE OR REPLACE FUNCTION public.driver_collateral_resolve(p_source_module text, p_source_id uuid, p_capture_gnf bigint, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_capture bigint; v_excess bigint;
  v_cp bigint := 0; v_cu bigint := 0; v_rp bigint := 0; v_ru bigint := 0;
  v_dw public.wallets; v_master public.wallets; v_tx public.wallet_transactions;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller) OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'collateral' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Collateral hold not found'; END IF;
  IF v_h.state NOT IN ('held','frozen') THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_capture := LEAST(GREATEST(COALESCE(p_capture_gnf,0),0), v_h.amount_gnf);
  v_excess := v_h.amount_gnf - v_capture;
  v_cp := LEAST(v_h.promo_gnf, v_capture);
  v_cu := v_capture - v_cp;
  v_rp := v_h.promo_gnf - v_cp;
  v_ru := v_excess - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_dw.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_capture, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;

    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:collateral', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_collateral',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COLLATERAL','amount_gnf',v_capture,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','authorised collateral loss'),
        jsonb_build_object('account','R_COLLATERAL_LOSS','amount_gnf',-v_capture,'memo','recovered collateral')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason);
  END IF;

  IF v_excess > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:collateral', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_collateral',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COLLATERAL','amount_gnf',v_excess,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release collateral'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason);
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-collateral:%s:%s', p_source_module, p_source_id), 'adjustment', 'completed',
     GREATEST(v_capture,1), v_dw.id, v_master.id, v_h.driver_user_id,
     p_source_module || ':' || p_source_id::text, 'Résolution de caution mission',
     jsonb_build_object('reason', p_reason, 'held_gnf', v_h.amount_gnf, 'captured_gnf', v_capture,
                        'promo_consumed_gnf', v_cp, 'unrestricted_consumed_gnf', v_cu,
                        'is_sandbox', v_h.is_sandbox), now())
  RETURNING * INTO v_tx;

  UPDATE public.wallet_transactions SET status='completed', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  UPDATE public.mission_financial_holds
     SET state = CASE WHEN v_capture > 0 THEN 'captured' ELSE 'released' END,
         captured_gnf = v_capture, released_gnf = v_excess,
         captured_promo_gnf = v_cp, captured_unrestricted_gnf = v_cu,
         resolution_tx_id = v_tx.id,
         reason = p_reason, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'collateral_resolve', 'mission',
          p_source_module || ':' || p_source_id::text,
          jsonb_build_object('held_gnf',v_h.amount_gnf,'promo_gnf',v_h.promo_gnf),
          jsonb_build_object('captured_gnf',v_capture,'promo_consumed_gnf',v_cp), p_reason);

  RETURN jsonb_build_object('status','resolved','captured_gnf',v_capture,
                            'promo_consumed_gnf',v_cp,'released_gnf',v_excess);
END; $$;

-- -------------------------------------------------------------------------
-- 5. Bucket-exact capture reversal
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_mission_capture_reverse(p_source_module text, p_source_id uuid, p_kind text, p_reason text, p_evidence text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_revenue text; v_cp bigint; v_cu bigint; v_res jsonb;
  v_dw public.wallets; v_master public.wallets;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can reverse a capture';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = p_kind FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Hold not found'; END IF;
  IF v_h.state = 'reversed' THEN RETURN jsonb_build_object('status','already_reversed'); END IF;
  IF v_h.captured_gnf <= 0 THEN RETURN jsonb_build_object('status','nothing_to_reverse'); END IF;
  IF v_h.driver_user_id IS NULL THEN
    RAISE EXCEPTION 'CAPTURE_REVERSAL_DRIVER_ONLY';
  END IF;

  v_revenue := CASE p_kind
    WHEN 'commission'   THEN 'R_COMMISSION'
    WHEN 'platform_fee' THEN 'R_TRANSACTION_FEE'
    WHEN 'collateral'   THEN 'R_COLLATERAL_LOSS'
    ELSE NULL END;
  IF v_revenue IS NULL THEN
    RAISE EXCEPTION 'CAPTURE_REVERSAL_UNSUPPORTED_KIND: %', p_kind;
  END IF;

  -- Exact stored attribution; fall back to hold funding split only for legacy rows.
  v_cp := v_h.captured_promo_gnf;
  v_cu := v_h.captured_unrestricted_gnf;
  IF (v_cp + v_cu) <> v_h.captured_gnf THEN
    v_cp := LEAST(v_h.promo_gnf, v_h.captured_gnf);
    v_cu := v_h.captured_gnf - v_cp;
  END IF;

  -- Compensating journal: revenue back to the ORIGINAL driver source buckets.
  v_res := public._ledger_post(
    format('mfh-capture-reverse:%s:%s:%s', p_source_module, p_source_id, p_kind),
    p_source_module, p_source_id, 'capture_' || p_kind || '_reversed',
    jsonb_build_array(
      jsonb_build_object('account',v_revenue,'amount_gnf',v_h.captured_gnf,'memo','revenue reversed'),
      jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_cp,
                         'party_type','driver','party_user_id',v_h.driver_user_id,
                         'memo','restored to restricted credit'),
      jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_cu,
                         'party_type','driver','party_user_id',v_h.driver_user_id,
                         'memo','restored to unrestricted')),
    v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason, p_evidence);

  IF v_res->>'status' = 'replayed' THEN
    RETURN jsonb_build_object('status','already_reversed');
  END IF;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_h.captured_gnf, updated_at = now() WHERE id = v_dw.id;
  IF v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_h.captured_gnf, updated_at = now() WHERE id = v_master.id;
  END IF;

  IF v_cp > 0 THEN PERFORM public._promo_restore(v_h.driver_user_id, v_cp); END IF;

  UPDATE public.mission_financial_holds
     SET state = 'reversed', reason = p_reason, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'capture_reversed', 'mission',
          p_source_module || ':' || p_source_id::text,
          jsonb_build_object('captured_gnf',v_h.captured_gnf,'promo',v_cp,'unrestricted',v_cu),
          v_res, p_reason);

  RETURN jsonb_build_object('status','reversed','reversed_gnf',v_h.captured_gnf,
                            'restored_promo_gnf',v_cp,'restored_unrestricted_gnf',v_cu,'journal',v_res);
END; $$;

-- -------------------------------------------------------------------------
-- 6. Single canonical customer capture -> merchant payable funding
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.chop_pay_customer_capture(p_source_module text, p_source_id uuid, p_merchant_store_id uuid, p_merchant_gnf bigint, p_driver uuid, p_driver_earning_gnf bigint, p_commission_gnf bigint, p_fee_gnf bigint, p_refund_remainder boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_p public.merchant_payables;
  v_m bigint := GREATEST(COALESCE(p_merchant_gnf,0),0);
  v_d bigint := GREATEST(COALESCE(p_driver_earning_gnf,0),0);
  v_c bigint := GREATEST(COALESCE(p_commission_gnf,0),0);
  v_f bigint := GREATEST(COALESCE(p_fee_gnf,0),0);
  v_total bigint; v_remainder bigint;
  v_lines jsonb;
  v_cw public.wallets; v_dw public.wallets; v_master public.wallets;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Customer hold not found'; END IF;
  IF v_h.state <> 'held' THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_total := v_m + v_d + v_c + v_f;
  IF v_total > v_h.amount_gnf THEN
    RAISE EXCEPTION 'SPLIT_EXCEEDS_HOLD' USING DETAIL = format('split=%s hold=%s', v_total, v_h.amount_gnf);
  END IF;
  v_remainder := v_h.amount_gnf - v_total;
  IF v_remainder > 0 AND NOT p_refund_remainder THEN
    RAISE EXCEPTION 'SPLIT_MUST_BE_EXACT' USING DETAIL = format('unallocated=%s', v_remainder);
  END IF;
  IF v_d > 0 AND p_driver IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;

  -- Canonical merchant flow: the payable must already exist and must be
  -- unfunded. Capture consumes the customer hold and funds it exactly once.
  IF v_m > 0 THEN
    IF p_merchant_store_id IS NULL THEN RAISE EXCEPTION 'Merchant store required'; END IF;
    SELECT * INTO v_p FROM public.merchant_payables
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND merchant_store_id = p_merchant_store_id FOR UPDATE;
    IF v_p.id IS NULL THEN
      RAISE EXCEPTION 'MERCHANT_PAYABLE_REQUIRED'
        USING DETAIL = 'Create the payable with merchant_payable_create before capture';
    END IF;
    IF v_p.funded_gnf > 0 OR v_p.state <> 'pending_funding' THEN
      RAISE EXCEPTION 'MERCHANT_PAYABLE_ALREADY_FUNDED' USING DETAIL = v_p.state;
    END IF;
    IF v_m > (v_p.amount_gnf - v_p.funded_gnf) THEN
      RAISE EXCEPTION 'MERCHANT_SPLIT_EXCEEDS_PAYABLE'
        USING DETAIL = format('split=%s payable=%s', v_m, v_p.amount_gnf);
    END IF;
  END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_h.party_user_id AND party_type = 'client' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0),
                            balance_gnf = balance_gnf - v_total, updated_at = now()
   WHERE id = v_cw.id;

  v_lines := jsonb_build_array(jsonb_build_object(
    'account','L_CUSTOMER_HOLD','amount_gnf',v_total,
    'party_type','client','party_user_id',v_h.party_user_id,'memo','order captured'));

  IF v_m > 0 THEN
    v_lines := v_lines || jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',-v_m,
      'party_type','merchant','party_user_id',v_p.merchant_user_id,
      'merchant_store_id',p_merchant_store_id,'memo','merchant payable funded from customer Chop Pay');
    IF v_p.merchant_user_id IS NOT NULL THEN
      INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_p.merchant_user_id,'merchant')
      ON CONFLICT (owner_user_id, party_type) DO NOTHING;
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_m, updated_at = now()
       WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
    END IF;
  END IF;
  IF v_d > 0 THEN
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (p_driver,'driver')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    SELECT * INTO v_dw FROM public.wallets
     WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_d, updated_at = now() WHERE id = v_dw.id;
    v_lines := v_lines || jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_d,
      'party_type','driver','party_user_id',p_driver,'memo','delivery earning');
  END IF;
  IF v_c > 0 THEN
    v_lines := v_lines || jsonb_build_object('account','R_COMMISSION','amount_gnf',-v_c,'memo','commission revenue');
  END IF;
  IF v_f > 0 THEN
    v_lines := v_lines || jsonb_build_object('account','R_TRANSACTION_FEE','amount_gnf',-v_f,'memo','service fee revenue');
  END IF;
  IF (v_c + v_f) > 0 AND v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_c + v_f, updated_at = now() WHERE id = v_master.id;
  END IF;

  IF v_total > 0 THEN
    PERFORM public._ledger_post(
      format('cust-capture:%s:%s', p_source_module, p_source_id),
      p_source_module, p_source_id, 'customer_payment_capture', v_lines,
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;

  IF v_remainder > 0 THEN
    PERFORM public._ledger_post(
      format('cust-refund:%s:%s', p_source_module, p_source_id),
      p_source_module, p_source_id, 'customer_payment_refund',
      jsonb_build_array(
        jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',v_remainder,
                           'party_type','client','party_user_id',v_h.party_user_id,'memo','unused hold'),
        jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_remainder,
                           'party_type','client','party_user_id',v_h.party_user_id,'memo','returned to customer balance')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox);
  END IF;

  IF v_m > 0 THEN
    UPDATE public.merchant_payables
       SET funded_gnf = v_m, funding_source = 'customer_choppay',
           state = 'funded', updated_at = now()
     WHERE id = v_p.id;
  END IF;

  UPDATE public.wallet_transactions SET status='completed', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status='pending';

  UPDATE public.mission_financial_holds
     SET state='captured', captured_gnf = v_total, released_gnf = v_remainder,
         resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_total,
    'merchant_gnf',v_m,'merchant_payable_id',v_p.id,'driver_earning_gnf',v_d,
    'commission_gnf',v_c,'fee_gnf',v_f,'refunded_gnf',v_remainder);
END; $$;

CREATE OR REPLACE FUNCTION public.merchant_payable_fund(p_source_module text, p_source_id uuid, p_merchant_store_id uuid, p_funding_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_p public.merchant_payables; v_h public.mission_financial_holds;
  v_amount bigint; v_from text;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_funding_source = 'customer_choppay' THEN
    RAISE EXCEPTION 'CUSTOMER_CHOPPAY_FUNDED_AT_CAPTURE'
      USING DETAIL = 'Customer Chop Pay orders are funded atomically by chop_pay_customer_capture';
  END IF;
  IF p_funding_source NOT IN ('driver_cash_funding','platform') THEN
    RAISE EXCEPTION 'Invalid funding source';
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = p_merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.funded_gnf >= v_p.amount_gnf OR v_p.state <> 'pending_funding' THEN
    RETURN jsonb_build_object('status','already_funded','payable_id',v_p.id,
                              'funded_gnf',v_p.funded_gnf,'funding_source',v_p.funding_source);
  END IF;
  v_amount := v_p.amount_gnf - v_p.funded_gnf;

  IF p_funding_source = 'driver_cash_funding' THEN
    SELECT * INTO v_h FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND kind = 'cash_funding' AND state IN ('held','partially_captured') FOR UPDATE;
    IF v_h.id IS NULL THEN RAISE EXCEPTION 'CASH_FUNDING_HOLD_MISSING'; END IF;
    IF (v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf) < v_amount THEN
      RAISE EXCEPTION 'CASH_FUNDING_INSUFFICIENT';
    END IF;
    IF v_h.promo_gnf > 0 THEN
      RAISE EXCEPTION 'RESTRICTED_FUNDS_CANNOT_FUND_MERCHANDISE';
    END IF;
    v_from := 'L_HOLD_CASH_FUNDING';
    UPDATE public.mission_financial_holds
       SET captured_gnf = captured_gnf + v_amount,
           captured_unrestricted_gnf = captured_unrestricted_gnf + v_amount,
           state = CASE WHEN captured_gnf + v_amount >= amount_gnf THEN 'captured' ELSE 'partially_captured' END
     WHERE id = v_h.id;
    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_amount,0),
                              balance_gnf = balance_gnf - v_amount, updated_at = now()
     WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver';
  ELSE
    v_from := 'EQ_PLATFORM';
  END IF;

  IF v_p.merchant_user_id IS NOT NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_p.merchant_user_id,'merchant')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount, updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;

  PERFORM public._ledger_post(
    format('payable-fund:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
    p_source_module, p_source_id, 'merchant_payable_funded',
    jsonb_build_array(
      jsonb_build_object('account',v_from,'amount_gnf',v_amount,'memo','funding source consumed'),
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',-v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'merchant_store_id',p_merchant_store_id,'memo','merchant payable funded')),
    v_p.mission_type, v_caller, v_p.policy_snapshot, v_p.is_sandbox);

  UPDATE public.merchant_payables
     SET funded_gnf = funded_gnf + v_amount, funding_source = p_funding_source,
         state = 'funded', updated_at = now()
   WHERE id = v_p.id;

  RETURN jsonb_build_object('status','funded','payable_id',v_p.id,'funded_gnf',v_amount,
                            'funding_source',p_funding_source,'preparation_authorized',true);
END; $$;

-- -------------------------------------------------------------------------
-- 7. Ops is read-only on money
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_mission_hold_release(p_source_module text, p_source_id uuid, p_kind text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
  v_released bigint := 0; v_wallet_id uuid; v_open bigint; v_u bigint; v_p bigint;
BEGIN
  FOR v_h IN
    SELECT * FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND (p_kind IS NULL OR kind = p_kind)
       AND state IN ('held','partially_captured','frozen')
     ORDER BY created_at FOR UPDATE
  LOOP
    -- Only the owning driver or a finance/God caller may release funds.
    -- operations_admin is explicitly read-only on money.
    IF v_h.driver_user_id <> COALESCE(v_caller, v_h.driver_user_id)
       AND NOT public._finance_privileged(v_caller) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;

    v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
    CONTINUE WHEN v_open <= 0;

    v_p := LEAST(v_open, GREATEST(v_h.promo_gnf - LEAST(v_h.captured_gnf, v_h.promo_gnf), 0));
    v_u := v_open - v_p;

    SELECT id INTO v_wallet_id FROM public.wallets
     WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;

    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now()
     WHERE id = v_wallet_id;
    UPDATE public.wallet_transactions SET status = 'cancelled', completed_at = now()
     WHERE id = v_h.hold_tx_id AND status = 'pending';

    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:%s', p_source_module, p_source_id, v_h.kind),
      p_source_module, p_source_id, 'release_' || v_h.kind,
      jsonb_build_array(
        jsonb_build_object('account', public._hold_account(v_h.kind), 'amount_gnf', v_open,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release hold'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_p,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_u,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason);

    UPDATE public.mission_financial_holds
       SET state = 'released', released_gnf = released_gnf + v_open,
           reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = v_caller
     WHERE id = v_h.id;

    v_released := v_released + v_open;
  END LOOP;

  RETURN jsonb_build_object('status', 'released', 'released_gnf', v_released);
END; $$;

-- -------------------------------------------------------------------------
-- 8. Collateral freeze / unfreeze (state only, idempotent, audited)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_mission_hold_freeze(p_source_module text, p_source_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_n int; v_already int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)
          OR public.has_admin_role(v_caller, 'operations_admin'::admin_role)
          OR public.has_admin_role(v_caller, 'support_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT count(*) INTO v_already FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND state = 'frozen';

  UPDATE public.mission_financial_holds
     SET state = 'frozen', reason = p_reason, updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'held';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n > 0 THEN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, note)
    VALUES (v_caller, 'wallet', 'mission_hold_freeze', 'mission',
            p_source_module || ':' || p_source_id::text, p_reason);
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN v_n = 0 AND v_already > 0 THEN 'already_frozen' ELSE 'frozen' END,
                            'holds', v_n, 'already_frozen', v_already,
                            'note','State change only — no value moved');
END; $$;

CREATE OR REPLACE FUNCTION public.driver_mission_hold_unfreeze(p_source_module text, p_source_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_n int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;
  IF EXISTS (SELECT 1 FROM public.claims_reserves
              WHERE source_module = p_source_module AND source_id = p_source_id
                AND state = 'allocated') THEN
    RAISE EXCEPTION 'CLAIM_OPEN_CANNOT_UNFREEZE';
  END IF;

  UPDATE public.mission_financial_holds
     SET state = 'held', reason = p_reason, updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'frozen';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, note)
  VALUES (v_caller, 'wallet', 'mission_hold_unfreeze', 'mission',
          p_source_module || ':' || p_source_id::text, p_reason);

  RETURN jsonb_build_object('status', CASE WHEN v_n > 0 THEN 'unfrozen' ELSE 'nothing_frozen' END,
                            'holds', v_n);
END; $$;

-- Claims require a frozen collateral hold first.
CREATE OR REPLACE FUNCTION public.claims_reserve_allocate(p_source_module text, p_source_id uuid, p_authorized_gnf bigint, p_evidence_ref text, p_reason text, p_customer uuid DEFAULT NULL::uuid, p_driver uuid DEFAULT NULL::uuid, p_declared_value_gnf bigint DEFAULT 0, p_mission_type text DEFAULT 'envoyer'::text, p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.claims_reserves; v_col public.mission_financial_holds;
BEGIN
  IF v_caller IS NULL OR NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can authorise a claims reserve';
  END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN RAISE EXCEPTION 'CLAIM_EVIDENCE_REQUIRED'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'A documented reason is required'; END IF;
  IF COALESCE(p_authorized_gnf,0) <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  SELECT * INTO v_col FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'collateral';
  IF v_col.id IS NULL OR v_col.state <> 'frozen' THEN
    RAISE EXCEPTION 'COLLATERAL_FREEZE_REQUIRED'
      USING DETAIL = 'Freeze the related collateral hold before authorising a claims reserve';
  END IF;

  INSERT INTO public.claims_reserves
    (claim_key, source_module, source_id, mission_type, customer_user_id, driver_user_id,
     declared_value_gnf, authorized_gnf, evidence_ref, reason, authorized_by, is_sandbox)
  VALUES (format('claim:%s:%s', p_source_module, p_source_id), p_source_module, p_source_id,
          p_mission_type, p_customer, p_driver, GREATEST(COALESCE(p_declared_value_gnf,0),0),
          p_authorized_gnf, p_evidence_ref, p_reason, v_caller, p_is_sandbox)
  ON CONFLICT (source_module, source_id) DO NOTHING
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN RETURN jsonb_build_object('status','already_exists'); END IF;

  PERFORM public._ledger_post(v_row.claim_key, p_source_module, p_source_id, 'claims_reserve_allocated',
    jsonb_build_array(
      jsonb_build_object('account','E_CLAIMS','amount_gnf',p_authorized_gnf,'memo','claims expense recognised'),
      jsonb_build_object('account','L_CLAIMS_RESERVE','amount_gnf',-p_authorized_gnf,'memo','reserve set aside')),
    p_mission_type, v_caller, jsonb_build_object('evidence_ref',p_evidence_ref), p_is_sandbox, p_reason);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'wallet','claims_reserve_allocated','claim',v_row.id::text,
          jsonb_build_object('authorized_gnf',p_authorized_gnf,'evidence_ref',p_evidence_ref), p_reason);

  RETURN jsonb_build_object('status','allocated','claim_id',v_row.id,'authorized_gnf',p_authorized_gnf,
                            'note','Discretionary claims reserve after investigation — never automatic insurance');
END; $$;

-- -------------------------------------------------------------------------
-- 9. Payout / settlement evidence uniqueness
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_payout_confirm(p_request_id uuid, p_evidence_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'PAYOUT_EVIDENCE_REQUIRED';
  END IF;
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'cashout' AND source_id = p_request_id AND kind = 'cashout' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Payout hold not found'; END IF;
  IF v_h.state <> 'held' THEN RETURN jsonb_build_object('status','already_resolved'); END IF;

  PERFORM public._finance_evidence_claim(p_evidence_ref,'driver_payout',p_request_id,v_h.amount_gnf,v_caller);

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf,0),
                            balance_gnf = balance_gnf - v_h.amount_gnf, updated_at = now()
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver';

  PERFORM public._ledger_post('cashout-paid:' || p_request_id::text, 'cashout', p_request_id, 'payout_paid',
    jsonb_build_array(
      jsonb_build_object('account','L_HOLD_CASHOUT','amount_gnf',v_h.amount_gnf,
                         'party_type','driver','party_user_id',v_h.driver_user_id,'memo','payout released'),
      jsonb_build_object('account','A_PROVIDER_CLEARING','amount_gnf',-v_h.amount_gnf,'memo','paid via provider')),
    NULL, v_caller, v_h.policy_snapshot, false, p_evidence_ref);

  UPDATE public.mission_financial_holds
     SET state='captured', captured_gnf = amount_gnf, captured_unrestricted_gnf = amount_gnf,
         evidence_ref = p_evidence_ref, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','paid','amount_gnf',v_h.amount_gnf);
END; $$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_complete(p_payable_id uuid, p_evidence_ref text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_p public.merchant_payables; v_amount bigint;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN
    RAISE EXCEPTION 'SETTLEMENT_EVIDENCE_REQUIRED';
  END IF;
  SELECT * INTO v_p FROM public.merchant_payables WHERE id = p_payable_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.state = 'settled' THEN RETURN jsonb_build_object('status','already_settled'); END IF;
  IF v_p.state <> 'settlement_held' THEN RAISE EXCEPTION 'SETTLEMENT_NOT_HELD'; END IF;
  v_amount := v_p.funded_gnf - v_p.settled_gnf;

  PERFORM public._finance_evidence_claim(p_evidence_ref,'merchant_settlement',v_p.id,v_amount,v_caller);

  IF v_p.merchant_user_id IS NOT NULL THEN
    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_amount,0),
                              balance_gnf = balance_gnf - v_amount, updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;

  PERFORM public._ledger_post('settle-paid:' || v_p.id::text, 'merchant_settlement', v_p.id,
    'merchant_settlement_paid',
    jsonb_build_array(
      jsonb_build_object('account','L_HOLD_SETTLEMENT','amount_gnf',v_amount,
                         'party_type','merchant','merchant_store_id',v_p.merchant_store_id,'memo','settlement released'),
      jsonb_build_object('account','A_PROVIDER_CLEARING','amount_gnf',-v_amount,'memo','paid out to provider')),
    v_p.mission_type, v_caller, v_p.policy_snapshot, v_p.is_sandbox, p_evidence_ref);

  UPDATE public.merchant_payables
     SET settled_gnf = settled_gnf + v_amount, state = 'settled', evidence_ref = p_evidence_ref,
         resolved_by = v_caller, resolved_at = now(), updated_at = now()
   WHERE id = v_p.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'wallet','merchant_settlement_paid','merchant_payable',v_p.id::text,
          jsonb_build_object('amount_gnf',v_amount,'evidence_ref',p_evidence_ref), p_evidence_ref);

  RETURN jsonb_build_object('status','settled','amount_gnf',v_amount);
END; $$;

-- -------------------------------------------------------------------------
-- 10. Server-authoritative cancellation debt
-- -------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.customer_cancellation_debt_create(text,uuid,uuid,text,text,bigint,text,boolean);

CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_create(
  p_source_module text, p_source_id uuid, p_customer uuid, p_mission_type text,
  p_stage text,
  p_fare_gnf bigint DEFAULT 0,
  p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0,
  p_preparation_started boolean DEFAULT false,
  p_responsible_party text DEFAULT 'customer',
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_req jsonb; v_snap jsonb; v_basis_kind text;
  v_bps int; v_basis bigint; v_amount bigint; v_exempt text;
  v_row public.customer_cancellation_debts;
BEGIN
  -- Internal/service or finance/God only. No customer-supplied amount is authoritative.
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_stage NOT IN ('before_dispatch','after_dispatch') THEN RAISE EXCEPTION 'Invalid stage'; END IF;
  IF p_responsible_party NOT IN ('customer','provider','platform','merchant','driver') THEN
    RAISE EXCEPTION 'Invalid responsible party';
  END IF;

  -- Repas: the customer may not cancel once the kitchen marks "En préparation".
  IF p_mission_type = 'repas' AND COALESCE(p_preparation_started,false)
     AND p_responsible_party = 'customer' THEN
    RAISE EXCEPTION 'REPAS_CANCELLATION_LOCKED'
      USING DETAIL = 'Customer cancellation is prohibited once preparation has started';
  END IF;

  v_req := public.finance_mission_requirement_v2(p_mission_type,0,0,0,0,'choppay');
  v_snap := COALESCE(v_req->'policy_snapshot','{}'::jsonb);
  v_basis_kind := COALESCE(v_snap->>'cancel_basis','none');

  -- Server resolves the basis from the snapshotted policy; caller supplies components only.
  v_basis := CASE v_basis_kind
    WHEN 'fare' THEN GREATEST(COALESCE(p_fare_gnf,0),0)
    WHEN 'merchandise_plus_delivery' THEN GREATEST(COALESCE(p_merchandise_subtotal_gnf,0),0)
                                        + GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    WHEN 'delivery_fee' THEN GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    ELSE 0 END;

  v_bps := CASE p_stage WHEN 'before_dispatch' THEN COALESCE((v_req->>'cancel_before_dispatch_bps')::int,0)
                        ELSE COALESCE((v_req->>'cancel_after_dispatch_bps')::int,0) END;
  v_amount := (v_basis * v_bps) / 10000;

  IF p_responsible_party <> 'customer' THEN
    v_exempt := format('not_customer_caused:%s', p_responsible_party);
    v_amount := 0;
  END IF;

  INSERT INTO public.customer_cancellation_debts
    (debt_key, customer_user_id, source_module, source_id, mission_type, stage,
     basis_gnf, applied_bps, amount_gnf, state, exempt_reason, policy_snapshot, is_sandbox)
  VALUES (format('cancel:%s:%s', p_source_module, p_source_id), p_customer, p_source_module,
          p_source_id, p_mission_type, p_stage, v_basis, v_bps, v_amount,
          CASE WHEN v_exempt IS NOT NULL THEN 'exempt' ELSE 'outstanding' END,
          v_exempt, v_snap || jsonb_build_object('cancel_basis_kind', v_basis_kind,
                                                 'preparation_started', COALESCE(p_preparation_started,false)),
          p_is_sandbox)
  ON CONFLICT (source_module, source_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN RETURN jsonb_build_object('status','already_exists'); END IF;

  IF v_amount > 0 THEN
    PERFORM public._ledger_post(v_row.debt_key, p_source_module, p_source_id, 'cancellation_fee_charged',
      jsonb_build_array(
        jsonb_build_object('account','A_CUSTOMER_DEBT','amount_gnf',v_amount,
                           'party_type','client','party_user_id',p_customer,'memo','cancellation fee receivable'),
        jsonb_build_object('account','R_CANCELLATION_FEE','amount_gnf',-v_amount,'memo','cancellation fee revenue')),
      p_mission_type, v_caller, v_snap, p_is_sandbox);
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN v_exempt IS NOT NULL THEN 'exempt' ELSE 'charged' END,
                            'debt_id',v_row.id,'basis_kind',v_basis_kind,'basis_gnf',v_basis,
                            'amount_gnf',v_amount,'applied_bps',v_bps);
END; $$;
REVOKE ALL ON FUNCTION public.customer_cancellation_debt_create(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.customer_cancellation_debt_create(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean) TO service_role;

-- -------------------------------------------------------------------------
-- 11. Explicit policy bases (appended, effective-dated — history preserved)
-- -------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_set_finance_policy(text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text);

CREATE OR REPLACE FUNCTION public.admin_set_finance_policy(
  p_mission_type text, p_commission_bps integer,
  p_min_driver_balance_gnf bigint DEFAULT 0,
  p_collateral_mode text DEFAULT 'none',
  p_collateral_pct_bps integer DEFAULT 0,
  p_collateral_fixed_gnf bigint DEFAULT 0,
  p_collateral_min_gnf bigint DEFAULT 0,
  p_collateral_max_gnf bigint DEFAULT NULL,
  p_fixed_commission_gnf bigint DEFAULT 0,
  p_require_collateral_before_offer boolean DEFAULT false,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL,
  p_collateral_basis text DEFAULT NULL,
  p_transaction_fee_bps integer DEFAULT NULL,
  p_fee_basis text DEFAULT NULL,
  p_cancel_before_dispatch_bps integer DEFAULT NULL,
  p_cancel_after_dispatch_bps integer DEFAULT NULL,
  p_cancel_basis text DEFAULT NULL,
  p_cash_funding_mode text DEFAULT NULL,
  p_cash_funding_pct_bps integer DEFAULT NULL,
  p_cash_funding_max_gnf bigint DEFAULT NULL,
  p_max_declared_value_gnf bigint DEFAULT NULL)
RETURNS finance_policies LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.finance_policies;
  v_new public.finance_policies;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change finance policy';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'Effective date cannot be in the past';
  END IF;

  SELECT * INTO v_before FROM public.finance_policy_current(p_mission_type);

  IF p_collateral_basis IS NOT NULL
     AND p_collateral_basis NOT IN ('none','fare','merchandise_subtotal','declared_value') THEN
    RAISE EXCEPTION 'Invalid collateral basis';
  END IF;
  IF p_cancel_basis IS NOT NULL
     AND p_cancel_basis NOT IN ('none','fare','merchandise_plus_delivery','delivery_fee') THEN
    RAISE EXCEPTION 'Invalid cancellation basis';
  END IF;
  IF p_fee_basis IS NOT NULL
     AND p_fee_basis NOT IN ('none','fare','merchandise_subtotal','declared_value','delivery_fee','order_total','transfer_amount') THEN
    RAISE EXCEPTION 'Invalid fee basis';
  END IF;
  IF p_collateral_mode <> 'none' AND COALESCE(p_collateral_basis, v_before.collateral_basis, 'none') = 'none' THEN
    RAISE EXCEPTION 'COLLATERAL_BASIS_REQUIRED'
      USING DETAIL = 'A collateral mode other than none requires an explicit collateral basis';
  END IF;
  IF COALESCE(p_transaction_fee_bps, v_before.transaction_fee_bps, 0) > 0
     AND COALESCE(p_fee_basis, v_before.fee_basis, 'none') = 'none' THEN
    RAISE EXCEPTION 'FEE_BASIS_REQUIRED';
  END IF;
  IF GREATEST(COALESCE(p_cancel_before_dispatch_bps, v_before.cancel_before_dispatch_bps, 0),
              COALESCE(p_cancel_after_dispatch_bps, v_before.cancel_after_dispatch_bps, 0)) > 0
     AND COALESCE(p_cancel_basis, v_before.cancel_basis, 'none') = 'none' THEN
    RAISE EXCEPTION 'CANCEL_BASIS_REQUIRED';
  END IF;

  INSERT INTO public.finance_policies
    (mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
     collateral_mode, collateral_pct_bps, collateral_fixed_gnf,
     collateral_min_gnf, collateral_max_gnf, require_collateral_before_offer,
     collateral_basis, transaction_fee_bps, fee_basis,
     cancel_before_dispatch_bps, cancel_after_dispatch_bps, cancel_basis,
     cash_funding_mode, cash_funding_pct_bps, cash_funding_max_gnf,
     max_declared_value_gnf, effective_from, note, created_by)
  VALUES
    (p_mission_type, p_commission_bps, p_fixed_commission_gnf, p_min_driver_balance_gnf,
     p_collateral_mode, p_collateral_pct_bps, p_collateral_fixed_gnf,
     p_collateral_min_gnf, p_collateral_max_gnf, p_require_collateral_before_offer,
     COALESCE(p_collateral_basis, v_before.collateral_basis, 'none'),
     COALESCE(p_transaction_fee_bps, v_before.transaction_fee_bps, 0),
     COALESCE(p_fee_basis, v_before.fee_basis, 'none'),
     COALESCE(p_cancel_before_dispatch_bps, v_before.cancel_before_dispatch_bps, 500),
     COALESCE(p_cancel_after_dispatch_bps, v_before.cancel_after_dispatch_bps, 1000),
     COALESCE(p_cancel_basis, v_before.cancel_basis, 'none'),
     COALESCE(p_cash_funding_mode, v_before.cash_funding_mode, 'none'),
     COALESCE(p_cash_funding_pct_bps, v_before.cash_funding_pct_bps, 0),
     COALESCE(p_cash_funding_max_gnf, v_before.cash_funding_max_gnf),
     COALESCE(p_max_declared_value_gnf, v_before.max_declared_value_gnf),
     p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id,
                                 before, after, note)
  VALUES (v_caller, 'pricing', 'finance_policy_set', 'finance_policy', p_mission_type,
          to_jsonb(v_before), to_jsonb(v_new), p_note);

  RETURN v_new;
END; $$;

-- Append corrected effective-dated rows carrying explicit bases.
INSERT INTO public.finance_policies
  (mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
   collateral_mode, collateral_pct_bps, collateral_fixed_gnf, collateral_min_gnf,
   collateral_max_gnf, require_collateral_before_offer, collateral_basis,
   transaction_fee_bps, fee_basis, cancel_before_dispatch_bps, cancel_after_dispatch_bps,
   cancel_basis, cash_funding_mode, cash_funding_pct_bps, cash_funding_max_gnf,
   max_declared_value_gnf, effective_from, note)
SELECT c.mission_type, c.commission_bps, c.fixed_commission_gnf, c.min_driver_balance_gnf,
       c.collateral_mode, c.collateral_pct_bps, c.collateral_fixed_gnf, c.collateral_min_gnf,
       c.collateral_max_gnf, c.require_collateral_before_offer,
       b.collateral_basis, c.transaction_fee_bps, c.fee_basis,
       c.cancel_before_dispatch_bps, c.cancel_after_dispatch_bps, b.cancel_basis,
       c.cash_funding_mode, c.cash_funding_pct_bps, c.cash_funding_max_gnf,
       c.max_declared_value_gnf, now(),
       'Slice 1 exit-gate correction: explicit collateral and cancellation bases (canonical policy §4, §5, §8)'
  FROM (VALUES
    ('ride','none','fare'),
    ('bonbonna','none','fare'),
    ('repas','merchandise_subtotal','merchandise_plus_delivery'),
    ('marche','merchandise_subtotal','merchandise_plus_delivery'),
    ('envoyer','declared_value','delivery_fee')
  ) AS b(mission_type, collateral_basis, cancel_basis)
  CROSS JOIN LATERAL public.finance_policy_current(b.mission_type) c;

-- -------------------------------------------------------------------------
-- 12. Hold placement: ineligible drivers cannot create new holds
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._driver_finance_eligible(p_driver uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT NOT public.is_user_banned(p_driver)
     AND NOT public.is_user_frozen(p_driver)
     AND NOT EXISTS (
       SELECT 1 FROM public.driver_profiles dp
        WHERE dp.user_id = p_driver AND dp.status IN ('suspended','rejected')
     );
$$;

CREATE OR REPLACE FUNCTION public.driver_mission_hold_place(p_mission_type text, p_source_module text, p_source_id uuid, p_value_gnf bigint DEFAULT 0, p_driver uuid DEFAULT NULL::uuid, p_is_sandbox boolean DEFAULT false, p_kinds text[] DEFAULT NULL::text[], p_fare_gnf bigint DEFAULT NULL::bigint, p_merchandise_subtotal_gnf bigint DEFAULT NULL::bigint, p_delivery_fee_gnf bigint DEFAULT NULL::bigint, p_declared_value_gnf bigint DEFAULT NULL::bigint, p_payment_mode text DEFAULT 'choppay'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid := COALESCE(p_driver, auth.uid());
  v_req jsonb; v_wallet public.wallets; v_avail bigint; v_total bigint := 0; v_existing int;
  v_kind text; v_amount bigint; v_alloc jsonb; v_u bigint; v_p bigint;
  v_tx public.wallet_transactions; v_key text; v_ids jsonb := '[]'::jsonb;
  v_kinds text[] := COALESCE(p_kinds, ARRAY['commission','collateral']);
BEGIN
  IF v_driver IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;
  IF v_driver <> COALESCE(v_caller, v_driver) AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF NOT public._driver_finance_eligible(v_driver) THEN
    RAISE EXCEPTION 'ACCOUNT_RESTRICTED';
  END IF;

  SELECT count(*) INTO v_existing FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = ANY(v_kinds);
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('status', 'already_held', 'source_id', p_source_id);
  END IF;

  v_req := public.finance_mission_requirement_v2(
    p_mission_type,
    COALESCE(p_fare_gnf, CASE WHEN p_mission_type IN ('ride','bonbonna') THEN p_value_gnf ELSE 0 END),
    COALESCE(p_merchandise_subtotal_gnf, CASE WHEN p_mission_type IN ('repas','marche') THEN p_value_gnf ELSE 0 END),
    COALESCE(p_delivery_fee_gnf, 0),
    COALESCE(p_declared_value_gnf, CASE WHEN p_mission_type = 'envoyer' THEN p_value_gnf ELSE 0 END),
    COALESCE(p_payment_mode, 'choppay'));

  IF (v_req->>'declared_value_exceeds_cap')::boolean THEN
    RAISE EXCEPTION 'DECLARED_VALUE_ABOVE_CAP' USING DETAIL = format('max=%s', v_req->>'max_declared_value_gnf');
  END IF;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_driver, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet not active'; END IF;

  v_avail := GREATEST(v_wallet.balance_gnf - v_wallet.held_gnf, 0);
  IF v_avail < (v_req->>'required_available_gnf')::bigint THEN
    RAISE EXCEPTION 'INSUFFICIENT_DRIVER_BALANCE'
      USING DETAIL = format('required=%s available=%s', v_req->>'required_available_gnf', v_avail);
  END IF;

  FOREACH v_kind IN ARRAY v_kinds LOOP
    v_amount := CASE v_kind
      WHEN 'commission'   THEN (v_req->>'commission_gnf')::bigint
      WHEN 'collateral'   THEN (v_req->>'collateral_gnf')::bigint
      WHEN 'platform_fee' THEN (v_req->>'platform_fee_gnf')::bigint
      WHEN 'cash_funding' THEN (v_req->>'cash_funding_gnf')::bigint
      ELSE 0 END;
    CONTINUE WHEN COALESCE(v_amount, 0) <= 0;

    v_alloc := public.driver_funding_allocate(v_driver, v_amount, v_kind);
    IF NOT (v_alloc->>'ok')::boolean THEN
      RAISE EXCEPTION '%', COALESCE(v_alloc->>'reason', 'INSUFFICIENT_DRIVER_BALANCE');
    END IF;
    v_u := (v_alloc->>'unrestricted_gnf')::bigint;
    v_p := (v_alloc->>'promo_gnf')::bigint;
    v_key := format('mfh:%s:%s:%s', p_source_module, p_source_id, v_kind);

    INSERT INTO public.wallet_transactions
      (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
       related_entity, description, metadata)
    VALUES (v_key, 'hold', 'pending', v_amount, v_wallet.id, v_driver,
       p_source_module || ':' || p_source_id::text,
       CASE v_kind
         WHEN 'commission'   THEN 'Réserve de commission mission'
         WHEN 'collateral'   THEN 'Caution mission'
         WHEN 'platform_fee' THEN 'Frais de service CHOPCHOP'
         ELSE 'Avance marchandise (commande espèces)' END,
       jsonb_build_object('mission_type', p_mission_type, 'kind', v_kind,
                          'is_sandbox', p_is_sandbox, 'unrestricted_gnf', v_u, 'promo_gnf', v_p))
    RETURNING * INTO v_tx;

    UPDATE public.wallets SET held_gnf = held_gnf + v_amount, updated_at = now() WHERE id = v_wallet.id;

    PERFORM public._ledger_post(
      v_key, p_source_module, p_source_id, 'hold_' || v_kind,
      jsonb_build_array(
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',v_u,
                           'party_type','driver','party_user_id',v_driver,'memo','hold from unrestricted'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',v_p,
                           'party_type','driver','party_user_id',v_driver,'memo','hold from restricted credit'),
        jsonb_build_object('account',public._hold_account(v_kind),'amount_gnf',-v_amount,
                           'party_type','driver','party_user_id',v_driver,'memo',v_kind||' hold')),
      p_mission_type, v_caller, COALESCE(v_req->'policy_snapshot','{}'::jsonb), p_is_sandbox);

    INSERT INTO public.mission_financial_holds
      (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
       amount_gnf, unrestricted_gnf, promo_gnf, hold_tx_id, policy_id,
       policy_snapshot, basis_value_gnf, is_sandbox, journal_key)
    VALUES (v_driver, 'driver', v_driver, p_mission_type, p_source_module, p_source_id, v_kind,
       v_amount, v_u, v_p, v_tx.id, (v_req->>'policy_id')::uuid,
       COALESCE(v_req->'policy_snapshot', '{}'::jsonb),
       CASE v_kind
         WHEN 'commission' THEN (v_req->>'commission_basis_gnf')::bigint
         WHEN 'collateral' THEN (v_req->>'collateral_basis_gnf')::bigint
         WHEN 'platform_fee' THEN (v_req->>'fee_basis_gnf')::bigint
         ELSE (v_req->>'merchandise_subtotal_gnf')::bigint END,
       p_is_sandbox, v_key);

    v_total := v_total + v_amount;
    v_ids := v_ids || jsonb_build_object('kind', v_kind, 'amount_gnf', v_amount,
                                         'unrestricted_gnf', v_u, 'promo_gnf', v_p);
  END LOOP;

  RETURN jsonb_build_object('status','held','total_gnf',v_total,'holds',v_ids,'requirement',v_req);
END; $$;
