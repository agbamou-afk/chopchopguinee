-- ============================================================
-- SLICE 6 — Envoyer lifecycle wiring + participant/admin RPCs
-- ============================================================

-- Exact (frozen) hold primitive must also serve the cash platform-fee reserve.
CREATE OR REPLACE FUNCTION public._driver_exact_hold_place_internal(
  p_mission_type text, p_source_module text, p_source_id uuid, p_driver uuid, p_amount bigint,
  p_kind text DEFAULT 'collateral'::text, p_snapshot jsonb DEFAULT '{}'::jsonb,
  p_basis_value_gnf bigint DEFAULT 0, p_policy_id uuid DEFAULT NULL::uuid,
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_wallet public.wallets; v_avail bigint; v_alloc jsonb; v_u bigint; v_p bigint;
  v_tx public.wallet_transactions; v_key text; v_amount bigint := COALESCE(p_amount,0);
BEGIN
  IF p_kind NOT IN ('collateral','platform_fee') THEN
    RAISE EXCEPTION 'EXACT_HOLD_KIND_NOT_ALLOWED' USING DETAIL = p_kind;
  END IF;
  IF p_driver IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;
  IF v_amount < 0 THEN RAISE EXCEPTION 'INVALID_HOLD_AMOUNT'; END IF;
  IF NOT public._driver_finance_eligible(p_driver) THEN RAISE EXCEPTION 'ACCOUNT_RESTRICTED'; END IF;

  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE source_module = p_source_module AND source_id = p_source_id AND kind = p_kind) THEN
    RETURN jsonb_build_object('status','already_held','amount_gnf',v_amount);
  END IF;
  IF v_amount = 0 THEN RETURN jsonb_build_object('status','zero','amount_gnf',0); END IF;

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
     p_source_module || ':' || p_source_id::text,
     CASE WHEN p_kind = 'collateral' THEN 'Caution mission' ELSE 'Réserve frais de transaction' END,
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

