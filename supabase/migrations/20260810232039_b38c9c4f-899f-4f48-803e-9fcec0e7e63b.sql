-- 1) Exact-amount, frozen-snapshot driver collateral hold (service-role only)
CREATE OR REPLACE FUNCTION public._driver_exact_hold_place_internal(
  p_mission_type text,
  p_source_module text,
  p_source_id uuid,
  p_driver uuid,
  p_amount bigint,
  p_kind text DEFAULT 'collateral',
  p_snapshot jsonb DEFAULT '{}'::jsonb,
  p_basis_value_gnf bigint DEFAULT 0,
  p_policy_id uuid DEFAULT NULL,
  p_is_sandbox boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_wallet public.wallets; v_avail bigint; v_alloc jsonb; v_u bigint; v_p bigint;
  v_tx public.wallet_transactions; v_key text; v_amount bigint := COALESCE(p_amount,0);
BEGIN
  IF p_kind <> 'collateral' THEN RAISE EXCEPTION 'EXACT_HOLD_KIND_NOT_ALLOWED' USING DETAIL = p_kind; END IF;
  IF p_driver IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;
  IF v_amount < 0 THEN RAISE EXCEPTION 'INVALID_HOLD_AMOUNT'; END IF;
  IF NOT public._driver_finance_eligible(p_driver) THEN RAISE EXCEPTION 'ACCOUNT_RESTRICTED'; END IF;

  -- Idempotent / replay safe
  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE source_module = p_source_module AND source_id = p_source_id AND kind = p_kind) THEN
    RETURN jsonb_build_object('status','already_held','amount_gnf',v_amount);
  END IF;
  IF v_amount = 0 THEN
    RETURN jsonb_build_object('status','zero','amount_gnf',0);
  END IF;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (p_driver,'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet not active'; END IF;

  v_avail := GREATEST(v_wallet.balance_gnf - v_wallet.held_gnf, 0);
  IF v_avail < v_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_DRIVER_BALANCE'
      USING DETAIL = format('required=%s available=%s', v_amount, v_avail);
  END IF;

  v_alloc := public.driver_funding_allocate(p_driver, v_amount, p_kind);
  IF NOT (v_alloc->>'ok')::boolean THEN
    RAISE EXCEPTION '%', COALESCE(v_alloc->>'reason','INSUFFICIENT_DRIVER_BALANCE');
  END IF;
  v_u := (v_alloc->>'unrestricted_gnf')::bigint;
  v_p := (v_alloc->>'promo_gnf')::bigint;
  v_key := format('mfh:%s:%s:%s', p_source_module, p_source_id, p_kind);

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
     related_entity, description, metadata)
  VALUES (v_key,'hold','pending', v_amount, v_wallet.id, p_driver,
     p_source_module || ':' || p_source_id::text, 'Caution mission',
     jsonb_build_object('mission_type',p_mission_type,'kind',p_kind,'is_sandbox',p_is_sandbox,
                        'unrestricted_gnf',v_u,'promo_gnf',v_p,'frozen_snapshot',true))
  RETURNING * INTO v_tx;

  UPDATE public.wallets SET held_gnf = held_gnf + v_amount, updated_at = now() WHERE id = v_wallet.id;

  PERFORM public._ledger_post(
    v_key, p_source_module, p_source_id, 'hold_' || p_kind,
    jsonb_build_array(
      jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',v_u,
                         'party_type','driver','party_user_id',p_driver,'memo','hold from unrestricted'),
      jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',v_p,
                         'party_type','driver','party_user_id',p_driver,'memo','hold from restricted credit'),
      jsonb_build_object('account',public._hold_account(p_kind),'amount_gnf',-v_amount,
                         'party_type','driver','party_user_id',p_driver,'memo',p_kind||' hold')),
    p_mission_type, NULL, COALESCE(p_snapshot,'{}'::jsonb), p_is_sandbox);

  INSERT INTO public.mission_financial_holds
    (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
     amount_gnf, unrestricted_gnf, promo_gnf, hold_tx_id, policy_id,
     policy_snapshot, basis_value_gnf, is_sandbox, journal_key)
  VALUES (p_driver,'driver',p_driver,p_mission_type,p_source_module,p_source_id,p_kind,
     v_amount, v_u, v_p, v_tx.id, p_policy_id, COALESCE(p_snapshot,'{}'::jsonb),
     COALESCE(p_basis_value_gnf,0), p_is_sandbox, v_key);

  RETURN jsonb_build_object('status','held','amount_gnf',v_amount,
    'unrestricted_gnf',v_u,'promo_gnf',v_p,'frozen',true);
END; $function$;

