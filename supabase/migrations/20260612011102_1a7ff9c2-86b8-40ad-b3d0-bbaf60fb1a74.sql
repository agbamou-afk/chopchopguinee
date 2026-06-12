
-- =========================================================
-- Phase 5: CHOPPay Payment Intent + Capture Foundation
-- =========================================================

-- 1) Extend payment_intents
ALTER TABLE public.payment_intents
  ADD COLUMN IF NOT EXISTS source_module text,
  ADD COLUMN IF NOT EXISTS source_id uuid,
  ADD COLUMN IF NOT EXISTS payee_user_id uuid,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS wallet_hold_tx_id uuid REFERENCES public.wallet_transactions(id),
  ADD COLUMN IF NOT EXISTS captured_tx_id uuid REFERENCES public.wallet_transactions(id),
  ADD COLUMN IF NOT EXISTS settlement_tx_id uuid REFERENCES public.wallet_transactions(id),
  ADD COLUMN IF NOT EXISTS captured_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

ALTER TABLE public.payment_intents
  DROP CONSTRAINT IF EXISTS payment_intents_source_module_chk;
ALTER TABLE public.payment_intents
  ADD CONSTRAINT payment_intents_source_module_chk
  CHECK (source_module IS NULL OR source_module IN
    ('marketplace','repas','ride','mission','topup','manual'));

CREATE INDEX IF NOT EXISTS idx_payment_intents_source
  ON public.payment_intents(source_module, source_id);

-- Unique idempotency per (source_module, source_id, user_id) when set
CREATE UNIQUE INDEX IF NOT EXISTS uidx_payment_intents_source_payer_active
  ON public.payment_intents(source_module, source_id, user_id)
  WHERE source_module IS NOT NULL
    AND source_id    IS NOT NULL
    AND state IN ('pending','processing','confirmed');

-- 2) food_orders.payment_status
ALTER TABLE public.food_orders
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid';

ALTER TABLE public.food_orders
  DROP CONSTRAINT IF EXISTS food_orders_payment_status_chk;
ALTER TABLE public.food_orders
  ADD CONSTRAINT food_orders_payment_status_chk
  CHECK (payment_status IN
    ('unpaid','pending','authorized','paid','failed','refunded','cancelled'));

-- =========================================================
-- 3) choppay_create_payment_intent
-- =========================================================
CREATE OR REPLACE FUNCTION public.choppay_create_payment_intent(
  p_source_module     text,
  p_source_id         uuid,
  p_amount_gnf        bigint,
  p_purpose           payment_purpose,
  p_merchant_store_id uuid    DEFAULT NULL,
  p_payee_user_id     uuid    DEFAULT NULL,
  p_description       text    DEFAULT NULL,
  p_metadata          jsonb   DEFAULT '{}'::jsonb,
  p_use_wallet        boolean DEFAULT true
)
RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_payer uuid := auth.uid();
  v_existing public.payment_intents;
  v_hold public.wallet_transactions;
  v_intent public.payment_intents;
  v_ref text;
  v_state payment_state;
  v_provider payment_provider;
BEGIN
  IF v_payer IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF p_source_module NOT IN ('marketplace','repas','ride','mission','topup','manual') THEN
    RAISE EXCEPTION 'invalid_source_module';
  END IF;
  IF p_source_id IS NULL THEN
    RAISE EXCEPTION 'source_id_required';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  -- Idempotency: return existing active intent for this (module, id, payer)
  SELECT * INTO v_existing
    FROM public.payment_intents
   WHERE source_module = p_source_module
     AND source_id     = p_source_id
     AND user_id       = v_payer
     AND state IN ('pending','processing','confirmed')
   ORDER BY created_at DESC
   LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  v_ref := 'choppay:' || p_source_module || ':' || p_source_id::text
        || ':' || v_payer::text || ':' || extract(epoch from now())::bigint::text;
  v_provider := CASE WHEN p_use_wallet THEN 'internal'::payment_provider
                     ELSE 'manual'::payment_provider END;

  -- If wallet path, attempt hold first
  IF p_use_wallet THEN
    BEGIN
      v_hold := public.wallet_hold(
        p_amount_gnf := p_amount_gnf,
        p_reference  := v_ref || ':hold',
        p_description := coalesce(p_description, 'CHOPPay hold ' || p_source_module)
      );
      v_state := 'processing'; -- authorized
    EXCEPTION WHEN OTHERS THEN
      v_hold := NULL;
      v_state := 'failed';
    END;
  ELSE
    v_state := 'pending';
  END IF;

  INSERT INTO public.payment_intents(
    user_id, amount_gnf, currency, purpose, state, provider, internal_reference,
    related_store_id, source_module, source_id, payee_user_id, description,
    wallet_hold_tx_id, metadata
  ) VALUES (
    v_payer, p_amount_gnf, 'GNF', p_purpose, v_state, v_provider, v_ref,
    p_merchant_store_id, p_source_module, p_source_id, p_payee_user_id, p_description,
    v_hold.id,
    coalesce(p_metadata,'{}'::jsonb)
      || jsonb_build_object(
        'use_wallet', p_use_wallet,
        'hold_attempted', p_use_wallet,
        'hold_succeeded', v_hold.id IS NOT NULL
      )
  ) RETURNING * INTO v_intent;

  RETURN v_intent;
END;
$$;