-- ---------- participant: register a private shipment photo ----------
CREATE OR REPLACE FUNCTION public.package_evidence_register(
  p_quote_id uuid, p_storage_path text, p_kind text DEFAULT 'item',
  p_content_type text DEFAULT NULL, p_byte_size integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_q public.package_delivery_quotes; v_row public.package_evidence_photos;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_q FROM public.package_delivery_quotes WHERE id = p_quote_id;
  IF v_q.id IS NULL THEN RAISE EXCEPTION 'quote_not_found' USING ERRCODE='22023'; END IF;
  IF v_q.user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF p_storage_path IS NULL OR p_storage_path <> format('%s/%s/%s', v_uid, p_quote_id,
       regexp_replace(p_storage_path, '^.*/', '')) THEN
    RAISE EXCEPTION 'invalid_storage_path' USING ERRCODE='22023';
  END IF;
  IF COALESCE(p_kind,'item') NOT IN ('item','packaging','label','condition') THEN
    RAISE EXCEPTION 'invalid_kind' USING ERRCODE='22023';
  END IF;

  INSERT INTO public.package_evidence_photos
    (quote_id, owner_user_id, storage_path, kind, content_type, byte_size)
  VALUES (p_quote_id, v_uid, p_storage_path, COALESCE(p_kind,'item'), p_content_type, p_byte_size)
  ON CONFLICT (storage_path) DO NOTHING
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('ok', true, 'photo_id', v_row.id, 'idempotent', v_row.id IS NULL,
    'count', (SELECT count(*) FROM public.package_evidence_photos WHERE quote_id = p_quote_id));
END; $$;

REVOKE ALL ON FUNCTION public.package_evidence_register(uuid,text,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_evidence_register(uuid,text,text,text,integer) TO authenticated, service_role;

-- ---------- checkout: declared value + tender + attestation ----------
CREATE OR REPLACE FUNCTION public.package_delivery_create_checkout(
  p_quote_id uuid, p_recipient_name text, p_recipient_phone text,
  p_description text DEFAULT NULL::text, p_instructions text DEFAULT NULL::text,
  p_idempotency_key text DEFAULT NULL::text, p_sender_phone text DEFAULT NULL::text,
  p_provider text DEFAULT 'orange_money'::text, p_sandbox boolean DEFAULT false,
  p_test_run_id uuid DEFAULT NULL::uuid,
  p_declared_value_gnf bigint DEFAULT NULL::bigint, p_tender text DEFAULT NULL::text,
  p_value_attested boolean DEFAULT false, p_attestation_statement text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_q public.package_delivery_quotes;
  v_pkg public.package_deliveries;
  v_intent public.payment_intents;
  v_profile record;
  v_recipient text; v_sender_phone text; v_key text; v_ref text; v_env text;
  v_declared_engine boolean; v_photos int; v_auth jsonb; v_probe jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public._envoyer_enabled() THEN RAISE EXCEPTION 'envoyer_disabled' USING ERRCODE='22023'; END IF;
  IF p_sandbox THEN PERFORM public._om_sandbox_require_active(); END IF;

  v_declared_engine := public._finance_flag('envoyer_declared_value_enabled');
  v_key := COALESCE(NULLIF(trim(p_idempotency_key), ''), p_quote_id::text);

  SELECT * INTO v_pkg FROM public.package_deliveries
   WHERE sender_user_id = v_uid AND idempotency_key = v_key;
  IF v_pkg.id IS NOT NULL THEN
    SELECT * INTO v_intent FROM public.payment_intents WHERE id = v_pkg.payment_intent_id;
    RETURN jsonb_build_object(
      'idempotent', true, 'package_id', v_pkg.id, 'reference', v_pkg.reference,
      'payment_intent_id', v_pkg.payment_intent_id, 'amount_gnf', v_pkg.quoted_amount_gnf,
      'intent_state', v_intent.state, 'provider_reference', v_intent.provider_reference,
      'declared_value_gnf', v_pkg.declared_value_gnf, 'tender', v_pkg.tender,
      'is_sandbox', v_pkg.is_sandbox);
  END IF;

  SELECT * INTO v_q FROM public.package_delivery_quotes WHERE id = p_quote_id FOR UPDATE;
  IF v_q.id IS NULL THEN RAISE EXCEPTION 'quote_not_found' USING ERRCODE='22023'; END IF;
  IF v_q.user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_q.expires_at <= now() THEN RAISE EXCEPTION 'quote_expired' USING ERRCODE='22023'; END IF;
  IF v_q.consumed_at IS NOT NULL THEN RAISE EXCEPTION 'quote_already_used' USING ERRCODE='22023'; END IF;

  v_recipient := public._normalize_guinea_phone(p_recipient_phone);
  IF v_recipient IS NULL THEN RAISE EXCEPTION 'invalid_recipient_phone' USING ERRCODE='22023'; END IF;
  IF p_recipient_name IS NULL OR length(trim(p_recipient_name)) < 2 THEN
    RAISE EXCEPTION 'invalid_recipient_name' USING ERRCODE='22023';
  END IF;

  -- Declared-value gate: refuse BEFORE any shipment, mission, hold or journal exists.
  IF v_declared_engine THEN
    IF p_tender IS NULL OR p_tender NOT IN ('cash','chop_pay') THEN
      RAISE EXCEPTION 'ENVOYER_TENDER_REQUIRED' USING ERRCODE='22023';
    END IF;
    IF p_declared_value_gnf IS NULL OR p_declared_value_gnf <= 0 THEN
      RAISE EXCEPTION 'DECLARED_VALUE_REQUIRED' USING ERRCODE='22023';
    END IF;
    IF COALESCE(p_value_attested,false) IS NOT TRUE
       OR p_attestation_statement IS NULL OR length(btrim(p_attestation_statement)) < 10 THEN
      RAISE EXCEPTION 'VALUE_ATTESTATION_REQUIRED' USING ERRCODE='22023';
    END IF;
    SELECT count(*) INTO v_photos FROM public.package_evidence_photos
     WHERE quote_id = v_q.id AND owner_user_id = v_uid;
    IF v_photos < 1 THEN RAISE EXCEPTION 'SHIPMENT_PHOTOS_REQUIRED' USING ERRCODE='22023'; END IF;
    -- ceiling / policy check up-front (raises DECLARED_VALUE_ABOVE_CEILING)
    v_probe := public._package_economics(p_declared_value_gnf, v_q.amount_gnf, p_tender, p_sandbox);
  END IF;

  SELECT full_name, phone INTO v_profile FROM public.profiles WHERE id = v_uid;
  v_sender_phone := COALESCE(public._normalize_guinea_phone(p_sender_phone),
                             public._normalize_guinea_phone(v_profile.phone));
  v_env := CASE WHEN p_sandbox THEN 'sandbox' ELSE 'production' END;
  v_ref := 'PKG-' || upper(substr(replace(gen_random_uuid()::text,'-',''), 1, 8));

  INSERT INTO public.package_deliveries(
    sender_user_id, quote_id, reference,
    pickup_label, pickup_lat, pickup_lng,
    destination_label, destination_lat, destination_lng,
    sender_name, sender_phone, recipient_name, recipient_phone,
    category, description, handling_notes,
    quoted_amount_gnf, distance_meters, duration_seconds,
    payment_status, package_status, idempotency_key,
    is_sandbox, environment, test_run_id,
    declared_value_gnf, tender, value_attested_at, value_attested_by,
    value_attestation_statement, value_attestation_version
  ) VALUES (
    v_uid, v_q.id, v_ref,
    v_q.pickup_label, v_q.pickup_lat, v_q.pickup_lng,
    v_q.destination_label, v_q.destination_lat, v_q.destination_lng,
    v_profile.full_name, v_sender_phone, left(trim(p_recipient_name), 120), v_recipient,
    v_q.category, left(coalesce(p_description,''), 500), left(coalesce(p_instructions,''), 500),
    v_q.amount_gnf, v_q.distance_meters, v_q.duration_seconds,
    'pending', 'payment_pending', v_key,
    p_sandbox, v_env, p_test_run_id,
    CASE WHEN v_declared_engine THEN p_declared_value_gnf ELSE 0 END,
    CASE WHEN v_declared_engine THEN p_tender ELSE NULL END,
    CASE WHEN v_declared_engine THEN now() ELSE NULL END,
    CASE WHEN v_declared_engine THEN v_uid ELSE NULL END,
    CASE WHEN v_declared_engine THEN left(btrim(p_attestation_statement), 500) ELSE NULL END,
    CASE WHEN v_declared_engine THEN 'envoyer.value_attestation.v1' ELSE NULL END
  ) RETURNING * INTO v_pkg;

  UPDATE public.package_delivery_quotes SET consumed_at = now() WHERE id = v_q.id;

  IF v_declared_engine THEN
    UPDATE public.package_evidence_photos SET package_id = v_pkg.id
     WHERE quote_id = v_q.id AND owner_user_id = v_uid AND package_id IS NULL;

    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'package', 'package.value.attested', 'package_delivery', v_pkg.id::text,
            jsonb_build_object('declared_value_gnf', p_declared_value_gnf,
                               'attested_at', v_pkg.value_attested_at,
                               'attestation_version', v_pkg.value_attestation_version,
                               'statement', v_pkg.value_attestation_statement));

    v_auth := public._package_authorize_internal(v_pkg.id, v_uid);

    RETURN jsonb_build_object(
      'idempotent', false, 'package_id', v_pkg.id, 'reference', v_pkg.reference,
      'amount_gnf', v_pkg.quoted_amount_gnf, 'tender', v_pkg.tender,
      'declared_value_gnf', v_pkg.declared_value_gnf,
      'authorization', v_auth, 'is_sandbox', p_sandbox);
  END IF;

  -- Legacy Orange Money intent path (declared-value engine OFF)
  INSERT INTO public.payment_intents(
    user_id, amount_gnf, currency, purpose, state, provider,
    internal_reference, source_module, source_id, description,
    metadata, is_sandbox, environment, test_run_id, expires_at
  ) VALUES (
    v_uid, v_q.amount_gnf, 'GNF', 'package_payment'::public.payment_purpose, 'pending',
    (CASE WHEN p_provider IN ('orange_money','mtn_money','cash','manual','internal','agent')
          THEN p_provider ELSE 'orange_money' END)::public.payment_provider,
    'pkg:' || v_pkg.id::text, 'package', v_pkg.id, 'Envoyer — livraison de colis ' || v_pkg.reference,
    jsonb_build_object('module','package','package_reference', v_pkg.reference,
      'quote_id', v_q.id, 'authoritative_amount_gnf', v_q.amount_gnf,
      'sandbox', p_sandbox, 'sandbox_module', CASE WHEN p_sandbox THEN 'package' ELSE NULL END),
    p_sandbox, v_env, p_test_run_id, now() + interval '30 minutes'
  ) RETURNING * INTO v_intent;

  UPDATE public.package_deliveries SET payment_intent_id = v_intent.id WHERE id = v_pkg.id;

  INSERT INTO public.payment_reconciliation_events
    (intent_id, event_type, provider, payload, actor_user_id, is_sandbox, environment, test_run_id)
  VALUES (v_intent.id, 'intent_created', v_intent.provider,
          jsonb_build_object('module','package','package_id', v_pkg.id, 'reference', v_pkg.reference),
          v_uid, p_sandbox, v_env, p_test_run_id);

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.checkout.created', 'package_delivery', v_pkg.id::text,
          jsonb_build_object('intent_id', v_intent.id, 'amount_gnf', v_q.amount_gnf, 'sandbox', p_sandbox));

  RETURN jsonb_build_object(
    'idempotent', false, 'package_id', v_pkg.id, 'reference', v_pkg.reference,
    'payment_intent_id', v_intent.id, 'amount_gnf', v_intent.amount_gnf,
    'intent_state', v_intent.state, 'provider', v_intent.provider, 'is_sandbox', p_sandbox);
END;
$function$;

REVOKE ALL ON FUNCTION public.package_delivery_create_checkout(uuid,text,text,text,text,text,text,text,boolean,uuid,bigint,text,boolean,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_delivery_create_checkout(uuid,text,text,text,text,text,text,text,boolean,uuid,bigint,text,boolean,text) TO authenticated, service_role;

-- ---------- mission_claim: package collateral at acceptance ----------
CREATE OR REPLACE FUNCTION public.mission_claim(_mission_id uuid)
RETURNS missions
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid(); _m public.missions; _cs jsonb; _tender text; _pkg uuid;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS NOT NULL THEN RAISE EXCEPTION 'mission_already_claimed'; END IF;
  IF NOT public.driver_has_capability(_uid, public.mission_required_capability(_m.type)) THEN
    RAISE EXCEPTION 'capability_missing';
  END IF;

  IF _m.type = 'marketplace_delivery' AND _m.ref_market_order_id IS NOT NULL THEN
    SELECT mo.metadata->>'payment_method' INTO _tender
      FROM public.marketplace_offers mo WHERE mo.id = _m.ref_market_order_id;
    IF _tender IS NULL OR _tender NOT IN ('cash','choppay') THEN
      RAISE EXCEPTION 'MARCHE_TENDER_REQUIRED'
        USING DETAIL = 'explicit payment method required before courier assignment';
    END IF;
  END IF;

  UPDATE public.missions SET courier_id = _uid WHERE id = _mission_id RETURNING * INTO _m;

  IF _m.type = 'package_delivery' THEN
    SELECT package_id INTO _pkg FROM public.package_runtime WHERE mission_id = _mission_id;
    IF _pkg IS NOT NULL THEN
      PERFORM public._package_accept_internal(_pkg, _uid);
    END IF;
  END IF;

  _cs := public._mission_cash_source(_m);
  IF _cs IS NOT NULL THEN
    IF public._cash_order_is_cash(_cs->>'module', (_cs->>'source_id')::uuid) THEN
      PERFORM public._cash_order_accept_internal(_cs->>'module', (_cs->>'source_id')::uuid, _uid);
    ELSIF public._chop_pay_is_chop_pay(_cs->>'module', (_cs->>'source_id')::uuid) THEN
      PERFORM public._chop_pay_accept_internal(_cs->>'module', (_cs->>'source_id')::uuid, _uid);
    END IF;
  END IF;

  UPDATE public.missions SET state = 'heading_to_pickup' WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END; $function$;

-- ---------- pickup: custody boundary ----------
CREATE OR REPLACE FUNCTION public.package_verify_pickup(p_package_id uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_pkg public.package_deliveries; v_m public.missions;
  v_s public.package_delivery_secrets; v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id FOR UPDATE;
  IF v_s.package_id IS NULL THEN RAISE EXCEPTION 'secrets_missing'; END IF;

  IF v_s.pickup_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'mission_state', v_m.state);
  END IF;
  IF v_s.pickup_attempts >= 6 THEN
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'too_many_attempts',
                              'attempts', v_s.pickup_attempts, 'attempts_left', 0,
                              'mission_state', v_m.state);
  END IF;
  IF v_m.state NOT IN ('assigned','heading_to_pickup','arrived_pickup') THEN
    RAISE EXCEPTION 'invalid_state' USING ERRCODE='22023';
  END IF;

  v_code := regexp_replace(COALESCE(p_code,''), '\D', '', 'g');
  IF v_code <> v_s.pickup_code THEN
    UPDATE public.package_delivery_secrets SET pickup_attempts = pickup_attempts + 1
     WHERE package_id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'package', 'package.pickup.code_failed', 'package_delivery', p_package_id::text,
            jsonb_build_object('attempts', v_s.pickup_attempts + 1));
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'invalid_code',
                              'attempts', v_s.pickup_attempts + 1,
                              'attempts_left', GREATEST(6 - (v_s.pickup_attempts + 1), 0),
                              'mission_state', v_m.state);
  END IF;

  UPDATE public.package_delivery_secrets
     SET pickup_verified_at = now(), pickup_attempts = pickup_attempts + 1
   WHERE package_id = p_package_id;

  UPDATE public.missions
     SET state = 'picked_up'::public.mission_state,
         pickup_confirmed_at = now(), pickup_confirmed_by = v_uid
   WHERE id = v_m.id;

  UPDATE public.package_deliveries SET package_status = 'in_transit' WHERE id = p_package_id;

  UPDATE public.package_runtime
     SET state = 'picked_up', picked_up_at = now()
   WHERE package_id = p_package_id AND state = 'accepted';

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (v_m.id, 'picked_up', v_uid, 'package_code_verified');

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.pickup.verified', 'package_delivery', p_package_id::text,
          jsonb_build_object('mission_id', v_m.id));

  PERFORM public._package_notify(
    v_pkg.sender_user_id, 'package_picked_up',
    jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                       'mission_id', v_m.id, 'sandbox', v_pkg.is_sandbox), 'high');

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'mission_state', 'picked_up',
                            'custody_established', true);