REVOKE ALL ON FUNCTION public._driver_exact_hold_place_internal(text,text,uuid,uuid,bigint,text,jsonb,bigint,uuid,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._driver_exact_hold_place_internal(text,text,uuid,uuid,bigint,text,jsonb,bigint,uuid,boolean) TO service_role;

-- 2) Authorization persists the frozen collateral amount
CREATE OR REPLACE FUNCTION public._chop_pay_customer_hold_internal(p_source_module text, p_source_id uuid, p_actor uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_f jsonb; v_e jsonb; v_row public.chop_pay_order_runtime; v_key text;
  v_sub bigint; v_del bigint; v_fee bigint; v_total bigint; v_snap jsonb; v_col bigint;
  v_w public.wallets; v_avail bigint; v_tx public.wallet_transactions; v_customer uuid;
BEGIN
  IF NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  v_key := format('%s:%s', p_source_module, p_source_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('choppay:'||v_key, 0));

  SELECT * INTO v_row FROM public.chop_pay_order_runtime WHERE order_key = v_key FOR UPDATE;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_authorized','runtime_id',v_row.id,
                              'state',v_row.state,'order_total_gnf',v_row.order_total_gnf,
                              'collateral_gnf',v_row.collateral_gnf);
  END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT (v_f->>'is_chop_pay')::boolean THEN RAISE EXCEPTION 'CHOP_PAY_TENDER_REQUIRED'; END IF;
  IF (v_f->>'mixed_tender')::boolean THEN RAISE EXCEPTION 'MIXED_TENDER_NOT_SUPPORTED'; END IF;
  IF (v_f->>'merchant_store_id') IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_MISSING'; END IF;
  IF (v_f->>'mission_id') IS NULL THEN
    RAISE EXCEPTION 'CHOP_PAY_DELIVERY_NOT_READY'
      USING DETAIL = 'delivery mission must exist so the delivery fee is part of the hold';
  END IF;
  v_customer := (v_f->>'customer_user_id')::uuid;

  v_e := public._chop_pay_economics(v_f);
  v_sub := (v_e->>'merchandise_subtotal_gnf')::bigint;
  v_del := (v_e->>'delivery_fee_gnf')::bigint;
  v_fee := (v_e->>'platform_fee_gnf')::bigint;
  v_total := (v_e->>'order_total_gnf')::bigint;
  v_col := GREATEST(COALESCE((v_e->>'collateral_gnf')::bigint,0),0);
  v_snap := v_e->'policy_snapshot';
  IF v_sub <= 0 THEN RAISE EXCEPTION 'INVALID_MERCHANDISE_SUBTOTAL'; END IF;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_customer,'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_customer AND party_type = 'client' FOR UPDATE;
  IF v_w.status <> 'active' THEN RAISE EXCEPTION 'WALLET_NOT_ACTIVE'; END IF;
  v_avail := GREATEST(v_w.balance_gnf - v_w.held_gnf, 0);
  IF v_avail < v_total THEN
    RAISE EXCEPTION 'INSUFFICIENT_CHOP_PAY_BALANCE'
      USING DETAIL = format('required=%s available=%s', v_total, v_avail);
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
     related_entity, description, metadata)
  VALUES (format('cph:%s:%s:customer_payment', p_source_module, p_source_id),
     'hold','pending', v_total, v_w.id, v_customer,
     p_source_module || ':' || p_source_id::text,
     'Réservation Chop Pay (commande complète)',
     jsonb_build_object('mission_type', v_f->>'mission_type','kind','customer_payment',
                        'merchandise_gnf',v_sub,'delivery_gnf',v_del,'platform_fee_gnf',v_fee))
  RETURNING * INTO v_tx;

  UPDATE public.wallets SET held_gnf = held_gnf + v_total, updated_at = now() WHERE id = v_w.id;

  INSERT INTO public.mission_financial_holds
    (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
     amount_gnf, customer_gnf, hold_tx_id, policy_snapshot, basis_value_gnf, is_sandbox, journal_key)
  VALUES (NULL, 'client', v_customer, v_f->>'mission_type', p_source_module, p_source_id,
     'customer_payment', v_total, v_total, v_tx.id, v_snap, v_sub, false,
     format('cph:%s:%s:customer_payment', p_source_module, p_source_id));

  PERFORM public._ledger_post(
    format('cph:%s:%s:customer_payment', p_source_module, p_source_id),
    p_source_module, p_source_id, 'hold_customer_payment',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',v_total,
                         'party_type','client','party_user_id',v_customer,'memo','customer chop pay reserved'),
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',-v_total,
                         'party_type','client','party_user_id',v_customer,'memo','full order hold')),
    v_f->>'mission_type', p_actor, v_snap, false);

  INSERT INTO public.chop_pay_order_runtime
    (order_key, source_module, source_id, mission_type, mission_id, customer_user_id,
     merchant_store_id, merchant_user_id, merchandise_subtotal_gnf, delivery_fee_gnf,
     platform_fee_gnf, order_total_gnf, collateral_gnf, policy_snapshot, state)
  VALUES (v_key, p_source_module, p_source_id, v_f->>'mission_type',
          (v_f->>'mission_id')::uuid, v_customer,
          (v_f->>'merchant_store_id')::uuid, (v_f->>'merchant_user_id')::uuid,
          v_sub, v_del, v_fee, v_total, v_col, v_snap, 'authorized')
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('status','authorized','runtime_id',v_row.id,
    'merchandise_subtotal_gnf',v_sub,'delivery_fee_gnf',v_del,'platform_fee_gnf',v_fee,
    'order_total_gnf',v_total,'held_gnf',v_total,'collateral_gnf',v_col);
