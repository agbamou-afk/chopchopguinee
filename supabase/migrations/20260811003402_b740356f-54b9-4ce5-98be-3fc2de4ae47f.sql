CREATE OR REPLACE FUNCTION public._qa_s6_run2()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_send uuid; v_drv uuid; v_drv2 uuid; v_god uuid;
  v_pkg uuid; v_mis uuid; v_rt public.package_runtime;
  v_j jsonb; v_err text; v_n bigint; v_b bigint; v_h bigint;
  v_master0 bigint; v_master1 bigint; v_master2 bigint;
  v_pick text; v_del text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    v_send := gen_random_uuid(); v_drv := gen_random_uuid();
    v_drv2 := gen_random_uuid(); v_god := gen_random_uuid();
    PERFORM public._qa_s6_setup(v_send, v_drv, v_god);
    INSERT INTO public.driver_profiles(user_id, status, vehicle_type, capabilities)
    VALUES (v_drv2,'approved','moto',ARRAY['package_delivery']);
    INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf) VALUES (v_drv2,'driver',100000);

    v_pkg := public._qa_s6_ship(v_send, 500000, 'cash', 'qa-s6-e1');
    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg;
    SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    BEGIN PERFORM public.mission_claim(v_mis); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('E1 courier without enough balance cannot take custody', v_err <> 'NO_ERROR', v_err);
    r := r || public._qa_s5_ok('E2 refused acceptance leaves no hold and no assignment',
      NOT EXISTS (SELECT 1 FROM public.mission_financial_holds WHERE source_module='package' AND source_id=v_pkg)
      AND (SELECT courier_id FROM public.missions WHERE id=v_mis) IS NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis);
    SELECT amount_gnf, unrestricted_gnf INTO v_b, v_h FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='collateral';
    r := r || public._qa_s5_ok('E3 collateral hold is exactly the frozen 375000 (unrestricted)',
      v_b = 375000 AND v_h = 375000, format('amount=%s unrestricted=%s', v_b, v_h));
    SELECT amount_gnf INTO v_b FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='platform_fee';
    r := r || public._qa_s5_ok('E4 platform fee reserve held at acceptance (1000)', v_b = 1000, v_b::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('E5 courier balance untouched, held = 376000',
      v_b = 5000000 AND v_h = 376000, format('bal=%s held=%s', v_b, v_h));
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('E6 runtime accepted and bound to the courier',
      v_rt.state='accepted' AND v_rt.driver_user_id=v_drv, v_rt.state);

    SELECT pickup_code, delivery_code INTO v_pick, v_del FROM public.package_delivery_secrets WHERE package_id=v_pkg;
    v_j := public.package_verify_pickup(v_pkg, '000000');
    r := r || public._qa_s5_ok('F1 wrong pickup code refused without custody', (v_j->>'ok')::boolean = false, v_j::text);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('F2 refused verification moves no money', v_b = v_master1, v_b::text);
    v_j := public.package_verify_pickup(v_pkg, v_pick);
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('F3 correct pickup code establishes custody',
      (v_j->>'ok')::boolean AND v_rt.state = 'picked_up', v_rt.state);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND state='held';
    r := r || public._qa_s5_ok('F4 both holds stay held through custody', v_n = 2, v_n::text);

    v_j := public.package_verify_delivery(v_pkg, v_del, 'QA Destinataire');
    r := r || public._qa_s5_ok('G1 delivery verified', (v_j->>'ok')::boolean, v_j::text);
    SELECT balance_gnf INTO v_master2 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('G2 platform fee captured exactly once (master +1000)',
      v_master2 = v_master1 + 1000, format('before=%s after=%s', v_master1, v_master2));
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('G3 courier pays only the 1000 fee, nothing held afterwards',
      v_b = 4999000 AND v_h = 0, format('bal=%s held=%s', v_b, v_h));
    r := r || public._qa_s5_ok('G4 no digital delivery-fee earning on a cash shipment',
      NOT EXISTS (SELECT 1 FROM public.wallet_transactions WHERE reference_id = v_pkg::text AND amount_gnf = 100000));
    SELECT released_gnf, captured_gnf INTO v_b, v_h FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='collateral';
    r := r || public._qa_s5_ok('G5 collateral released in full, never captured on a clean delivery',
      v_b = 375000 AND v_h = 0, format('released=%s captured=%s', v_b, v_h));
    SELECT captured_gnf INTO v_b FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='platform_fee';
    r := r || public._qa_s5_ok('G6 platform fee reserve fully captured', v_b = 1000, v_b::text);
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('G7 runtime completed and cash due recorded (101000)',
      v_rt.state='completed' AND v_rt.cash_due_gnf = 101000, v_rt.state);

    v_j := public.package_verify_delivery(v_pkg, v_del, 'QA Destinataire');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('H1 replayed delivery is inert (no second fee capture)', v_b = v_master2, v_b::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='package' AND source_id=v_pkg;
    r := r || public._qa_s5_ok('H2 replay creates no additional hold', v_n = 2, v_n::text);
    BEGIN PERFORM public.mission_claim(v_mis); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('H3 a settled mission cannot be re-claimed', v_err <> 'NO_ERROR', v_err);

    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
       WHERE j.source_module='package' GROUP BY j.id HAVING sum(p.amount_gnf) <> 0 OR count(*) < 2) t;
    r := r || public._qa_s5_ok('N1 every Envoyer journal is balanced with at least two postings', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND captured_gnf + released_gnf > amount_gnf;
    r := r || public._qa_s5_ok('N2 no hold releases or captures more than it reserved', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE source_module='package' AND source_id IS NULL;
    r := r || public._qa_s5_ok('N3 every Envoyer journal is traceable to its shipment', v_n=0, v_n::text);

    RAISE EXCEPTION 'QA_S6_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S6_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART2_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z1 master wallet naturally restored by rollback', v_master1 = v_master0, v_master1::text);
  SELECT count(*) INTO v_n FROM public.package_runtime;
  r := r || public._qa_s5_ok('Z2 no runtime residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='package';
  r := r || public._qa_s5_ok('Z3 no hold residue', v_n=0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',2,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x WHERE NOT (x->>'ok')::boolean));
END; $$;
REVOKE ALL ON FUNCTION public._qa_s6_run2() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s6_results(part, report) SELECT 2, public._qa_s6_run2();