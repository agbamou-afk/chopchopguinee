CREATE OR REPLACE FUNCTION public._qa_s10_run()
RETURNS TABLE(id text, ok boolean, detail text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_user uuid;
  v_master bigint;
  v_n int;
  v_msg text;
BEGIN
  SELECT p.user_id INTO v_user FROM public.profiles p LIMIT 1;

  BEGIN
    -- ============ A. RUNTIME STAGE GATES (all stages OFF) ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_user), true);

    BEGIN
      PERFORM public.driver_cashout_create_request(10000,'+224620000000','qa');
      id:='A1-stage6-cashout-blocked'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='A1-stage6-cashout-blocked'; ok:=(v_msg LIKE '%STAGE_DISABLED:driver_cashout_enabled%'); detail:=v_msg; RETURN NEXT;
    END;

    BEGIN
      PERFORM public.wallet_p2p_transfer(v_user, 5000, 'qa', 'qa-s10');
      id:='A2-stage7-p2p-blocked'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='A2-stage7-p2p-blocked'; ok:=(v_msg LIKE '%STAGE_DISABLED:chop_pay_p2p_enabled%'); detail:=v_msg; RETURN NEXT;
    END;

    BEGIN
      PERFORM public.package_claim_open(gen_random_uuid(),'qa claim reason','EV-QA-1');
      id:='A3-envoyer-claims-blocked'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='A3-envoyer-claims-blocked'; ok:=(v_msg LIKE '%ENVOYER_CLAIMS_DISABLED%'); detail:=v_msg; RETURN NEXT;
    END;

    PERFORM set_config('request.jwt.claims', NULL, true);

    -- Stage 5 runs as service (no jwt) -> _finance_privileged true for internal
    BEGIN
      PERFORM public.merchant_settlement_complete(gen_random_uuid(),'EV-QA-SETTLE');
      id:='A4-stage5-settlement-blocked'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='A4-stage5-settlement-blocked'; ok:=(v_msg LIKE '%STAGE_DISABLED:merchant_om_settlement_enabled%'); detail:=v_msg; RETURN NEXT;
    END;

    -- ============ B. UMBRELLA ISOLATION ============
    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_enabled';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_user), true);

    BEGIN
      PERFORM public.driver_cashout_create_request(10000,'+224620000000','qa');
      id:='B1-umbrella-does-not-imply-stage6'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='B1-umbrella-does-not-imply-stage6'; ok:=(v_msg LIKE '%STAGE_DISABLED:driver_cashout_enabled%'); detail:=v_msg; RETURN NEXT;
    END;

    BEGIN
      PERFORM public.wallet_p2p_transfer(v_user, 5000, 'qa', 'qa-s10b');
      id:='B2-umbrella-does-not-imply-stage7'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='B2-umbrella-does-not-imply-stage7'; ok:=(v_msg LIKE '%STAGE_DISABLED:chop_pay_p2p_enabled%'); detail:=v_msg; RETURN NEXT;
    END;

    PERFORM set_config('request.jwt.claims', NULL, true);
    BEGIN
      PERFORM public.merchant_settlement_complete(gen_random_uuid(),'EV-QA-SETTLE');
      id:='B3-umbrella-does-not-imply-stage5'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='B3-umbrella-does-not-imply-stage5'; ok:=(v_msg LIKE '%STAGE_DISABLED:merchant_om_settlement_enabled%'); detail:=v_msg; RETURN NEXT;
    END;

    -- Stage 4 ON must not imply stage 5/6/7
    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_checkout_enabled';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_user), true);
    BEGIN
      PERFORM public.driver_cashout_create_request(10000,'+224620000000','qa');
      id:='B4-stage4-does-not-imply-stage6'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='B4-stage4-does-not-imply-stage6'; ok:=(v_msg LIKE '%STAGE_DISABLED:driver_cashout_enabled%'); detail:=v_msg; RETURN NEXT;
    END;

    -- Stage 5 ON must not imply stage 6
    UPDATE public.feature_flags SET enabled = true WHERE key = 'merchant_om_settlement_enabled';
    BEGIN
      PERFORM public.driver_cashout_create_request(10000,'+224620000000','qa');
      id:='B5-stage5-does-not-imply-stage6'; ok:=false; detail:='no exception'; RETURN NEXT;
    EXCEPTION WHEN OTHERS THEN
      v_msg := SQLERRM;
      id:='B5-stage5-does-not-imply-stage6'; ok:=(v_msg LIKE '%STAGE_DISABLED:driver_cashout_enabled%'); detail:=v_msg; RETURN NEXT;
    END;
    PERFORM set_config('request.jwt.claims', NULL, true);

    RAISE EXCEPTION 'QA_S10_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S10_ROLLBACK' THEN
      id:='FIXTURE-ERROR'; ok:=false; detail:=SQLERRM; RETURN NEXT;
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', NULL, true);

  -- ============ C. SOURCE-LEVEL ENGINE GATES ============
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='cash_order_quote' AND p.prosrc ILIKE '%cash_order_funding_enabled%';
  id:='C1-stage2-cash-order-flag'; ok:=(v_n=1); detail:=v_n::text; RETURN NEXT;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='chop_pay_authorize_order' AND p.prosrc ILIKE '%chop_pay_checkout_enabled%';
  id:='C2-stage4-chop-pay-checkout-flag'; ok:=(v_n=1); detail:=v_n::text; RETURN NEXT;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='package_delivery_create_checkout' AND p.prosrc ILIKE '%_envoyer_enabled%';
  id:='C3-stage3-envoyer-flag'; ok:=(v_n=1); detail:=v_n::text; RETURN NEXT;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='driver_offer_accept_for_ride' AND p.prosrc ILIKE '%driver_balance_gate_enabled%';
  id:='C4-stage1-ride-commission-gate'; ok:=(v_n=1); detail:=v_n::text; RETURN NEXT;

  -- ============ D. ANON PRIVILEGE POSTURE ============
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND (p.proname LIKE 'driver_cashout%' OR p.proname LIKE 'wallet_p2p%'
          OR p.proname IN ('wallet_topup_om_credit','merchant_settlement_complete','om_auto_match'))
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  id:='D1-anon-no-finance-execute'; ok:=(v_n=0); detail:=v_n::text; RETURN NEXT;

  -- ============ E. LEDGER INVARIANTS ============
  SELECT count(*) INTO v_n FROM (
    SELECT journal_id FROM public.ledger_postings GROUP BY journal_id HAVING sum(amount_gnf) <> 0) x;
  id:='E1-ledger-zero-sum'; ok:=(v_n=0); detail:=v_n::text; RETURN NEXT;

  SELECT count(*) INTO v_n FROM (
    SELECT journal_id FROM public.ledger_postings GROUP BY journal_id HAVING count(*) < 2) x;
  id:='E2-ledger-min-two-legs'; ok:=(v_n=0); detail:=v_n::text; RETURN NEXT;

  -- ============ F. OM INBOUND STRICT EVIDENCE (Slice 9 regression) ============
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='om_auto_match' AND p.prosrc ILIKE '%payer_phone_missing%';
  id:='F1-om-payer-phone-required'; ok:=(v_n=1); detail:=v_n::text; RETURN NEXT;

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='wallet_topup_om_credit' AND p.prosrc ILIKE '%needs_review%';
  id:='F2-om-credit-parks-mismatch'; ok:=(v_n=1); detail:=v_n::text; RETURN NEXT;

  -- ============ G. FLAG STATE (post-run, must be unchanged) ============
  SELECT count(*) INTO v_n FROM public.feature_flags
   WHERE key IN ('chop_pay_p2p_enabled','driver_cashout_enabled','merchant_om_settlement_enabled',
                 'chop_pay_checkout_enabled','chop_pay_enabled') AND enabled = true;
  id:='G1-stages-4to7-off-after-run'; ok:=(v_n=0); detail:=v_n::text; RETURN NEXT;

  SELECT count(*) INTO v_n FROM public.feature_flags WHERE key='om_topup_enabled' AND enabled;
  id:='G2-om-topup-remains-on'; ok:=(v_n=1); detail:=v_n::text; RETURN NEXT;

  -- ============ H. MASTER WALLET BASELINE ============
  SELECT COALESCE(sum(balance_gnf),0) INTO v_master FROM public.wallets WHERE party_type='master';
  id:='H1-master-wallet-unchanged'; ok:=(v_master = -100435); detail:=v_master::text; RETURN NEXT;
END; $$;

REVOKE ALL ON FUNCTION public._qa_s10_run() FROM PUBLIC, anon, authenticated;
