CREATE OR REPLACE FUNCTION public._qa_node5_finance_dormant_liability()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  u_pos  uuid := gen_random_uuid();
  u_held uuid := gen_random_uuid();
  u_debt uuid := gen_random_uuid();
  u_succ uuid := gen_random_uuid();
  u_god  uuid := gen_random_uuid();
  ids uuid[];
  ph text;
  res jsonb; v_txt text; v_amt bigint; v_id uuid;
  b_lp bigint; b_ls numeric; b_w bigint; b_pr bigint; b_dc bigint;
  a_lp bigint; a_ls numeric; a_w bigint; a_pr bigint; a_dc bigint;
BEGIN
  ids := ARRAY[u_pos,u_held,u_debt,u_succ,u_god];
  ph  := '+22468' || lpad((floor(random()*10000000))::bigint::text, 7, '0');

  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_pr FROM public.profiles;
  SELECT count(*) INTO b_dc FROM public.dormant_closed_account_liabilities;

  -- ================= A. STRUCTURE / LAW SURFACE =================
  r := r || public._qa_s13_ok('N5DL.A1 the dormant liability register exists',
        to_regclass('public.dormant_closed_account_liabilities') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5DL.A2 the register enforces row level security',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.dormant_closed_account_liabilities'::regclass), NULL);
  r := r || public._qa_s13_ok('N5DL.A3 the register is never readable signed-out',
        NOT has_table_privilege('anon','public.dormant_closed_account_liabilities','SELECT'), NULL);
  r := r || public._qa_s13_ok('N5DL.A4 customers can never write the register',
        NOT has_table_privilege('authenticated','public.dormant_closed_account_liabilities','INSERT')
        AND NOT has_table_privilege('authenticated','public.dormant_closed_account_liabilities','UPDATE')
        AND NOT has_table_privilege('authenticated','public.dormant_closed_account_liabilities','DELETE'), NULL);
  r := r || public._qa_s13_ok('N5DL.A5 the only read policy is staff scoped',
        (SELECT count(*) FROM pg_policies WHERE schemaname='public'
          AND tablename='dormant_closed_account_liabilities'
          AND qual LIKE '%_is_ops_or_god_admin%') = 1, NULL);
  r := r || public._qa_s13_ok('N5DL.A6 the classification primitive is internal only',
        NOT has_function_privilege('anon','public._dormant_liability_classify(uuid,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._dormant_liability_classify(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5DL.A7 no settlement rail is active',
        (SELECT COALESCE(bool_or(enabled),false) FROM public.feature_flags
          WHERE key='dormant_liability_settlement_enabled') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5DL.A8 a positive balance is no longer a closure blocker token',
        pg_get_functiondef('public._account_closure_blockers(uuid,text)'::regprocedure)
          NOT LIKE '%WALLET_BALANCE_NONZERO%', NULL);
  r := r || public._qa_s13_ok('N5DL.A9 a negative balance is still a closure blocker',
        pg_get_functiondef('public._account_closure_blockers(uuid,text)'::regprocedure)
          LIKE '%WALLET_BALANCE_NEGATIVE%', NULL);
  r := r || public._qa_s13_ok('N5DL.A10 held funds are still a closure blocker',
        pg_get_functiondef('public._account_closure_blockers(uuid,text)'::regprocedure)
          LIKE '%WALLET_FUNDS_HELD%', NULL);
  r := r || public._qa_s13_ok('N5DL.A11 in-flight cash-out is still a closure blocker',
        pg_get_functiondef('public._account_closure_blockers(uuid,text)'::regprocedure)
          LIKE '%DRIVER_CASHOUT_IN_FLIGHT%', NULL);
  r := r || public._qa_s13_ok('N5DL.A12 closure records the dormant liability',
        pg_get_functiondef('public._account_closure_core(uuid,text,text)'::regprocedure)
          LIKE '%_dormant_liability_classify%', NULL);
  r := r || public._qa_s13_ok('N5DL.A13 legacy reconciliation records the dormant liability',
        pg_get_functiondef('public.admin_account_closure_reconcile(uuid,text)'::regprocedure)
          LIKE '%_dormant_liability_classify%', NULL);

  -- ================= FIXTURES =================
  PERFORM public._qa_node5_fr_seed(ids);
  PERFORM public._qa_node5_fr_profiles(ids);
  UPDATE public.profiles SET phone = ph WHERE user_id = u_pos;
  INSERT INTO public.admin_users(user_id,admin_role,status) VALUES (u_god,'god_admin','active');
  INSERT INTO public.user_roles(user_id,role) VALUES (u_pos,'driver'),(u_pos,'user');
  INSERT INTO public.professional_identities(user_id,professional_type,claim_state,claimed_at)
  VALUES (u_pos,'driver','active',now()), (u_debt,'driver','active',now());
  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence)
  VALUES (u_pos,'approved','moto','online'), (u_debt,'approved','moto','offline');
  UPDATE public.driver_profiles SET cash_debt_gnf = 7500 WHERE user_id = u_debt;

  PERFORM public._qa_s13_wallet(u_pos,'driver',29448,0);
  PERFORM public._qa_s13_wallet(u_held,'client',12000,3000);
  PERFORM public._qa_s13_wallet(u_debt,'driver',4000,0);

  r := r || public._qa_s13_ok('N5DL.B1 the fixture account really holds a positive balance',
        (SELECT balance_gnf FROM public.wallets WHERE owner_user_id=u_pos AND party_type='driver') = 29448, NULL);
  r := r || public._qa_s13_ok('N5DL.B2 the held fixture really holds funds',
        (SELECT held_gnf FROM public.wallets WHERE owner_user_id=u_held) = 3000, NULL);

  -- ================= C. HELD FUNDS STILL BLOCK =================
  res := public._account_closure_blockers(u_held,'self');
  r := r || public._qa_s13_ok('N5DL.C1 held funds keep the account closure-ineligible',
        (res->>'eligible')::boolean IS FALSE
        AND res->'blockers' @> '"WALLET_FUNDS_HELD"'::jsonb, res::text);
  BEGIN
    PERFORM public._account_closure_core(u_held,'admin','qa dl held');
    r := r || public._qa_s13_ok('N5DL.C2 closure is refused while funds are held', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5DL.C2 closure is refused while funds are held',
          v_txt LIKE '%ACCOUNT_CLOSURE_BLOCKED%', v_txt);
  END;
  r := r || public._qa_s13_ok('N5DL.C3 a refused closure records no liability',
        NOT EXISTS (SELECT 1 FROM public.dormant_closed_account_liabilities WHERE user_id=u_held), NULL);
  r := r || public._qa_s13_ok('N5DL.C4 a refused closure leaves the account open',
        (SELECT account_status FROM public.profiles WHERE user_id=u_held) <> 'deleted', NULL);

  -- ================= D. OTHER FINANCIAL OBLIGATIONS STILL BLOCK =================
  res := public._account_closure_blockers(u_debt,'self');
  r := r || public._qa_s13_ok('N5DL.D1 an outstanding driver cash debt still blocks closure',
        (res->>'eligible')::boolean IS FALSE
        AND res->'blockers' @> '"DRIVER_CASH_DEBT_OUTSTANDING"'::jsonb, res::text);
  BEGIN
    PERFORM public._account_closure_core(u_debt,'admin','qa dl debt');
    r := r || public._qa_s13_ok('N5DL.D2 closure is refused while a debt is outstanding', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5DL.D2 closure is refused while a debt is outstanding',
          v_txt LIKE '%ACCOUNT_CLOSURE_BLOCKED%', v_txt);
  END;
  r := r || public._qa_s13_ok('N5DL.D3 the blocked debtor keeps its balance untouched',
        (SELECT balance_gnf FROM public.wallets WHERE owner_user_id=u_debt) = 4000, NULL);

  -- ================= E. POSITIVE BALANCE NO LONGER BLOCKS =================
  res := public._account_closure_blockers(u_pos,'admin');
  r := r || public._qa_s13_ok('N5DL.E1 a positive available balance alone leaves closure eligible',
        (res->>'eligible')::boolean IS TRUE, res::text);
  res := public._account_closure_core(u_pos,'admin','qa dl positive');
  r := r || public._qa_s13_ok('N5DL.E2 the account closes with a positive balance',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5DL.E3 closure reports exactly one classified wallet',
        (res->'authority'->'dormant_liability'->>'wallets_classified')::int = 1, res::text);
  r := r || public._qa_s13_ok('N5DL.E4 closure reports the exact preserved amount',
        (res->'authority'->'dormant_liability'->>'amount_gnf')::bigint = 29448, res::text);
  r := r || public._qa_s13_ok('N5DL.E5 the profile is closed',
        (SELECT account_status FROM public.profiles WHERE user_id=u_pos) = 'deleted', NULL);

  -- ================= F. THE MONEY IS PRESERVED, NOT MOVED =================
  SELECT amount_gnf INTO v_amt FROM public.dormant_closed_account_liabilities WHERE user_id=u_pos;
  r := r || public._qa_s13_ok('N5DL.F1 a dormant liability is recorded for the closed account',
        v_amt = 29448, COALESCE(v_amt::text,'none'));
  r := r || public._qa_s13_ok('N5DL.F2 the liability is dormant, never settled',
        (SELECT state FROM public.dormant_closed_account_liabilities WHERE user_id=u_pos) = 'dormant', NULL);
  r := r || public._qa_s13_ok('N5DL.F3 the wallet balance is byte-for-byte unchanged',
        (SELECT balance_gnf FROM public.wallets WHERE owner_user_id=u_pos AND party_type='driver') = 29448, NULL);
  r := r || public._qa_s13_ok('N5DL.F4 the wallet row itself survives',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_pos), NULL);
  r := r || public._qa_s13_ok('N5DL.F5 the wallet is immobilised, not spendable',
        (SELECT status FROM public.wallets WHERE owner_user_id=u_pos AND party_type='driver')::text = 'frozen', NULL);
  r := r || public._qa_s13_ok('N5DL.F6 the liability stays anchored to the original canonical UUID',
        (SELECT user_id FROM public.dormant_closed_account_liabilities WHERE user_id=u_pos) = u_pos, NULL);
  r := r || public._qa_s13_ok('N5DL.F7 the liability points at the original wallet',
        (SELECT wallet_id FROM public.dormant_closed_account_liabilities WHERE user_id=u_pos)
          = (SELECT id FROM public.wallets WHERE owner_user_id=u_pos AND party_type='driver'), NULL);
  r := r || public._qa_s13_ok('N5DL.F8 closure created no ledger movement',
        (SELECT count(*) FROM public.ledger_postings) = b_lp, NULL);
  r := r || public._qa_s13_ok('N5DL.F9 the ledger still balances to its prior value',
        (SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings) = b_ls, NULL);
  r := r || public._qa_s13_ok('N5DL.F10 no wallet transaction was fabricated for the closure',
        NOT EXISTS (SELECT 1 FROM public.wallet_transactions
                     WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id=u_pos)
                        OR to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id=u_pos)), NULL);
  r := r || public._qa_s13_ok('N5DL.F11 the money is never recognised as platform revenue',
        NOT EXISTS (SELECT 1 FROM public.ledger_postings lp
                     WHERE lp.created_at > now() - interval '2 minutes'
                       AND lp.amount_gnf = 29448), NULL);

  -- ================= G. NO AUTHORITY SURVIVES THE LIABILITY =================
  r := r || public._qa_s13_ok('N5DL.G1 dormant liability confers no capability role',
        (SELECT count(*) FROM public.user_roles WHERE user_id=u_pos) = 0, NULL);
  r := r || public._qa_s13_ok('N5DL.G2 dormant liability confers no professional authority',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_pos AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5DL.G3 dormant liability confers no driver operating status',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_pos) <> 'approved', NULL);
  r := r || public._qa_s13_ok('N5DL.G4 dormant liability confers no governance authority',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_pos AND status='active'), NULL);
  r := r || public._qa_s13_ok('N5DL.G5 dormant liability confers no recovery material',
        NOT EXISTS (SELECT 1 FROM public.account_recovery_profiles WHERE user_id=u_pos), NULL);
  r := r || public._qa_s13_ok('N5DL.G6 auth access termination is still enqueued',
        EXISTS (SELECT 1 FROM public.account_access_terminations WHERE user_id=u_pos), NULL);

  -- ================= H. NO INHERITANCE BY A SUCCESSOR =================
  UPDATE public.profiles SET phone = ph WHERE user_id = u_succ;
  r := r || public._qa_s13_ok('N5DL.H1 the freed contact can be reused by a new identity',
        (SELECT phone FROM public.profiles WHERE user_id=u_succ) = ph, NULL);
  r := r || public._qa_s13_ok('N5DL.H2 the successor inherits no dormant liability',
        NOT EXISTS (SELECT 1 FROM public.dormant_closed_account_liabilities WHERE user_id=u_succ), NULL);
  r := r || public._qa_s13_ok('N5DL.H3 the successor inherits no wallet balance',
        COALESCE((SELECT sum(balance_gnf) FROM public.wallets WHERE owner_user_id=u_succ),0) = 0, NULL);
  r := r || public._qa_s13_ok('N5DL.H4 the liability still belongs to the predecessor UUID',
        (SELECT count(*) FROM public.dormant_closed_account_liabilities WHERE user_id=u_pos) = 1, NULL);

  -- ================= I. IMMUTABILITY + FAIL-CLOSED SETTLEMENT =================
  SELECT id INTO v_id FROM public.dormant_closed_account_liabilities WHERE user_id=u_pos;
  BEGIN
    UPDATE public.dormant_closed_account_liabilities SET amount_gnf = 1 WHERE id = v_id;
    r := r || public._qa_s13_ok('N5DL.I1 the recorded amount can never be edited', false, 'edit accepted');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5DL.I1 the recorded amount can never be edited',
          v_txt LIKE '%DORMANT_LIABILITY_IMMUTABLE%', v_txt);
  END;
  BEGIN
    UPDATE public.dormant_closed_account_liabilities SET user_id = u_succ WHERE id = v_id;
    r := r || public._qa_s13_ok('N5DL.I2 ownership can never be transferred', false, 'transfer accepted');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5DL.I2 ownership can never be transferred',
          v_txt LIKE '%DORMANT_LIABILITY_IMMUTABLE%', v_txt);
  END;
  BEGIN
    UPDATE public.dormant_closed_account_liabilities
       SET state='settled', settlement_evidence_ref='qa-fake-evidence', settled_at=now()
     WHERE id = v_id;
    r := r || public._qa_s13_ok('N5DL.I3 settlement is impossible without a lawful rail', false, 'settlement accepted');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5DL.I3 settlement is impossible without a lawful rail',
          v_txt LIKE '%NO_LAWFUL_SETTLEMENT_RAIL%', v_txt);
  END;
  r := r || public._qa_s13_ok('N5DL.I4 the liability is still dormant after the attempt',
        (SELECT state FROM public.dormant_closed_account_liabilities WHERE id=v_id) = 'dormant', NULL);
  r := r || public._qa_s13_ok('N5DL.I5 the amount survived every attempt unchanged',
        (SELECT amount_gnf FROM public.dormant_closed_account_liabilities WHERE id=v_id) = 29448, NULL);

  -- ================= J. LIVE LEGACY TRUTH =================
  r := r || public._qa_s13_ok('N5DL.J1 every closed account with money has a dormant liability of the exact amount',
        NOT EXISTS (
          SELECT 1 FROM public.wallets w
            JOIN public.profiles p ON p.user_id = w.owner_user_id
           WHERE p.account_status='deleted' AND COALESCE(w.balance_gnf,0) > 0
             AND NOT EXISTS (SELECT 1 FROM public.dormant_closed_account_liabilities d
                              WHERE d.wallet_id = w.id AND d.amount_gnf = w.balance_gnf
                                AND d.state='dormant')), NULL);
  r := r || public._qa_s13_ok('N5DL.J2 no closed account holds funds in escrow',
        NOT EXISTS (SELECT 1 FROM public.wallets w
                      JOIN public.profiles p ON p.user_id=w.owner_user_id
                     WHERE p.account_status='deleted' AND COALESCE(w.held_gnf,0) > 0), NULL);
  r := r || public._qa_s13_ok('N5DL.J3 no dormant liability is recorded against an open account',
        NOT EXISTS (SELECT 1 FROM public.dormant_closed_account_liabilities d
                      JOIN public.profiles p ON p.user_id=d.user_id
                     WHERE p.account_status <> 'deleted'), NULL);

  -- ================= CLEANUP + RESIDUE =================
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM public._qa_node5_fr_cleanup(ids, gen_random_uuid());

  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_pr FROM public.profiles;
  SELECT count(*) INTO a_dc FROM public.dormant_closed_account_liabilities;

  r := r || public._qa_s13_ok('N5DL.K1 ledger postings are untouched', a_lp = b_lp, (a_lp-b_lp)::text);
  r := r || public._qa_s13_ok('N5DL.K2 the ledger sum is untouched', a_ls = b_ls, (a_ls-b_ls)::text);
  r := r || public._qa_s13_ok('N5DL.K3 wallet residue is zero', a_w = b_w, (a_w-b_w)::text);
  r := r || public._qa_s13_ok('N5DL.K4 profile residue is zero', a_pr = b_pr, (a_pr-b_pr)::text);
  r := r || public._qa_s13_ok('N5DL.K5 liability register residue is zero', a_dc = b_dc, (a_dc-b_dc)::text);

  RETURN jsonb_build_object(
    'suite','_qa_node5_finance_dormant_liability',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    PERFORM public._qa_node5_fr_cleanup(ids, gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END
$function$;

REVOKE ALL ON FUNCTION public._qa_node5_finance_dormant_liability() FROM PUBLIC, anon, authenticated;