END; $function$;

-- ---------- delivery: settle through the engine ----------
CREATE OR REPLACE FUNCTION public.package_verify_delivery(
  p_package_id uuid, p_code text, p_recipient_name text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_pkg public.package_deliveries; v_m public.missions;
  v_s public.package_delivery_secrets; v_code text; v_rt public.package_runtime; v_settle jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id FOR UPDATE;
  IF v_s.package_id IS NULL THEN RAISE EXCEPTION 'secrets_missing'; END IF;
  IF v_s.delivery_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'mission_state', v_m.state);
  END IF;
  IF v_s.pickup_verified_at IS NULL THEN RAISE EXCEPTION 'pickup_not_verified' USING ERRCODE='22023'; END IF;
  IF v_s.delivery_attempts >= 6 THEN
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'too_many_attempts',
                              'attempts', v_s.delivery_attempts, 'attempts_left', 0,
                              'mission_state', v_m.state);
  END IF;
  IF v_m.state NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff') THEN
    RAISE EXCEPTION 'invalid_state' USING ERRCODE='22023';
  END IF;

  v_code := regexp_replace(COALESCE(p_code,''), '\D', '', 'g');
  IF v_code <> v_s.delivery_code THEN
    UPDATE public.package_delivery_secrets SET delivery_attempts = delivery_attempts + 1
     WHERE package_id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'package', 'package.delivery.code_failed', 'package_delivery', p_package_id::text,
            jsonb_build_object('attempts', v_s.delivery_attempts + 1));
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'invalid_code',
                              'attempts', v_s.delivery_attempts + 1,
                              'attempts_left', GREATEST(6 - (v_s.delivery_attempts + 1), 0),
                              'mission_state', v_m.state);
  END IF;

  SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_package_id;
  IF v_rt.id IS NOT NULL AND v_rt.claim_state <> 'none' THEN
    RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM' USING ERRCODE='22023';
  END IF;

  UPDATE public.package_delivery_secrets
     SET delivery_verified_at = now(), delivery_attempts = delivery_attempts + 1
   WHERE package_id = p_package_id;

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(), dropoff_confirmed_by = v_uid
   WHERE id = v_m.id;

  UPDATE public.package_deliveries
     SET package_status = 'delivered', delivered_at = now(),
         recipient_confirmed_name = COALESCE(left(trim(p_recipient_name),120), recipient_name),
         payment_status = CASE WHEN is_sandbox THEN payment_status ELSE 'settled' END
   WHERE id = p_package_id;

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (v_m.id, 'delivered', v_uid, 'package_code_verified');

  IF v_rt.id IS NOT NULL THEN
    -- Declared-value runtime owns settlement (cash never creates a digital earning).
    v_settle := public._package_complete_internal(p_package_id, v_uid);
  ELSIF NOT v_pkg.is_sandbox THEN
    BEGIN
      PERFORM public.wallet_credit_mission_earning(v_m.id, 'package_verify_delivery');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.mission_events(mission_id, event, actor_id, note)
      VALUES (v_m.id, 'issue', v_uid, 'courier_earning_failed: ' || SQLERRM);
    END;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.delivery.verified', 'package_delivery', p_package_id::text,
          jsonb_build_object('mission_id', v_m.id, 'sandbox', v_pkg.is_sandbox, 'settlement', v_settle));

  PERFORM public._package_notify(
    v_pkg.sender_user_id, 'package_delivered',
    jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                       'mission_id', v_m.id, 'sandbox', v_pkg.is_sandbox), 'high');

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'mission_state', 'delivered',
                            'settlement', v_settle);