REVOKE ALL ON FUNCTION public.choppay_create_payment_intent(text,uuid,bigint,payment_purpose,uuid,uuid,text,jsonb,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.choppay_create_payment_intent(text,uuid,bigint,payment_purpose,uuid,uuid,text,jsonb,boolean) TO authenticated, service_role;

-- =========================================================
-- 4) choppay_capture_payment_intent  (service_role only)
-- =========================================================
CREATE OR REPLACE FUNCTION public.choppay_capture_payment_intent(
  p_payment_intent_id uuid,
  p_reason text DEFAULT 'Capture CHOPPay payment'
)
RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_intent public.payment_intents;
  v_hold public.wallet_transactions;
  v_pay  public.wallet_transactions;
BEGIN
  SELECT * INTO v_intent FROM public.payment_intents
    WHERE id = p_payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN
    RAISE EXCEPTION 'intent_not_found';
  END IF;

  -- Idempotent: already captured
  IF v_intent.state = 'confirmed' THEN
    RETURN v_intent;
  END IF;

  IF v_intent.state NOT IN ('pending','processing') THEN
    RAISE EXCEPTION 'intent_not_capturable: state=%', v_intent.state;
  END IF;

  IF v_intent.wallet_hold_tx_id IS NULL THEN
    RAISE EXCEPTION 'no_wallet_hold_to_capture';
  END IF;

  SELECT * INTO v_hold FROM public.wallet_transactions
    WHERE id = v_intent.wallet_hold_tx_id FOR UPDATE;

  -- Capture to master wallet (settlement happens in later phase)
  v_pay := public.wallet_capture(
    p_hold_id := v_intent.wallet_hold_tx_id,
    p_to_user_id := NULL,
    p_to_party_type := 'master',
    p_actual_amount_gnf := v_intent.amount_gnf,
    p_description := p_reason
  );

  UPDATE public.payment_intents
     SET state = 'confirmed',
         captured_tx_id = v_pay.id,
         captured_at = now(),
         metadata = metadata || jsonb_build_object('captured_reason', p_reason)
   WHERE id = v_intent.id
   RETURNING * INTO v_intent;

  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, payload, actor_user_id)
  VALUES
    (v_intent.id, 'wallet_credited', v_intent.provider,
     jsonb_build_object('captured_tx_id', v_pay.id, 'reason', p_reason),
     auth.uid());

  RETURN v_intent;
END;
$$;

REVOKE ALL ON FUNCTION public.choppay_capture_payment_intent(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.choppay_capture_payment_intent(uuid,text) TO service_role;

-- =========================================================
-- 5) choppay_cancel_payment_intent
-- =========================================================
CREATE OR REPLACE FUNCTION public.choppay_cancel_payment_intent(
  p_payment_intent_id uuid,
  p_reason text DEFAULT 'Payment cancelled'
)
RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_intent public.payment_intents;
  v_is_admin boolean;
BEGIN
  SELECT * INTO v_intent FROM public.payment_intents
    WHERE id = p_payment_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN
    RAISE EXCEPTION 'intent_not_found';
  END IF;

  v_is_admin := (v_caller IS NOT NULL) AND public.has_role(v_caller,'admin');

  IF v_caller IS NULL OR (v_intent.user_id <> v_caller AND NOT v_is_admin) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Idempotent
  IF v_intent.state IN ('cancelled','failed') THEN
    RETURN v_intent;
  END IF;

  IF v_intent.state = 'confirmed' THEN
    RAISE EXCEPTION 'cannot_cancel_captured_intent';
  END IF;

  -- Release hold if any & still pending
  IF v_intent.wallet_hold_tx_id IS NOT NULL THEN
    BEGIN
      PERFORM public.wallet_release(v_intent.wallet_hold_tx_id, p_reason);
    EXCEPTION WHEN OTHERS THEN
      NULL; -- already released/captured
    END;
  END IF;

  UPDATE public.payment_intents
     SET state = 'cancelled',
         cancelled_at = now(),
         metadata = metadata || jsonb_build_object('cancel_reason', p_reason)
   WHERE id = v_intent.id
   RETURNING * INTO v_intent;

  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, payload, actor_user_id)
  VALUES
    (v_intent.id, 'provider_failed', v_intent.provider,
     jsonb_build_object('cancelled', true, 'reason', p_reason),
     v_caller);

  RETURN v_intent;
END;
$$;

REVOKE ALL ON FUNCTION public.choppay_cancel_payment_intent(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.choppay_cancel_payment_intent(uuid,text) TO authenticated, service_role;

-- =========================================================
-- 6) admin_preview_payment_intents
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_preview_payment_intents(
  p_state text DEFAULT NULL,
  p_source_module text DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  id uuid, source_module text, source_id uuid, payer_user_id uuid,
  payee_user_id uuid, merchant_store_id uuid, amount_gnf bigint,
  state payment_state, provider payment_provider, internal_reference text,
  wallet_hold_tx_id uuid, captured_tx_id uuid, settlement_tx_id uuid,
  metadata jsonb, created_at timestamptz, captured_at timestamptz,
  cancelled_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_any_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: admin required';
  END IF;
  RETURN QUERY
  SELECT pi.id, pi.source_module, pi.source_id, pi.user_id,
         pi.payee_user_id, pi.related_store_id, pi.amount_gnf,
         pi.state, pi.provider, pi.internal_reference,
         pi.wallet_hold_tx_id, pi.captured_tx_id, pi.settlement_tx_id,
         pi.metadata, pi.created_at, pi.captured_at, pi.cancelled_at
    FROM public.payment_intents pi
   WHERE (p_state IS NULL OR pi.state::text = p_state)
     AND (p_source_module IS NULL OR pi.source_module = p_source_module)
   ORDER BY pi.created_at DESC
   LIMIT coalesce(p_limit,100);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_preview_payment_intents(text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_payment_intents(text,text,integer) TO authenticated, service_role;
