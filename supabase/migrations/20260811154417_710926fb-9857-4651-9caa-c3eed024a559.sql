CREATE OR REPLACE FUNCTION public.finance_treasury_exceptions()
RETURNS TABLE (
  code text, severity text, amount_gnf bigint, entity_count int,
  source_module text, account_code text, detail text,
  state text, occurred_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  f jsonb; v_now timestamptz := now();
  v_assets bigint; v_cust bigint; v_drv bigint; v_mer bigint; v_promo bigint; v_covered bigint; v_d bigint;
BEGIN
  PERFORM public._finance_treasury_gate();
  f := public._finance_treasury_facts();

  v_assets := (f#>>'{om_topups,credited}')::bigint - (f#>>'{payout_orders,settled_out}')::bigint;
  v_cust   := (f#>>'{wallets,client_bal}')::bigint   + (f#>>'{wallets,client_held}')::bigint;
  v_drv    := (f#>>'{wallets,driver_bal}')::bigint   + (f#>>'{wallets,driver_held}')::bigint;
  v_mer    := (f#>>'{wallets,merchant_bal}')::bigint + (f#>>'{wallets,merchant_held}')::bigint
              + (f#>>'{payables,payable_outstanding}')::bigint;
  v_promo  := (f#>>'{promo,outstanding}')::bigint;
  v_covered := v_cust + v_drv + v_mer - v_promo;

  v_d := v_assets - v_covered;
  IF v_d < 0 THEN
    RETURN QUERY SELECT 'TREASURY_SHORTFALL','critical',v_d,1,'treasury',NULL::text,
      'Verified provider-backed assets are below recorded cash-backed obligations.','open',v_now;
  ELSIF v_d > 0 THEN
    RETURN QUERY SELECT 'TREASURY_SURPLUS','warning',v_d,1,'treasury',NULL::text,
      'Verified provider-backed assets exceed recorded cash-backed obligations.','open',v_now;
  END IF;

  v_d := v_cust - ((f#>>'{ledger,l_customer}')::bigint + (f#>>'{ledger,l_customer_hold}')::bigint);
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'WALLET_LEDGER_MISMATCH','critical',v_d,1,'chop_pay','L_CUSTOMER_CHOPPAY',
      'Customer wallet balances differ from the customer liability ledger account.','open',v_now;
  END IF;
  v_d := v_drv - (f#>>'{ledger,l_driver}')::bigint;
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'WALLET_LEDGER_MISMATCH','critical',v_d,1,'driver','L_DRIVER_UNRESTRICTED',
      'Driver wallet balances differ from the driver liability ledger accounts.','open',v_now;
  END IF;
  v_d := (f#>>'{wallets,merchant_bal}')::bigint + (f#>>'{wallets,merchant_held}')::bigint;
  IF v_d <> 0 AND (f#>>'{ledger,posting_count}')::int = 0 THEN
    RETURN QUERY SELECT 'WALLET_LEDGER_MISMATCH','critical',v_d,1,'merchant','L_MERCHANT_PAYABLE',
      'Merchant wallet balances exist with no corresponding ledger postings.','open',v_now;
  END IF;

  v_d := (f#>>'{wallets,master_bal}')::bigint;
  IF v_d < 0 THEN
    RETURN QUERY SELECT 'MASTER_WALLET_DEFICIT','high',v_d,1,'treasury','EQ_PLATFORM',
      'DEF-FIN-001: platform master wallet carries a pre-ledger negative balance. Frozen by policy; do not normalize.','acknowledged',v_now;
  END IF;

  v_d := (f#>>'{payables,payable_outstanding}')::bigint - (f#>>'{ledger,l_merchant_payable}')::bigint;
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'MERCHANT_PAYABLE_MISMATCH','critical',v_d,
      (f#>>'{payables,payable_open_count}')::int,'merchant','L_MERCHANT_PAYABLE',
      'Outstanding merchant payables differ from the merchant payable ledger account.','open',v_now;
  END IF;

  v_d := (f#>>'{claims,recognized_obligation}')::bigint - (f#>>'{ledger,l_claims_reserve}')::bigint;
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'CLAIM_RESERVE_MISMATCH','high',v_d,
      (f#>>'{claims,open_count}')::int,'envoyer','L_CLAIMS_RESERVE',
      'Recognized claims obligation differs from the claims reserve ledger account.','open',v_now;
  END IF;

  v_d := v_assets - (f#>>'{ledger,a_provider_clearing}')::bigint;
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'PROVIDER_CLEARING_MISMATCH','high',v_d,1,'orange_money','A_PROVIDER_CLEARING',
      'Net provider-confirmed cash differs from the provider clearing ledger account.','open',v_now;
  END IF;

  IF (f#>>'{om_topups,unreconciled_count}')::int > 0 THEN
    RETURN QUERY SELECT 'INBOUND_OM_UNRECONCILED','high',
      (f#>>'{om_topups,unreconciled}')::bigint,(f#>>'{om_topups,unreconciled_count}')::int,
      'orange_money',NULL::text,
      'Inbound Orange Money top-ups awaiting review/match. No wallet credit has been made.','open',v_now;
  END IF;
  IF (f#>>'{om_events,unmatched_count}')::int > 0 THEN
    RETURN QUERY SELECT 'INBOUND_OM_UNMATCHED_EVENT','warning',
      (f#>>'{om_events,unmatched}')::bigint,(f#>>'{om_events,unmatched_count}')::int,
      'orange_money',NULL::text,
      'Provider events recorded without a completed match/credit decision.','open',v_now;
  END IF;

  IF (f#>>'{payout_evidence,unrecon_count}')::int > 0 THEN
    RETURN QUERY SELECT 'OUTBOUND_PAYOUT_UNRECONCILED','high',
      (f#>>'{payout_evidence,unrecon_amount}')::bigint,(f#>>'{payout_evidence,unrecon_count}')::int,
      'payouts',NULL::text,
      'Outbound payout evidence pending or mismatched. No merchant payable has been debited.','open',v_now;
  END IF;

  IF (f#>>'{ledger,ledger_global_sum}')::bigint <> 0 THEN
    RETURN QUERY SELECT 'LEDGER_GLOBAL_IMBALANCE','critical',
      (f#>>'{ledger,ledger_global_sum}')::bigint,1,'ledger',NULL::text,
      'Global ledger postings do not sum to zero.','open',v_now;
  END IF;

  RETURN QUERY
  SELECT 'LEDGER_JOURNAL_IMBALANCE'::text, 'critical'::text, s.sum_gnf::bigint, 1,
         'ledger'::text, NULL::text,
         ('Journal '||s.journal_key||' does not sum to zero.')::text, 'open'::text, s.created_at
  FROM (
    SELECT j.journal_key, j.created_at, COALESCE(SUM(p.amount_gnf),0)::bigint AS sum_gnf
    FROM public.ledger_journals j
    LEFT JOIN public.ledger_postings p ON p.journal_id = j.id
    GROUP BY j.journal_key, j.created_at
    HAVING COALESCE(SUM(p.amount_gnf),0) <> 0
  ) s;
END;
$$;

REVOKE ALL ON FUNCTION public.finance_treasury_exceptions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_treasury_exceptions() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.finance_treasury_drilldown(p_code text, p_limit int DEFAULT 50)
RETURNS TABLE (
  ref text, label text, amount_gnf bigint, state text,
  source_module text, source_ref text, occurred_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_lim int := LEAST(GREATEST(COALESCE(p_limit,50),1),200);
BEGIN
  PERFORM public._finance_treasury_gate();

  IF p_code = 'INBOUND_OM_UNRECONCILED' THEN
    RETURN QUERY
      SELECT t.reference::text, COALESCE(t.review_reason,'awaiting match')::text, t.amount_gnf::bigint,
             t.status::text, 'orange_money'::text, t.id::text, t.created_at
      FROM public.topup_requests t
      WHERE t.status IN ('needs_review','matched')
        AND COALESCE(t.environment,'production')='production'
      ORDER BY t.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'INBOUND_OM_UNMATCHED_EVENT' THEN
    RETURN QUERY
      SELECT e.provider_transaction_id::text, COALESCE(e.notes,e.event_type)::text, e.amount_gnf::bigint,
             e.processing_status::text, 'orange_money'::text, e.id::text, e.created_at
      FROM public.payment_provider_events e
      WHERE COALESCE(e.is_sandbox,false)=false
        AND e.processing_status NOT IN ('processed','credited','ignored')
      ORDER BY e.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'OUTBOUND_PAYOUT_UNRECONCILED' THEN
    RETURN QUERY
      SELECT ev.normalized_reference::text, COALESCE(ev.mismatch_reason, ev.provider_status)::text,
             ev.amount_gnf::bigint, ev.reconciliation_state::text, 'payouts'::text,
             ev.payout_order_id::text, ev.created_at
      FROM public.payout_provider_evidence ev
      WHERE ev.reconciliation_state <> 'reconciled'
      ORDER BY ev.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'MERCHANT_PAYABLE_MISMATCH' THEN
    RETURN QUERY
      SELECT mp.payable_key::text, COALESCE(mp.mission_type::text, mp.source_module)::text,
             GREATEST(mp.amount_gnf - mp.settled_gnf,0)::bigint, mp.state::text,
             mp.source_module::text, mp.source_id::text, mp.created_at
      FROM public.merchant_payables mp
      WHERE mp.state NOT IN ('settled','reversed','cancelled')
      ORDER BY mp.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'CLAIM_RESERVE_MISMATCH' THEN
    RETURN QUERY
      SELECT c.claim_key::text, COALESCE(c.reason,'claim')::text,
             GREATEST(c.authorized_gnf - c.paid_gnf - c.released_gnf,0)::bigint, c.state::text,
             c.source_module::text, c.source_id::text, c.created_at
      FROM public.claims_reserves c
      WHERE c.state NOT IN ('settled','released','rejected','cancelled')
      ORDER BY c.created_at DESC LIMIT v_lim;

  ELSIF p_code IN ('LEDGER_JOURNAL_IMBALANCE','LEDGER_GLOBAL_IMBALANCE') THEN
    RETURN QUERY
      SELECT j.journal_key::text, COALESCE(j.action,'journal')::text,
             COALESCE(SUM(p.amount_gnf),0)::bigint,
             (CASE WHEN COALESCE(SUM(p.amount_gnf),0)=0 THEN 'balanced' ELSE 'imbalanced' END)::text,
             j.source_module::text, j.source_id::text, j.created_at
      FROM public.ledger_journals j
      LEFT JOIN public.ledger_postings p ON p.journal_id=j.id
      GROUP BY j.journal_key, j.action, j.source_module, j.source_id, j.created_at
      HAVING COALESCE(SUM(p.amount_gnf),0) <> 0
      ORDER BY j.created_at DESC LIMIT v_lim;

  ELSIF p_code IN ('TREASURY_SHORTFALL','TREASURY_SURPLUS','WALLET_LEDGER_MISMATCH',
                   'MASTER_WALLET_DEFICIT','PROVIDER_CLEARING_MISMATCH') THEN
    RETURN QUERY
      SELECT w.party_type::text, 'wallet class'::text, SUM(w.balance_gnf)::bigint,
             'balance'::text, 'chop_pay'::text, NULL::text, MAX(w.updated_at)
      FROM public.wallets w GROUP BY w.party_type
      UNION ALL
      SELECT lp.account_code::text, 'ledger account'::text, SUM(lp.amount_gnf)::bigint,
             'posted'::text, 'ledger'::text, NULL::text, MAX(lp.created_at)
      FROM public.ledger_postings lp GROUP BY lp.account_code;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.finance_treasury_drilldown(text,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_treasury_drilldown(text,int) TO authenticated, service_role;