END; $function$;

-- ---------- sender: open a claim after custody ----------
CREATE OR REPLACE FUNCTION public.package_claim_open(
  p_package_id uuid, p_reason text, p_evidence_ref text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid(); v_pkg public.package_deliveries;
  v_rt public.package_runtime; v_s public.package_delivery_secrets; v_issue uuid; v_freeze jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public._finance_flag('envoyer_claims_enabled') THEN
    RAISE EXCEPTION 'ENVOYER_CLAIMS_DISABLED' USING ERRCODE='22023';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'CLAIM_REASON_REQUIRED' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF v_pkg.sender_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_package_id;
  IF v_rt.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id;
  IF v_s.pickup_verified_at IS NULL THEN
    RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED' USING ERRCODE='22023';
  END IF;

  v_freeze := public._package_claim_freeze_internal(p_package_id, btrim(p_reason), v_uid);

  IF v_pkg.support_issue_id IS NULL THEN
    INSERT INTO public.support_issues(
      issue_type, severity, title, description, reporter_user_id,
      related_mission_id, related_customer_id, metadata)
    VALUES ('package_dispute','high',
      'Réclamation colis ' || v_pkg.reference, btrim(p_reason), v_uid,
      v_pkg.mission_id, v_uid,
      jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                         'declared_value_gnf', v_rt.declared_value_gnf,
                         'collateral_gnf', v_rt.collateral_gnf,
                         'claims_exposure_gnf', v_rt.claims_exposure_gnf,
                         'evidence_ref', p_evidence_ref, 'sandbox', v_pkg.is_sandbox))
    RETURNING id INTO v_issue;
    UPDATE public.package_deliveries SET support_issue_id = v_issue WHERE id = p_package_id;
  ELSE
    v_issue := v_pkg.support_issue_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'claim_state','open', 'support_issue_id', v_issue,
    'declared_value_gnf', v_rt.declared_value_gnf, 'collateral_gnf', v_rt.collateral_gnf,
    'claims_exposure_gnf', v_rt.claims_exposure_gnf, 'freeze', v_freeze);
