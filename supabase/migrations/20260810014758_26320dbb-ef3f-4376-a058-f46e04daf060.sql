-- P1-1: atomic tender on Marché offer creation (single signature, no overload)
DROP FUNCTION IF EXISTS public.create_marketplace_offer(uuid, bigint, text);

CREATE OR REPLACE FUNCTION public.create_marketplace_offer(
  p_listing_id uuid,
  p_amount_gnf bigint,
  p_message text DEFAULT NULL::text,
  p_payment_method text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  caller uuid := auth.uid();
  v public.marketplace_listings;
  v_store_status text;
  v_store_onb text;
  v_offer_id uuid;
  v_meta jsonb := '{}'::jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF public.is_user_banned(caller) THEN RAISE EXCEPTION 'account blocked'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_freezes
    WHERE user_id = caller AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  ) THEN
    RAISE EXCEPTION 'account frozen';
  END IF;

  -- Explicit tender only. NULL keeps legacy behaviour (never interpreted as cash).
  IF p_payment_method IS NOT NULL AND p_payment_method NOT IN ('cash','choppay') THEN
    RAISE EXCEPTION 'INVALID_TENDER';
  END IF;

  SELECT * INTO v FROM public.marketplace_listings WHERE id = p_listing_id;
  IF v.id IS NULL THEN RAISE EXCEPTION 'listing not found'; END IF;
  IF v.seller_id = caller THEN RAISE EXCEPTION 'cannot offer on own listing'; END IF;
  IF v.status <> 'active' OR v.visibility <> 'public' THEN
    RAISE EXCEPTION 'listing not available';
  END IF;
  IF NOT v.allow_offers OR v.pricing_mode NOT IN ('negotiable','quote') THEN
    RAISE EXCEPTION 'offers not allowed';
  END IF;
  IF coalesce(v.quantity_in_stock, 0) <= 0 THEN RAISE EXCEPTION 'out of stock'; END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN RAISE EXCEPTION 'invalid amount'; END IF;

  IF v.store_id IS NOT NULL THEN
    SELECT status, onboarding_status INTO v_store_status, v_store_onb
    FROM public.merchant_stores WHERE id = v.store_id;
    IF v_store_onb <> 'approved' OR v_store_status NOT IN ('active','paused') THEN
      RAISE EXCEPTION 'store not active';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.marketplace_offers
    WHERE listing_id = p_listing_id AND buyer_user_id = caller
      AND status IN ('pending','countered')
  ) THEN
    RAISE EXCEPTION 'pending offer already exists';
  END IF;

  IF p_payment_method IS NOT NULL THEN
    v_meta := jsonb_build_object('payment_method', p_payment_method);
  END IF;

  INSERT INTO public.marketplace_offers (
    listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
    offer_amount_gnf, buyer_message, expires_at, metadata
  ) VALUES (
    p_listing_id, v.store_id, caller, v.seller_id,
    p_amount_gnf, nullif(trim(p_message), ''), now() + interval '7 days',
    CASE WHEN p_payment_method IS NULL THEN NULL ELSE v_meta END
  ) RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_marketplace_offer(uuid, bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_marketplace_offer(uuid, bigint, text, text) TO authenticated;

-- P1-2: explicit cash tender is authoritative, even before a runtime row exists
CREATE OR REPLACE FUNCTION public._cash_order_block_direct_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.state IS DISTINCT FROM OLD.state
     AND COALESCE(current_setting('chopchop.cash_engine', true), '0') <> '1'
     AND (
       NEW.payment_method::text = 'cash'
       OR EXISTS (SELECT 1 FROM public.cash_order_runtime
                   WHERE source_module = 'repas' AND source_id = NEW.id)
     ) THEN
    RAISE EXCEPTION 'CASH_ORDER_STATE_ENGINE_ONLY'
      USING DETAIL = 'Cash orders must transition through the cash order engine';
  END IF;
  RETURN NEW;
END; $function$;

-- P1-5: Marché mission claim requires explicit tender
CREATE OR REPLACE FUNCTION public.mission_claim(_mission_id uuid)
RETURNS missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _m   public.missions;
  _cs  jsonb;
  _tender text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS NOT NULL THEN RAISE EXCEPTION 'mission_already_claimed'; END IF;
  IF NOT public.driver_has_capability(_uid, public.mission_required_capability(_m.type)) THEN
    RAISE EXCEPTION 'capability_missing';
  END IF;

  -- Marché: explicit tender must be resolved before assignment finalises.
  IF _m.type = 'marketplace_delivery' AND _m.ref_market_order_id IS NOT NULL THEN
    SELECT mo.metadata->>'payment_method' INTO _tender
      FROM public.marketplace_offers mo WHERE mo.id = _m.ref_market_order_id;
    IF _tender IS NULL OR _tender NOT IN ('cash','choppay') THEN
      RAISE EXCEPTION 'MARCHE_TENDER_REQUIRED'
        USING DETAIL = 'explicit payment method required before courier assignment';
    END IF;
  END IF;

  UPDATE public.missions SET courier_id = _uid WHERE id = _mission_id RETURNING * INTO _m;

  _cs := public._mission_cash_source(_m);
  IF _cs IS NOT NULL
     AND public._cash_order_is_cash(_cs->>'module', (_cs->>'source_id')::uuid) THEN
    PERFORM public._cash_order_accept_internal(
      _cs->>'module', (_cs->>'source_id')::uuid, _uid);
  END IF;

  UPDATE public.missions SET state = 'heading_to_pickup'
   WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END; $function$;

-- Hardening: beneficiary must be the exact runtime driver
CREATE OR REPLACE FUNCTION public._merchant_payable_reverse_internal(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid,
  p_beneficiary uuid, p_reason text, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p public.merchant_payables; v_amount bigint; v_mw public.wallets; v_dw public.wallets;
  v_driver uuid;
BEGIN
  SELECT driver_user_id INTO v_driver FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_driver IS NULL THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','no cash order runtime for source');
  END IF;
  IF p_beneficiary IS NULL OR p_beneficiary <> v_driver THEN
    RAISE EXCEPTION 'BENEFICIARY_MISMATCH'
      USING DETAIL = 'reversal beneficiary must be the cash order driver';
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = p_merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RETURN jsonb_build_object('status','no_payable','reversed_gnf',0); END IF;
  IF v_p.state = 'reversed' THEN
    RETURN jsonb_build_object('status','already_reversed','reversed_gnf',0);
  END IF;
  IF v_p.funded_gnf = 0 THEN
    UPDATE public.merchant_payables
       SET state = 'reversed', reason = COALESCE(p_reason, reason),
           resolved_at = now(), resolved_by = p_actor, updated_at = now()
     WHERE id = v_p.id;
    RETURN jsonb_build_object('status','not_funded','reversed_gnf',0);
  END IF;
  IF v_p.funding_source <> 'driver_cash_funding' THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','funding source is not driver cash funding');
  END IF;
  IF v_p.settled_gnf > 0 OR v_p.state IN ('settled','settlement_held') THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','payable already settled externally');
  END IF;

  v_amount := v_p.funded_gnf;

  SELECT * INTO v_mw FROM public.wallets
   WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant' FOR UPDATE;
  IF v_mw.id IS NULL OR (v_mw.balance_gnf - v_mw.held_gnf) < v_amount THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','insufficient recoverable merchant liability');
  END IF;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_dw.id IS NULL THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','driver wallet missing');
  END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - v_amount, updated_at = now()
   WHERE id = v_mw.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount, updated_at = now()
   WHERE id = v_dw.id;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('payable-reverse:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
     'reversal', 'completed', v_amount, v_mw.id, v_dw.id, v_p.merchant_user_id,
     p_source_module || ':' || p_source_id::text,
     'Reprise du financement marchandise (litige)',
     jsonb_build_object('reason', p_reason, 'restored_as','unrestricted',
                        'is_sandbox', v_p.is_sandbox), now());

  PERFORM public._ledger_post(
    format('payable-reverse:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
    p_source_module, p_source_id, 'merchant_payable_reversed',
    jsonb_build_array(
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'memo','reverse merchant liability'),
      jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_amount,
                         'party_type','driver','party_user_id',v_dw.owner_user_id,
                         'memo','restore merchandise principal as unrestricted')),
    v_p.mission_type, p_actor, v_p.policy_snapshot, v_p.is_sandbox);

  UPDATE public.merchant_payables
     SET funded_gnf = 0, state = 'reversed', reason = COALESCE(p_reason, reason),
         resolved_at = now(), resolved_by = p_actor, updated_at = now()
   WHERE id = v_p.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (p_actor, 'finance', 'merchant_payable_reversed', 'merchant_payables', v_p.id::text,
          jsonb_build_object('reversed_gnf', v_amount, 'merchant_user_id', v_p.merchant_user_id,
                             'driver_user_id', v_dw.owner_user_id), p_reason);

  RETURN jsonb_build_object('status','reversed','reversed_gnf',v_amount,
                            'merchant_user_id',v_p.merchant_user_id,
                            'driver_user_id',v_dw.owner_user_id);
END; $function$;

REVOKE ALL ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) TO service_role;