END; $function$;

-- 3) Accept uses the frozen amount, never live policy
CREATE OR REPLACE FUNCTION public._chop_pay_accept_internal(p_source_module text, p_source_id uuid, p_driver uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row public.chop_pay_order_runtime; v_f jsonb; v_hold jsonb; v_col bigint;
BEGIN
  IF p_driver IS NULL THEN RAISE EXCEPTION 'NO_DRIVER'; END IF;
  IF NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(format('choppay:%s:%s',p_source_module,p_source_id), 0));

  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'
      USING DETAIL = 'customer full-order hold must be secured before dispatch';
  END IF;
  IF v_row.driver_user_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_accepted','runtime_id',v_row.id,
                              'driver_user_id',v_row.driver_user_id,'state',v_row.state);
  END IF;
  IF v_row.state <> 'authorized' THEN RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state; END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT (v_f->>'is_chop_pay')::boolean THEN RAISE EXCEPTION 'CHOP_PAY_TENDER_REQUIRED'; END IF;
  IF (v_f->>'courier_id') IS NULL THEN RAISE EXCEPTION 'NO_ASSIGNED_COURIER'; END IF;
  IF p_driver <> (v_f->>'courier_id')::uuid THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;
  IF (v_f->>'mission_state') <> 'assigned' THEN RAISE EXCEPTION 'STALE_OFFER'; END IF;

  -- DEF-FIN-S5-001: collateral is the FROZEN amount persisted at authorization.
  v_hold := public._driver_exact_hold_place_internal(
    v_row.mission_type, p_source_module, p_source_id, p_driver,
    v_row.collateral_gnf, 'collateral', v_row.policy_snapshot,
    v_row.merchandise_subtotal_gnf, NULL, v_row.is_sandbox);

  SELECT COALESCE(SUM(amount_gnf),0) INTO v_col FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'collateral';

  PERFORM public._merchant_payable_create_internal(
    p_source_module, p_source_id, v_row.merchant_store_id,
    v_row.merchandise_subtotal_gnf, 0, v_row.mission_type, v_row.policy_snapshot, false);

  UPDATE public.chop_pay_order_runtime
     SET driver_user_id = p_driver, state = 'accepted', accepted_at = now(),
         mission_id = COALESCE(mission_id,(v_f->>'mission_id')::uuid)
   WHERE id = v_row.id;

  RETURN jsonb_build_object('status','accepted','runtime_id',v_row.id,
    'collateral_gnf',v_col,'frozen_collateral_gnf',v_row.collateral_gnf,
    'order_total_gnf',v_row.order_total_gnf,'hold',v_hold);
END; $function$;

-- 4) Freeze collateral_gnf once persisted
CREATE OR REPLACE FUNCTION public._chop_pay_runtime_immutable()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.merchandise_subtotal_gnf IS DISTINCT FROM OLD.merchandise_subtotal_gnf
     OR NEW.delivery_fee_gnf IS DISTINCT FROM OLD.delivery_fee_gnf
     OR NEW.platform_fee_gnf IS DISTINCT FROM OLD.platform_fee_gnf
     OR NEW.order_total_gnf IS DISTINCT FROM OLD.order_total_gnf
     OR NEW.policy_snapshot IS DISTINCT FROM OLD.policy_snapshot
     OR NEW.customer_user_id IS DISTINCT FROM OLD.customer_user_id
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.source_module IS DISTINCT FROM OLD.source_module
     OR NEW.source_id IS DISTINCT FROM OLD.source_id
     OR NEW.collateral_gnf IS DISTINCT FROM OLD.collateral_gnf
     OR (OLD.driver_user_id IS NOT NULL AND NEW.driver_user_id IS DISTINCT FROM OLD.driver_user_id)
  THEN
    RAISE EXCEPTION 'CHOP_PAY_SNAPSHOT_IMMUTABLE';
  END IF;
  RETURN NEW;
END; $function$;