END; $$;

REVOKE ALL ON FUNCTION public.package_claim_open(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_claim_open(uuid,text,text) TO authenticated, service_role;

-- ---------- cancellation: custody boundary ----------
CREATE OR REPLACE FUNCTION public.package_delivery_cancel(
  p_package_id uuid, p_reason text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_pkg public.package_deliveries; v_m public.missions;
  v_s public.package_delivery_secrets; v_rt public.package_runtime;
  v_fee bigint := 0; v_refund bigint; v_req uuid; v_issue uuid; v_rel jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF v_pkg.sender_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_pkg.cancelled_at IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'status', v_pkg.package_status,
      'refund_request_id', v_pkg.refund_request_id, 'fee_gnf', v_pkg.cancellation_fee_gnf);
  END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id;
  SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_package_id;

  IF v_rt.id IS NOT NULL AND v_rt.claim_state <> 'none' THEN
    RAISE EXCEPTION 'SETTLEMENT_FROZEN_BY_CLAIM' USING ERRCODE='22023';
  END IF;

  -- Custody established: no ordinary cancellation shortcut, claim path required.
  IF v_s.pickup_verified_at IS NOT NULL OR v_pkg.package_status IN ('in_transit','delivered') THEN
    IF v_pkg.support_issue_id IS NULL THEN
      INSERT INTO public.support_issues(
        issue_type, severity, title, description, reporter_user_id,
        related_mission_id, related_payment_intent_id, related_customer_id, metadata)
      VALUES ('package_dispute','high',
        'Colis déjà récupéré — demande d''annulation ' || v_pkg.reference,
        COALESCE(p_reason, 'Annulation demandée après récupération du colis.'), v_uid,
        v_pkg.mission_id, v_pkg.payment_intent_id, v_uid,
        jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                           'sandbox', v_pkg.is_sandbox))
      RETURNING id INTO v_issue;
      UPDATE public.package_deliveries SET support_issue_id = v_issue WHERE id = p_package_id;
    ELSE
      v_issue := v_pkg.support_issue_id;
    END IF;

    RETURN jsonb_build_object('idempotent', false, 'self_service', false,
      'error', 'CUSTODY_ESTABLISHED_CLAIM_REQUIRED', 'claim_required', true,
      'support_issue_id', v_issue, 'status', v_pkg.package_status);
  END IF;

  IF v_rt.id IS NOT NULL THEN
    -- Declared-value runtime: release collateral / customer hold, no cancellation
    -- fee (envoyer cancel_basis is 'none' in the frozen policy snapshot).
    v_rel := public._package_cancel_release_internal(p_package_id,
               COALESCE(p_reason,'client_cancelled'), v_uid);
    v_fee := 0;
  ELSIF v_m.id IS NOT NULL AND v_m.courier_id IS NOT NULL THEN
    v_fee := floor(v_pkg.quoted_amount_gnf * 0.10)::bigint;
  END IF;
  v_refund := v_pkg.quoted_amount_gnf - v_fee;

  IF v_m.id IS NOT NULL THEN
    UPDATE public.missions SET state = 'failed'::public.mission_state,
           issue_reason = COALESCE(p_reason, 'client_cancelled') WHERE id = v_m.id;
  END IF;

  UPDATE public.package_deliveries
     SET package_status = 'cancelled', cancelled_at = now(),
         cancellation_reason = left(COALESCE(p_reason,'client_cancelled'), 300),
         cancellation_fee_gnf = v_fee
   WHERE id = p_package_id;

  IF v_pkg.payment_intent_id IS NOT NULL
     AND v_pkg.payment_status IN ('authorized','settled')
     AND v_refund > 0 AND v_rt.id IS NULL THEN
    INSERT INTO public.payment_refund_requests(
      payment_intent_id, user_id, source_module, source_id,
      original_amount_gnf, fee_gnf, amount_gnf, reason,
      is_sandbox, environment, test_run_id, metadata)
    VALUES (v_pkg.payment_intent_id, v_uid, 'package', v_pkg.id,
      v_pkg.quoted_amount_gnf, v_fee, v_refund,
      COALESCE(p_reason, 'client_cancelled'), v_pkg.is_sandbox, v_pkg.environment, v_pkg.test_run_id,
      jsonb_build_object('package_reference', v_pkg.reference))
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_req;
    IF v_req IS NOT NULL THEN
      UPDATE public.package_deliveries SET refund_request_id = v_req WHERE id = p_package_id;
    END IF;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.cancelled', 'package_delivery', p_package_id::text,
          jsonb_build_object('fee_gnf', v_fee, 'refund_request_id', v_req, 'release', v_rel));

  RETURN jsonb_build_object('idempotent', false, 'self_service', true,
    'fee_gnf', v_fee, 'refund_gnf', CASE WHEN v_rt.id IS NULL THEN v_refund ELSE 0 END,
    'release', v_rel, 'refund_request_id', v_req);
