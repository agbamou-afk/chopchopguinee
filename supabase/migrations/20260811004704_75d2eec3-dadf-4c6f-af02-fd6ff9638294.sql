-- ============================================================
-- SLICE 6 CLOSEOUT — DEF-FIN-S6-001 + QA parts 3/4/5
-- ============================================================

-- DEF-FIN-S6-001: the driver hold-release primitive also matched the customer
-- Chop Pay reservation (driver_user_id IS NULL). It marked that hold released
-- without decrementing the customer wallet, so the dedicated Chop Pay release
-- then returned 'already_resolved' and the customer's money stayed held.
CREATE OR REPLACE FUNCTION public._driver_mission_hold_release_internal(
  p_source_module text, p_source_id uuid, p_kind text DEFAULT NULL::text,
  p_reason text DEFAULT NULL::text, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_h public.mission_financial_holds;
  v_released bigint := 0; v_wallet_id uuid; v_open bigint; v_u bigint; v_p bigint;
BEGIN
  FOR v_h IN
    SELECT * FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND (p_kind IS NULL OR kind = p_kind)
       AND driver_user_id IS NOT NULL
       AND kind <> 'customer_payment'
       AND state IN ('held','partially_captured','frozen')
     ORDER BY created_at FOR UPDATE
  LOOP
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
      v_h.mission_type, p_actor, v_h.policy_snapshot, v_h.is_sandbox, p_reason);

    UPDATE public.mission_financial_holds
       SET state = 'released', released_gnf = released_gnf + v_open,
           reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = p_actor
     WHERE id = v_h.id;

    v_released := v_released + v_open;
  END LOOP;

  RETURN jsonb_build_object('status', 'released', 'released_gnf', v_released);
END; $function$;