END; $function$;

-- ---------- God Admin: investigated claim resolution ----------
CREATE OR REPLACE FUNCTION public.admin_package_claim_resolve(
  p_package_id uuid, p_outcome text, p_reason text, p_evidence_ref text,
  p_pay_customer_gnf bigint DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid(); v_rt public.package_runtime; v_pkg public.package_deliveries;
  v_pay bigint; v_from_driver bigint; v_from_platform bigint;
  v_cap jsonb; v_alloc jsonb; v_res jsonb; v_rel jsonb; v_cust jsonb; v_settle jsonb;
  v_open_col bigint; v_master public.wallets; v_cw public.wallets;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501',
      DETAIL = 'Only a God Admin can resolve an Envoyer claim';
  END IF;
  IF p_outcome NOT IN ('customer_upheld','driver_exonerated','reconciliation_required') THEN
    RAISE EXCEPTION 'INVALID_OUTCOME';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF p_evidence_ref IS NULL OR length(btrim(p_evidence_ref)) < 4 THEN RAISE EXCEPTION 'CLAIM_EVIDENCE_REQUIRED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('package:'||p_package_id::text, 0));
  SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = p_package_id FOR UPDATE;
  IF v_rt.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_NOT_AUTHORIZED'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_rt.claim_state <> 'open' THEN
    RETURN jsonb_build_object('status','already_resolved','claim_state',v_rt.claim_state);
  END IF;

  IF p_outcome = 'reconciliation_required' THEN
    UPDATE public.package_runtime
       SET claim_state = 'reconciliation_required', state = 'reconciliation_required',
           resolved_at = now()
     WHERE id = v_rt.id;
    UPDATE public.package_deliveries SET claim_state = 'reconciliation_required' WHERE id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_caller,'package','package.claim.reconciliation_required','package_delivery',
            p_package_id::text, jsonb_build_object('evidence_ref',p_evidence_ref), p_reason);
    RETURN jsonb_build_object('status','reconciliation_required','money_moved',false);
  END IF;

  IF p_outcome = 'customer_upheld' THEN
    v_pay := GREATEST(COALESCE(p_pay_customer_gnf,0),0);
    IF v_pay <= 0 THEN RAISE EXCEPTION 'CLAIM_PAYMENT_REQUIRED'; END IF;
    IF v_pay > v_rt.declared_value_gnf THEN RAISE EXCEPTION 'CLAIM_EXCEEDS_DECLARED_VALUE'; END IF;

    SELECT GREATEST(amount_gnf - captured_gnf - released_gnf, 0) INTO v_open_col
      FROM public.mission_financial_holds
     WHERE source_module = 'package' AND source_id = p_package_id AND kind = 'collateral';
    v_open_col := COALESCE(v_open_col, 0);

    v_from_driver := LEAST(v_pay, v_open_col);
    v_from_platform := v_pay - v_from_driver;
    IF v_from_platform > v_rt.claims_exposure_gnf THEN
      RAISE EXCEPTION 'CLAIM_EXCEEDS_PLATFORM_EXPOSURE'
        USING DETAIL = format('exposure=%s requested=%s', v_rt.claims_exposure_gnf, v_from_platform);
    END IF;

    -- Platform residual runs through the canonical claims-reserve primitives while
    -- the collateral hold is still frozen (allocate requires a frozen hold).
    IF v_from_platform > 0 THEN
      v_alloc := public.claims_reserve_allocate(
        'package', p_package_id, 'envoyer', v_rt.customer_user_id, v_rt.driver_user_id,
        v_rt.declared_value_gnf, v_from_platform, p_evidence_ref, btrim(p_reason), v_rt.is_sandbox);
      SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
      IF v_master.id IS NULL THEN RAISE EXCEPTION 'MASTER_WALLET_MISSING'; END IF;
      UPDATE public.wallets SET balance_gnf = balance_gnf - v_from_platform, updated_at = now()
       WHERE id = v_master.id;
      v_res := public.claims_reserve_resolve(
        (SELECT id FROM public.claims_reserves WHERE source_module='package' AND source_id=p_package_id),
        v_from_platform, btrim(p_reason));
    END IF;

    IF v_from_driver > 0 THEN
      v_cap := public._package_collateral_capture_internal(
        p_package_id, v_from_driver, btrim(p_reason), p_evidence_ref, v_caller);
    END IF;

    -- Remaining collateral goes back to its original funding buckets.
    v_rel := public._driver_mission_hold_release_internal(
      'package', p_package_id, NULL, 'envoyer_claim_upheld', v_caller);

    -- Upheld claim: the sender is not charged for the delivery.
    UPDATE public.mission_financial_holds SET state = 'held'
     WHERE source_module='package' AND source_id=p_package_id AND kind='customer_payment' AND state='frozen';
    IF v_rt.tender = 'chop_pay' THEN
      v_cust := public._package_choppay_release_internal(p_package_id, 'envoyer_claim_upheld', v_caller);
    END IF;

    UPDATE public.package_runtime
       SET claim_state = 'upheld', state = 'resolved', resolved_at = now(),
           claim_paid_gnf = v_pay
     WHERE id = v_rt.id;
    UPDATE public.package_deliveries SET claim_state = 'resolved' WHERE id = p_package_id;

    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_caller,'package','package.claim.customer_upheld','package_delivery', p_package_id::text,
            jsonb_build_object('paid_gnf',v_pay,'from_collateral_gnf',v_from_driver,
                               'from_platform_gnf',v_from_platform,'evidence_ref',p_evidence_ref), p_reason);

    RETURN jsonb_build_object('status','customer_upheld','paid_gnf',v_pay,
      'from_collateral_gnf',v_from_driver,'from_platform_gnf',v_from_platform,
      'collateral_release',v_rel,'customer_release',v_cust,'capture',v_cap,
      'reserve_allocate',v_alloc,'reserve_resolve',v_res);
  END IF;

  -- driver_exonerated
  UPDATE public.mission_financial_holds SET state = 'held'
   WHERE source_module='package' AND source_id=p_package_id
     AND state='frozen' AND captured_gnf = 0;
  UPDATE public.mission_financial_holds SET state = 'partially_captured'
   WHERE source_module='package' AND source_id=p_package_id
     AND state='frozen' AND captured_gnf > 0;

  IF v_pkg.package_status = 'delivered' THEN
    UPDATE public.package_runtime SET claim_state = 'none', state = 'picked_up' WHERE id = v_rt.id;
    v_settle := public._package_complete_internal(p_package_id, v_caller);
  ELSE
    UPDATE public.package_runtime SET claim_state = 'none', state = 'accepted' WHERE id = v_rt.id;
    v_settle := public._package_cancel_release_internal(p_package_id, 'envoyer_claim_denied', v_caller);
  END IF;

  UPDATE public.package_runtime
     SET claim_state = 'denied', resolved_at = now() WHERE id = v_rt.id;
  UPDATE public.package_deliveries SET claim_state = 'resolved' WHERE id = p_package_id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'package','package.claim.driver_exonerated','package_delivery', p_package_id::text,
          jsonb_build_object('evidence_ref',p_evidence_ref,'settlement',v_settle), p_reason);

  RETURN jsonb_build_object('status','driver_exonerated','paid_gnf',0,'settlement',v_settle);
END; $$;

REVOKE ALL ON FUNCTION public.admin_package_claim_resolve(uuid,text,text,text,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_package_claim_resolve(uuid,text,text,text,bigint) TO authenticated, service_role;