REVOKE ALL ON FUNCTION public._driver_mission_hold_release_internal(text,uuid,text,text,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._driver_mission_hold_release_internal(text,uuid,text,text,uuid)
  TO service_role;

-- ============================================================
-- QA PART 3 — Chop Pay tender lifecycle
-- ============================================================
CREATE OR REPLACE FUNCTION public._qa_s6_run3()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_send uuid; v_poor uuid; v_drv uuid; v_god uuid;
  v_pkg uuid; v_mis uuid; v_rt public.package_runtime; v_q uuid;
  v_j jsonb; v_err text; v_n bigint; v_b bigint; v_h bigint;
  v_master0 bigint; v_master1 bigint; v_master2 bigint; v_pick text; v_del text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    v_send := gen_random_uuid(); v_drv := gen_random_uuid();
    v_god := gen_random_uuid(); v_poor := gen_random_uuid();
    PERFORM public._qa_s6_setup(v_send, v_drv, v_god);
    INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf) VALUES (v_poor,'client',50000);

    -- P. authorisation: full-order customer hold, no cash due
    v_pkg := public._qa_s6_ship(v_send, 400000, 'chop_pay', 'qa-s6-p1');
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg;
    SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;

    r := r || public._qa_s5_ok('P1 chop pay customer hold = delivery fee + 1% fee (101000)',
      v_rt.customer_hold_gnf = 101000 AND v_rt.cash_due_gnf = 0,
      format('hold=%s cash_due=%s', v_rt.customer_hold_gnf, v_rt.cash_due_gnf));
    r := r || public._qa_s5_ok('P2 platform fee is 1% of the delivery fee only (1000)',
      v_rt.platform_fee_gnf = 1000, v_rt.platform_fee_gnf::text);
    r := r || public._qa_s5_ok('P3 declared 400000 => collateral 300000, exposure 100000',
      v_rt.collateral_gnf = 300000 AND v_rt.claims_exposure_gnf = 100000,
      format('col=%s exp=%s', v_rt.collateral_gnf, v_rt.claims_exposure_gnf));
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_send AND party_type='client';
    r := r || public._qa_s5_ok('P4 customer funds reserved at authorisation, balance untouched',
      v_b = 5000000 AND v_h = 101000, format('bal=%s held=%s', v_b, v_h));
    r := r || public._qa_s5_ok('P5 digital authorisation recorded on the shipment',
      (SELECT payment_status FROM public.package_deliveries WHERE id=v_pkg) = 'authorized');
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg;
    r := r || public._qa_s5_ok('P6 only the customer hold exists before a courier accepts', v_n = 1, v_n::text);
    r := r || public._qa_s5_ok('P7 explicit rail recorded (tender = chop_pay, never implicit)',
      v_rt.tender = 'chop_pay', v_rt.tender);

    -- Q. insufficient Chop Pay balance refuses the shipment atomically
    v_q := public._qa_s6_quote(v_poor, 100000);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_poor), true);
    PERFORM public.package_evidence_register(v_q, format('%s/%s/front.jpg', v_poor, v_q), 'item');
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-q1',NULL,'orange_money',false,NULL,
        200000,'chop_pay',true,'Je certifie que la valeur declaree est exacte.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('Q1 insufficient Chop Pay balance refuses the shipment',
      v_err LIKE '%INSUFFICIENT_CHOP_PAY_BALANCE%', v_err);
    SELECT count(*) INTO v_n FROM public.package_runtime;
    r := r || public._qa_s5_ok('Q2 refused Chop Pay shipment leaves no runtime residue', v_n = 1, v_n::text);
    SELECT held_gnf INTO v_h FROM public.wallets WHERE owner_user_id=v_poor AND party_type='client';
    r := r || public._qa_s5_ok('Q3 refused Chop Pay shipment reserves nothing', v_h = 0, v_h::text);

    -- R. acceptance: collateral only, never a cash fee reserve
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis);
    SELECT amount_gnf INTO v_b FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='collateral';
    r := r || public._qa_s5_ok('R1 courier collateral is exactly the frozen 300000', v_b = 300000, v_b::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='platform_fee';
    r := r || public._qa_s5_ok('R2 no courier fee reserve on a Chop Pay shipment (customer pays it)',
      v_n = 0, v_n::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('R3 courier balance untouched, held = 300000',
      v_b = 5000000 AND v_h = 300000, format('bal=%s held=%s', v_b, v_h));

    -- S. custody + settlement
    SELECT pickup_code, delivery_code INTO v_pick, v_del
      FROM public.package_delivery_secrets WHERE package_id=v_pkg;
    PERFORM public.package_verify_pickup(v_pkg, v_pick);
    v_j := public.package_verify_delivery(v_pkg, v_del, 'QA Destinataire');
    r := r || public._qa_s5_ok('S1 delivery verified on the Chop Pay rail', (v_j->>'ok')::boolean, v_j::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_send AND party_type='client';
    r := r || public._qa_s5_ok('S2 customer charged exactly 101000, nothing left reserved',
      v_b = 4899000 AND v_h = 0, format('bal=%s held=%s', v_b, v_h));
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('S3 courier receives the full delivery fee digitally (+100000), nothing held',
      v_b = 5100000 AND v_h = 0, format('bal=%s held=%s', v_b, v_h));
    SELECT balance_gnf INTO v_master2 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('S4 platform keeps exactly the 1000 transaction fee',
      v_master2 = v_master1 + 1000, format('before=%s after=%s', v_master1, v_master2));
    SELECT released_gnf, captured_gnf INTO v_b, v_h FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='collateral';
    r := r || public._qa_s5_ok('S5 collateral released in full, never captured on a clean delivery',
      v_b = 300000 AND v_h = 0, format('released=%s captured=%s', v_b, v_h));
    SELECT captured_gnf, released_gnf INTO v_b, v_h FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='customer_payment';
    r := r || public._qa_s5_ok('S6 customer reservation fully consumed, no residual release',
      v_b = 101000 AND v_h = 0, format('captured=%s released=%s', v_b, v_h));
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('S7 runtime completed with a digital courier earning of 100000',
      v_rt.state='completed' AND v_rt.driver_earning_gnf = 100000
      AND v_rt.platform_revenue_gnf = 1000, v_rt.state);

    -- T. replay + reconciliation invariants
    v_j := public.package_verify_delivery(v_pkg, v_del, 'QA Destinataire');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('T1 replayed Chop Pay delivery is inert', v_b = v_master2, v_b::text);
    SELECT count(*) INTO v_n FROM public.ledger_journals
     WHERE source_module='package' AND source_id=v_pkg AND journal_type='capture_customer_delivery';
    r := r || public._qa_s5_ok('T2 the delivery capture is journalled exactly once', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
       WHERE j.source_module='package' GROUP BY j.id HAVING sum(p.amount_gnf) <> 0 OR count(*) < 2) t;
    r := r || public._qa_s5_ok('T3 every Chop Pay Envoyer journal is balanced', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND captured_gnf + released_gnf > amount_gnf;
    r := r || public._qa_s5_ok('T4 no hold over-captured or over-released', v_n=0, v_n::text);

    RAISE EXCEPTION 'QA_S6_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S6_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART3_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z1 master wallet naturally restored by rollback',
    v_master1 = v_master0, v_master1::text);
  SELECT count(*) INTO v_n FROM public.package_runtime;
  r := r || public._qa_s5_ok('Z2 no runtime residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.feature_flags
   WHERE enabled AND key IN ('envoyer_enabled','envoyer_declared_value_enabled',
                             'envoyer_claims_enabled','chop_pay_checkout_enabled');
  r := r || public._qa_s5_ok('Z3 Slice 6 flags restored to OFF', v_n = 0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',3,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END; $$;

REVOKE ALL ON FUNCTION public._qa_s6_run3() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- QA PART 4 — claims lifecycle
-- ============================================================
CREATE OR REPLACE FUNCTION public._qa_s6_run4()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_send uuid; v_drv uuid; v_god uuid;
  v_pkg uuid; v_pkg2 uuid; v_pkg3 uuid; v_mis uuid; v_rt public.package_runtime;
  v_j jsonb; v_err text; v_n bigint; v_b bigint; v_h bigint;
  v_master0 bigint; v_master1 bigint; v_master2 bigint; v_pick text; v_del text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    v_send := gen_random_uuid(); v_drv := gen_random_uuid(); v_god := gen_random_uuid();
    PERFORM public._qa_s6_setup(v_send, v_drv, v_god);

    -- I. custody boundary: no claim before the courier has the parcel
    v_pkg := public._qa_s6_ship(v_send, 500000, 'cash', 'qa-s6-i1');
    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_send), true);
    BEGIN v_j := public.package_claim_open(v_pkg, 'Colis endommage a la livraison'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('I1 no claim before custody is established',
      v_err LIKE '%CUSTODY_NOT_ESTABLISHED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis);
    SELECT pickup_code, delivery_code INTO v_pick, v_del
      FROM public.package_delivery_secrets WHERE package_id=v_pkg;
    PERFORM public.package_verify_pickup(v_pkg, v_pick);
    SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;

    -- claim opening freezes settlement
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_send), true);
    v_j := public.package_claim_open(v_pkg, 'Colis perdu apres la prise en charge');
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('I2 claim opens after custody and freezes the runtime',
      (v_j->>'ok')::boolean AND v_rt.claim_state='open' AND v_rt.state='claim_open', v_rt.state);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND state='frozen';
    r := r || public._qa_s5_ok('I3 every open hold is frozen by the claim', v_n = 2, v_n::text);
    r := r || public._qa_s5_ok('I4 a support issue is opened and linked to the shipment',
      (v_j->>'support_issue_id') IS NOT NULL
      AND EXISTS (SELECT 1 FROM public.support_issues s
                   WHERE s.id = (v_j->>'support_issue_id')::uuid AND s.issue_type='package_dispute'));
    r := r || public._qa_s5_ok('I5 claim opening moves no money',
      (SELECT balance_gnf FROM public.wallets WHERE party_type='master' LIMIT 1) = v_master1);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_j := public.package_verify_delivery(v_pkg, v_del, 'QA'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('I6 settlement is blocked while a claim is open',
      v_err LIKE '%SETTLEMENT_FROZEN_BY_CLAIM%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_send), true);
    BEGIN v_j := public.package_delivery_cancel(v_pkg, 'test'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('I7 cancellation is blocked while a claim is open',
      v_err LIKE '%SETTLEMENT_FROZEN_BY_CLAIM%', v_err);

    -- J. adjudication authority
    BEGIN v_j := public.admin_package_claim_resolve(v_pkg,'customer_upheld','Enquete terminee','EV-0001',500000);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('J1 the sender cannot adjudicate their own claim',
      v_err LIKE '%forbidden%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    BEGIN v_j := public.admin_package_claim_resolve(v_pkg,'customer_upheld','Enquete','EV-1',600000);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('J2 payment above the declared value is refused',
      v_err LIKE '%CLAIM_EXCEEDS_DECLARED_VALUE%', v_err);
    BEGIN v_j := public.admin_package_claim_resolve(v_pkg,'customer_upheld','Enquete terminee',NULL,100000);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('J3 an investigated outcome requires an evidence reference',
      v_err LIKE '%CLAIM_EVIDENCE_REQUIRED%', v_err);

    -- upheld: collateral first, platform exposure second
    v_j := public.admin_package_claim_resolve(
      v_pkg,'customer_upheld','Colis perdu, responsabilite coursier etablie','EV-S6-0001',500000);
    r := r || public._qa_s5_ok('J4 upheld claim splits 375000 collateral + 125000 platform exposure',
      (v_j->>'from_collateral_gnf')::bigint = 375000
      AND (v_j->>'from_platform_gnf')::bigint = 125000, v_j::text);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_send AND party_type='client';
    r := r || public._qa_s5_ok('J5 customer compensated exactly the declared value (5000000 + 500000)',
      v_b = 5500000, v_b::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('J6 courier loses exactly the collateral, nothing stays held',
      v_b = 4625000 AND v_h = 0, format('bal=%s held=%s', v_b, v_h));
    SELECT balance_gnf INTO v_master2 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('J7 platform absorbs exactly its 125000 exposure, never more',
      v_master2 = v_master1 - 125000, format('before=%s after=%s', v_master1, v_master2));
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('J8 runtime records the upheld outcome and the amount paid',
      v_rt.claim_state='upheld' AND v_rt.claim_paid_gnf = 500000 AND v_rt.resolved_at IS NOT NULL,
      v_rt.claim_state);
    r := r || public._qa_s5_ok('J9 the adjudication is audited with reason and evidence',
      EXISTS (SELECT 1 FROM public.audit_logs WHERE action='package.claim.customer_upheld'
               AND actor_user_id = v_god AND target_id = v_pkg::text
               AND after->>'evidence_ref' = 'EV-S6-0001'));
    v_j := public.admin_package_claim_resolve(v_pkg,'customer_upheld','Rejeu','EV-S6-0001',500000);
    r := r || public._qa_s5_ok('J10 replayed adjudication is inert',
      v_j->>'status' = 'already_resolved'
      AND (SELECT balance_gnf FROM public.wallets WHERE party_type='master' LIMIT 1) = v_master2, v_j::text);

    -- exonerated branch
    v_pkg2 := public._qa_s6_ship(v_send, 400000, 'chop_pay', 'qa-s6-j2');
    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis);
    SELECT pickup_code INTO v_pick FROM public.package_delivery_secrets WHERE package_id=v_pkg2;
    PERFORM public.package_verify_pickup(v_pkg2, v_pick);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_send), true);
    PERFORM public.package_claim_open(v_pkg2, 'Contenu non conforme a la remise');
    SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_j := public.admin_package_claim_resolve(
      v_pkg2,'driver_exonerated','Preuves photo et code de remise concordants','EV-S6-0002');
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg2;
    r := r || public._qa_s5_ok('J11 exonerated claim pays the customer nothing',
      (v_j->>'paid_gnf')::bigint = 0
      AND (SELECT balance_gnf FROM public.wallets WHERE party_type='master' LIMIT 1) = v_master1, v_j::text);
    r := r || public._qa_s5_ok('J12 exonerated claim is recorded as denied and resolved',
      v_rt.claim_state='denied' AND v_rt.resolved_at IS NOT NULL, v_rt.claim_state);
    SELECT held_gnf INTO v_h FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('J13 exonerated courier keeps nothing frozen', v_h = 0, v_h::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_send AND party_type='client';
    r := r || public._qa_s5_ok('J14 DEF-FIN-S6-001: customer Chop Pay reservation is fully released',
      v_h = 0, format('bal=%s held=%s', v_b, v_h));

    -- reconciliation branch
    v_pkg3 := public._qa_s6_ship(v_send, 300000, 'cash', 'qa-s6-j3');
    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg3;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis);
    SELECT pickup_code INTO v_pick FROM public.package_delivery_secrets WHERE package_id=v_pkg3;
    PERFORM public.package_verify_pickup(v_pkg3, v_pick);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_send), true);
    PERFORM public.package_claim_open(v_pkg3, 'Litige sur le contenu du colis');
    SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_j := public.admin_package_claim_resolve(
      v_pkg3,'reconciliation_required','Preuves insuffisantes, dossier en reconciliation','EV-S6-0003');
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg3;
    r := r || public._qa_s5_ok('J15 reconciliation outcome moves no money',
      (v_j->>'money_moved')::boolean = false
      AND (SELECT balance_gnf FROM public.wallets WHERE party_type='master' LIMIT 1) = v_master1, v_j::text);
    r := r || public._qa_s5_ok('J16 reconciliation keeps the shipment blocked and traceable',
      v_rt.claim_state='reconciliation_required' AND v_rt.state='reconciliation_required',
      v_rt.claim_state);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg3 AND state='frozen';
    r := r || public._qa_s5_ok('J17 funds stay frozen until reconciliation completes', v_n = 2, v_n::text);

    -- invariants across every claim journal
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
       WHERE j.source_module='package' GROUP BY j.id HAVING sum(p.amount_gnf) <> 0 OR count(*) < 2) t;
    r := r || public._qa_s5_ok('N4 every claim journal is balanced', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND captured_gnf + released_gnf > amount_gnf;
    r := r || public._qa_s5_ok('N5 no claim over-captured a hold', v_n=0, v_n::text);

    RAISE EXCEPTION 'QA_S6_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S6_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART4_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z1 master wallet naturally restored by rollback',
    v_master1 = v_master0, v_master1::text);
  SELECT count(*) INTO v_n FROM public.package_runtime;
  r := r || public._qa_s5_ok('Z2 no runtime residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.claims_reserves;
  r := r || public._qa_s5_ok('Z3 no claims-reserve residue', v_n = 0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',4,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END; $$;

REVOKE ALL ON FUNCTION public._qa_s6_run4() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- QA PART 5 — privilege matrix (M) + private evidence posture (L)
-- ============================================================
CREATE OR REPLACE FUNCTION public._qa_s6_run5()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int; v_n bigint; v_bad text;
BEGIN
  -- M1: no internal Envoyer primitive is reachable by a client role
  SELECT count(*), COALESCE(string_agg(sig,', '),'') INTO v_n, v_bad FROM (
    SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace
       AND p.proname IN ('_package_economics','_package_dispatch_internal',
             '_package_choppay_hold_internal','_package_choppay_capture_internal',
             '_package_choppay_release_internal','_package_authorize_internal',
             '_package_accept_internal','_package_complete_internal',
             '_package_cancel_release_internal','_package_claim_freeze_internal',
             '_package_collateral_capture_internal','_driver_exact_hold_place_internal',
             '_driver_mission_hold_release_internal')
       AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
            OR has_function_privilege('anon', p.oid, 'EXECUTE'))) t;
  r := r || public._qa_s5_ok('M1 every internal Envoyer primitive is service_role only', v_n = 0, v_bad);

  -- M2: internals remain executable by service_role
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace
     AND p.proname IN ('_package_authorize_internal','_package_accept_internal',
                       '_package_complete_internal','_package_claim_freeze_internal')
     AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE');
  r := r || public._qa_s5_ok('M2 service_role retains the internal engine', v_n = 0, v_n::text);

  -- M3: participant wrappers reachable by signed-in users, never by anon
  SELECT count(*), COALESCE(string_agg(sig,', '),'') INTO v_n, v_bad FROM (
    SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace
       AND p.proname IN ('package_delivery_create_checkout','package_evidence_register',
             'package_claim_open','package_verify_pickup','package_verify_delivery',
             'package_delivery_cancel','package_delivery_quote')
       AND (NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
            OR has_function_privilege('anon', p.oid, 'EXECUTE'))) t;
  r := r || public._qa_s5_ok('M3 participant wrappers are authenticated-only', v_n = 0, v_bad);

  -- M4: adjudication is guarded in code, not by grant alone
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname='admin_package_claim_resolve'
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR pg_get_functiondef(p.oid) NOT LIKE '%is_god_admin%');
  r := r || public._qa_s5_ok('M4 claim adjudication is God-Admin gated and closed to anon', v_n = 0, v_n::text);

  -- L1: evidence bucket is private
  SELECT count(*) INTO v_n FROM storage.buckets WHERE id='package-evidence' AND public = false;
  r := r || public._qa_s5_ok('L1 package-evidence bucket exists and is private', v_n = 1, v_n::text);

  -- L2: no anon or public storage policy on the evidence bucket
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND qual LIKE '%package-evidence%' AND ('anon' = ANY(roles) OR roles = '{public}');
  r := r || public._qa_s5_ok('L2 no anonymous read path to shipment photos', v_n = 0, v_n::text);

  -- L3: evidence rows are RLS-protected and readable only by participants/admins
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='package_evidence_photos';
  r := r || public._qa_s5_ok('L3 evidence register carries participant/admin read policies',
    v_n = 3 AND (SELECT relrowsecurity FROM pg_class WHERE oid='public.package_evidence_photos'::regclass),
    v_n::text);

  -- L4: clients cannot write the evidence register directly (RPC-only)
  SELECT count(*) INTO v_n FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name IN ('package_evidence_photos','package_runtime')
     AND grantee IN ('authenticated','anon') AND privilege_type <> 'SELECT';
  r := r || public._qa_s5_ok('L4 evidence and runtime tables are read-only for client roles', v_n = 0, v_n::text);

  -- L5: financial runtime is never anon-readable
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='package_runtime' AND 'anon' = ANY(roles);
  r := r || public._qa_s5_ok('L5 Envoyer financial runtime is closed to anon', v_n = 0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',5,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END; $$;

REVOKE ALL ON FUNCTION public._qa_s6_run5() FROM PUBLIC, anon, authenticated;