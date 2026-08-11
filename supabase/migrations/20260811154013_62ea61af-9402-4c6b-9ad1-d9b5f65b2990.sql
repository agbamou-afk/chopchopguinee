-- ============================================================
-- SLICE 12 — Treasury, Claims & Finance Operations (READ ONLY)
-- No money movement. No balancing plug. Explicit exceptions only.
-- ============================================================

CREATE OR REPLACE FUNCTION public._finance_treasury_gate()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED:finance_treasury';
  END IF;
  RETURN v_caller;
END;
$$;

REVOKE ALL ON FUNCTION public._finance_treasury_gate() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._finance_treasury_gate() TO authenticated, service_role;

-- ------------------------------------------------------------
-- Canonical fact snapshot (internal, no role gate; callers gate)
-- Every figure below is read verbatim from an authoritative table.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._finance_treasury_facts()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
WITH w AS (
  SELECT
    COALESCE(SUM(balance_gnf) FILTER (WHERE party_type='client'),0)   AS client_bal,
    COALESCE(SUM(held_gnf)    FILTER (WHERE party_type='client'),0)   AS client_held,
    COALESCE(SUM(balance_gnf) FILTER (WHERE party_type='driver'),0)   AS driver_bal,
    COALESCE(SUM(held_gnf)    FILTER (WHERE party_type='driver'),0)   AS driver_held,
    COALESCE(SUM(balance_gnf) FILTER (WHERE party_type='merchant'),0) AS merchant_bal,
    COALESCE(SUM(held_gnf)    FILTER (WHERE party_type='merchant'),0) AS merchant_held,
    COALESCE(SUM(balance_gnf) FILTER (WHERE party_type='master'),0)   AS master_bal,
    COALESCE(SUM(held_gnf)    FILTER (WHERE party_type='master'),0)   AS master_held
  FROM public.wallets
),
lg AS (
  SELECT
    -- Debit-positive convention: liability/revenue accounts carry credit (negative) balances.
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='L_CUSTOMER_CHOPPAY'),0)  AS l_customer,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='L_CUSTOMER_HOLD'),0)     AS l_customer_hold,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code IN
        ('L_DRIVER_UNRESTRICTED','L_DRIVER_PROMO')),0)                             AS l_driver,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='L_DRIVER_PROMO'),0)      AS l_driver_promo,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='L_MERCHANT_PAYABLE'),0)  AS l_merchant_payable,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='L_CLAIMS_RESERVE'),0)    AS l_claims_reserve,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code IN
        ('L_HOLD_CASH_FUNDING','L_HOLD_CASHOUT','L_HOLD_COLLATERAL',
         'L_HOLD_COMMISSION','L_HOLD_PLATFORM_FEE','L_HOLD_SETTLEMENT')),0)        AS l_holds,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='L_HOLD_SETTLEMENT'),0)   AS l_hold_settlement,
    COALESCE( SUM(amount_gnf) FILTER (WHERE account_code='A_PROVIDER_CLEARING'),0) AS a_provider_clearing,
    COALESCE( SUM(amount_gnf) FILTER (WHERE account_code='A_CUSTOMER_DEBT'),0)     AS a_customer_debt,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='R_COMMISSION'),0)        AS r_commission,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='R_TRANSACTION_FEE'),0)   AS r_transaction_fee,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='R_CANCELLATION_FEE'),0)  AS r_cancellation_fee,
    COALESCE(-SUM(amount_gnf) FILTER (WHERE account_code='R_COLLATERAL_LOSS'),0)   AS r_collateral_loss,
    COALESCE( SUM(amount_gnf) FILTER (WHERE account_code='E_CLAIMS'),0)            AS e_claims,
    COALESCE( SUM(amount_gnf) FILTER (WHERE account_code='E_PROVIDER_FEE'),0)      AS e_provider_fee,
    COALESCE( SUM(amount_gnf) FILTER (WHERE account_code='E_PROMOTIONAL_CREDIT'),0) AS e_promo,
    COALESCE( SUM(amount_gnf),0)                                                    AS ledger_global_sum,
    count(*)                                                                        AS posting_count
  FROM public.ledger_postings
),
mp AS (
  SELECT
    COALESCE(SUM(GREATEST(amount_gnf - settled_gnf,0))
      FILTER (WHERE state NOT IN ('settled','reversed','cancelled')),0) AS payable_outstanding,
    COALESCE(SUM(funded_gnf),0)  AS payable_funded,
    COALESCE(SUM(settled_gnf),0) AS payable_settled,
    count(*) FILTER (WHERE state NOT IN ('settled','reversed','cancelled')) AS payable_open_count
  FROM public.merchant_payables
),
po AS (
  SELECT
    COALESCE(SUM(reservation_gnf) FILTER (WHERE status NOT IN ('settled','cancelled','rejected','released')),0) AS reserved,
    count(*)  FILTER (WHERE status NOT IN ('settled','cancelled','rejected','released')) AS reserved_count,
    COALESCE(SUM(settled_gnf),0) AS settled_out,
    count(*)  FILTER (WHERE status = 'settled') AS settled_count
  FROM public.payout_orders
),
pe AS (
  SELECT
    COALESCE(SUM(amount_gnf) FILTER (WHERE reconciliation_state <> 'reconciled'),0) AS unrecon_amount,
    count(*) FILTER (WHERE reconciliation_state <> 'reconciled') AS unrecon_count
  FROM public.payout_provider_evidence
),
cd AS (
  SELECT
    COALESCE(SUM(GREATEST(amount_gnf - paid_gnf - waived_gnf,0))
      FILTER (WHERE state NOT IN ('settled','waived','cancelled')),0) AS outstanding,
    COALESCE(SUM(paid_gnf),0)   AS collected,
    COALESCE(SUM(waived_gnf),0) AS waived,
    count(*) FILTER (WHERE state NOT IN ('settled','waived','cancelled')) AS open_count
  FROM public.customer_cancellation_debts
),
cl AS (
  SELECT
    COALESCE(SUM(GREATEST(authorized_gnf - paid_gnf - released_gnf,0))
      FILTER (WHERE state NOT IN ('settled','released','rejected','cancelled')),0) AS recognized_obligation,
    COALESCE(SUM(declared_value_gnf)
      FILTER (WHERE state NOT IN ('settled','released','rejected','cancelled')),0) AS open_exposure,
    COALESCE(SUM(paid_gnf),0)     AS paid,
    COALESCE(SUM(released_gnf),0) AS released,
    count(*) FILTER (WHERE state NOT IN ('settled','released','rejected','cancelled')) AS open_count
  FROM public.claims_reserves
),
hd AS (
  SELECT
    COALESCE(SUM(GREATEST(amount_gnf - COALESCE(captured_gnf,0) - COALESCE(released_gnf,0),0))
      FILTER (WHERE state = 'held'),0) AS open_holds,
    count(*) FILTER (WHERE state = 'held') AS open_hold_count
  FROM public.mission_financial_holds
),
pr AS (
  SELECT
    COALESCE(SUM(GREATEST(granted_gnf - consumed_gnf - reversed_gnf,0))
      FILTER (WHERE state = 'active'),0) AS outstanding,
    COALESCE(SUM(granted_gnf),0) AS granted,
    count(*) AS grant_count
  FROM public.driver_promo_credits
),
om AS (
  SELECT
    COALESCE(SUM(amount_gnf) FILTER (WHERE status='credited'),0) AS credited,
    COALESCE(SUM(amount_gnf) FILTER (WHERE status IN ('needs_review','matched')),0) AS unreconciled,
    count(*) FILTER (WHERE status IN ('needs_review','matched')) AS unreconciled_count,
    COALESCE(SUM(amount_gnf) FILTER (WHERE status='pending'),0) AS pending
  FROM public.topup_requests
  WHERE COALESCE(environment,'production') = 'production'
),
ev AS (
  SELECT
    COALESCE(SUM(amount_gnf) FILTER (WHERE processing_status NOT IN ('processed','credited','ignored')),0) AS unmatched,
    count(*) FILTER (WHERE processing_status NOT IN ('processed','credited','ignored')) AS unmatched_count
  FROM public.payment_provider_events
  WHERE COALESCE(is_sandbox,false) = false
)
SELECT jsonb_build_object(
  'generated_at', now(),
  'wallets', to_jsonb(w), 'ledger', to_jsonb(lg), 'payables', to_jsonb(mp),
  'payout_orders', to_jsonb(po), 'payout_evidence', to_jsonb(pe),
  'debts', to_jsonb(cd), 'claims', to_jsonb(cl), 'holds', to_jsonb(hd),
  'promo', to_jsonb(pr), 'om_topups', to_jsonb(om), 'om_events', to_jsonb(ev)
)
FROM w, lg, mp, po, pe, cd, cl, hd, pr, om, ev;
$$;

REVOKE ALL ON FUNCTION public._finance_treasury_facts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._finance_treasury_facts() TO service_role;

-- ------------------------------------------------------------
-- finance_treasury_overview() — server-authored KPI block.
-- Frontend renders these fields verbatim.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finance_treasury_overview()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  f jsonb;
  v_assets bigint; v_cust bigint; v_drv bigint; v_mer bigint;
  v_held bigint; v_promo bigint; v_reserved bigint; v_covered bigint;
BEGIN
  PERFORM public._finance_treasury_gate();
  f := public._finance_treasury_facts();

  v_assets := (f#>>'{om_topups,credited}')::bigint - (f#>>'{payout_orders,settled_out}')::bigint;
  v_cust   := (f#>>'{wallets,client_bal}')::bigint   + (f#>>'{wallets,client_held}')::bigint;
  v_drv    := (f#>>'{wallets,driver_bal}')::bigint   + (f#>>'{wallets,driver_held}')::bigint;
  v_mer    := (f#>>'{wallets,merchant_bal}')::bigint + (f#>>'{wallets,merchant_held}')::bigint
              + (f#>>'{payables,payable_outstanding}')::bigint;
  v_held   := (f#>>'{wallets,client_held}')::bigint + (f#>>'{wallets,driver_held}')::bigint
              + (f#>>'{wallets,merchant_held}')::bigint + (f#>>'{holds,open_holds}')::bigint;
  v_promo  := (f#>>'{promo,outstanding}')::bigint;
  v_reserved := (f#>>'{payout_orders,reserved}')::bigint;
  -- Promotional credit is platform-funded, never cash-backed: excluded from covered obligations.
  v_covered := v_cust + v_drv + v_mer - v_promo;

  RETURN jsonb_build_object(
    'generated_at', f->'generated_at',

    -- ASSETS (provider/ledger facts only)
    'verified_assets_gnf', v_assets,
    'om_inbound_credited_gnf', (f#>>'{om_topups,credited}')::bigint,
    'om_outbound_settled_gnf', (f#>>'{payout_orders,settled_out}')::bigint,
    'provider_clearing_ledger_gnf', (f#>>'{ledger,a_provider_clearing}')::bigint,

    -- LIABILITIES / OBLIGATIONS
    'total_customer_liability_gnf', v_cust,
    'total_driver_liability_gnf', v_drv,
    'total_merchant_liability_gnf', v_mer,
    'merchant_wallet_liability_gnf', (f#>>'{wallets,merchant_bal}')::bigint,
    'merchant_payable_outstanding_gnf', (f#>>'{payables,payable_outstanding}')::bigint,
    'restricted_or_held_liability_gnf', v_held,
    'promotional_credit_liability_gnf', v_promo,
    'merchant_settlement_reserved_gnf', v_reserved,
    'merchant_settlement_reserved_count', (f#>>'{payout_orders,reserved_count}')::int,
    'master_wallet_balance_gnf', (f#>>'{wallets,master_bal}')::bigint,
    'master_wallet_held_gnf', (f#>>'{wallets,master_held}')::bigint,

    -- CLAIMS
    'recognized_claims_obligation_gnf', (f#>>'{claims,recognized_obligation}')::bigint,
    'open_claims_exposure_gnf', (f#>>'{claims,open_exposure}')::bigint,
    'claims_paid_gnf', (f#>>'{claims,paid}')::bigint,
    'claims_released_gnf', (f#>>'{claims,released}')::bigint,
    'open_claims_count', (f#>>'{claims,open_count}')::int,

    -- RECEIVABLES
    'cancellation_debt_receivable_gnf', (f#>>'{debts,outstanding}')::bigint,
    'cancellation_debt_collected_gnf', (f#>>'{debts,collected}')::bigint,
    'cancellation_debt_waived_gnf', (f#>>'{debts,waived}')::bigint,
    'cancellation_debt_open_count', (f#>>'{debts,open_count}')::int,

    -- REVENUE (captured only)
    'captured_revenue_gnf',
        (f#>>'{ledger,r_commission}')::bigint + (f#>>'{ledger,r_transaction_fee}')::bigint
      + (f#>>'{ledger,r_cancellation_fee}')::bigint + (f#>>'{ledger,r_collateral_loss}')::bigint,
    'captured_revenue_breakdown', jsonb_build_object(
      'ride_commission_gnf', (f#>>'{ledger,r_commission}')::bigint,
      'transaction_fee_gnf', (f#>>'{ledger,r_transaction_fee}')::bigint,
      'cancellation_fee_gnf', (f#>>'{ledger,r_cancellation_fee}')::bigint,
      'recovered_collateral_gnf', (f#>>'{ledger,r_collateral_loss}')::bigint),

    -- OM / PAYOUT OPS POSTURE
    'inbound_om_unreconciled_gnf', (f#>>'{om_topups,unreconciled}')::bigint,
    'inbound_om_unreconciled_count', (f#>>'{om_topups,unreconciled_count}')::int,
    'inbound_om_pending_gnf', (f#>>'{om_topups,pending}')::bigint,
    'inbound_om_unmatched_events_gnf', (f#>>'{om_events,unmatched}')::bigint,
    'inbound_om_unmatched_events_count', (f#>>'{om_events,unmatched_count}')::int,
    'outbound_payout_unreconciled_gnf', (f#>>'{payout_evidence,unrecon_amount}')::bigint,
    'outbound_payout_unreconciled_count', (f#>>'{payout_evidence,unrecon_count}')::int,

    -- COVERAGE (never forced to zero)
    'covered_obligations_gnf', v_covered,
    'treasury_coverage_delta_gnf', v_assets - v_covered,

    'ledger_posting_count', (f#>>'{ledger,posting_count}')::int,
    'ledger_global_sum_gnf', (f#>>'{ledger,ledger_global_sum}')::bigint
  );
END;
$$;

REVOKE ALL ON FUNCTION public.finance_treasury_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_treasury_overview() TO authenticated, service_role;

-- ------------------------------------------------------------
-- finance_treasury_exceptions() — every unexplained difference,
-- named and quantified. NEVER a balancing plug.
-- ------------------------------------------------------------
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

  -- 1. Treasury coverage
  v_d := v_assets - v_covered;
  IF v_d < 0 THEN
    RETURN QUERY SELECT 'TREASURY_SHORTFALL','critical',v_d,1,'treasury',NULL::text,
      'Verified provider-backed assets are below recorded cash-backed obligations.','open',v_now;
  ELSIF v_d > 0 THEN
    RETURN QUERY SELECT 'TREASURY_SURPLUS','warning',v_d,1,'treasury',NULL::text,
      'Verified provider-backed assets exceed recorded cash-backed obligations.','open',v_now;
  END IF;

  -- 2. Wallet vs ledger, per accounting class
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

  -- 3. Master wallet (DEF-FIN-001) — surfaced, never normalized
  v_d := (f#>>'{wallets,master_bal}')::bigint;
  IF v_d < 0 THEN
    RETURN QUERY SELECT 'MASTER_WALLET_DEFICIT','high',v_d,1,'treasury','EQ_PLATFORM',
      'DEF-FIN-001: platform master wallet carries a pre-ledger negative balance. Frozen by policy; do not normalize.','acknowledged',v_now;
  END IF;

  -- 4. Merchant payable vs ledger
  v_d := (f#>>'{payables,payable_outstanding}')::bigint - (f#>>'{ledger,l_merchant_payable}')::bigint;
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'MERCHANT_PAYABLE_MISMATCH','critical',v_d,
      (f#>>'{payables,payable_open_count}')::int,'merchant','L_MERCHANT_PAYABLE',
      'Outstanding merchant payables differ from the merchant payable ledger account.','open',v_now;
  END IF;

  -- 5. Claims reserve vs ledger
  v_d := (f#>>'{claims,recognized_obligation}')::bigint - (f#>>'{ledger,l_claims_reserve}')::bigint;
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'CLAIM_RESERVE_MISMATCH','high',v_d,
      (f#>>'{claims,open_count}')::int,'envoyer','L_CLAIMS_RESERVE',
      'Recognized claims obligation differs from the claims reserve ledger account.','open',v_now;
  END IF;

  -- 6. Provider clearing vs provider facts
  v_d := v_assets - (f#>>'{ledger,a_provider_clearing}')::bigint;
  IF v_d <> 0 THEN
    RETURN QUERY SELECT 'PROVIDER_CLEARING_MISMATCH','high',v_d,1,'orange_money','A_PROVIDER_CLEARING',
      'Net provider-confirmed cash differs from the provider clearing ledger account.','open',v_now;
  END IF;

  -- 7. Inbound OM awaiting reconciliation (no wallet credit made)
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

  -- 8. Outbound payout evidence not reconciled (no payable debit)
  IF (f#>>'{payout_evidence,unrecon_count}')::int > 0 THEN
    RETURN QUERY SELECT 'OUTBOUND_PAYOUT_UNRECONCILED','high',
      (f#>>'{payout_evidence,unrecon_amount}')::bigint,(f#>>'{payout_evidence,unrecon_count}')::int,
      'payouts',NULL::text,
      'Outbound payout evidence pending or mismatched. No merchant payable has been debited.','open',v_now;
  END IF;

  -- 9. Ledger integrity
  IF (f#>>'{ledger,ledger_global_sum}')::bigint <> 0 THEN
    RETURN QUERY SELECT 'LEDGER_GLOBAL_IMBALANCE','critical',
      (f#>>'{ledger,ledger_global_sum}')::bigint,1,'ledger',NULL::text,
      'Global ledger postings do not sum to zero.','open',v_now;
  END IF;

  RETURN QUERY
  SELECT 'LEDGER_JOURNAL_IMBALANCE','critical', s.sum_gnf, 1, 'ledger', NULL::text,
         'Journal '||s.journal_key||' does not sum to zero.','open', s.created_at
  FROM (
    SELECT j.journal_key, j.created_at, COALESCE(SUM(p.amount_gnf),0) AS sum_gnf
    FROM public.ledger_journals j
    LEFT JOIN public.ledger_postings p ON p.journal_id = j.id
    GROUP BY j.journal_key, j.created_at
    HAVING COALESCE(SUM(p.amount_gnf),0) <> 0
  ) s;
END;
$$;

REVOKE ALL ON FUNCTION public.finance_treasury_exceptions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_treasury_exceptions() TO authenticated, service_role;

-- ------------------------------------------------------------
-- finance_treasury_drilldown(code) — exception -> source records
-- ------------------------------------------------------------
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
      SELECT t.reference, COALESCE(t.review_reason,'awaiting match'), t.amount_gnf, t.status::text,
             'orange_money', t.id::text, t.created_at
      FROM public.topup_requests t
      WHERE t.status IN ('needs_review','matched')
        AND COALESCE(t.environment,'production')='production'
      ORDER BY t.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'INBOUND_OM_UNMATCHED_EVENT' THEN
    RETURN QUERY
      SELECT e.provider_transaction_id, COALESCE(e.notes,e.event_type), e.amount_gnf,
             e.processing_status::text, 'orange_money', e.id::text, e.created_at
      FROM public.payment_provider_events e
      WHERE COALESCE(e.is_sandbox,false)=false
        AND e.processing_status NOT IN ('processed','credited','ignored')
      ORDER BY e.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'OUTBOUND_PAYOUT_UNRECONCILED' THEN
    RETURN QUERY
      SELECT ev.normalized_reference, COALESCE(ev.mismatch_reason, ev.provider_status),
             ev.amount_gnf, ev.reconciliation_state::text, 'payouts', ev.payout_order_id::text, ev.created_at
      FROM public.payout_provider_evidence ev
      WHERE ev.reconciliation_state <> 'reconciled'
      ORDER BY ev.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'MERCHANT_PAYABLE_MISMATCH' THEN
    RETURN QUERY
      SELECT mp.payable_key, COALESCE(mp.mission_type,mp.source_module),
             GREATEST(mp.amount_gnf - mp.settled_gnf,0), mp.state::text,
             mp.source_module, mp.source_id::text, mp.created_at
      FROM public.merchant_payables mp
      WHERE mp.state NOT IN ('settled','reversed','cancelled')
      ORDER BY mp.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'CLAIM_RESERVE_MISMATCH' THEN
    RETURN QUERY
      SELECT c.claim_key, COALESCE(c.reason,'claim'),
             GREATEST(c.authorized_gnf - c.paid_gnf - c.released_gnf,0), c.state::text,
             c.source_module, c.source_id::text, c.created_at
      FROM public.claims_reserves c
      WHERE c.state NOT IN ('settled','released','rejected','cancelled')
      ORDER BY c.created_at DESC LIMIT v_lim;

  ELSIF p_code IN ('LEDGER_JOURNAL_IMBALANCE','LEDGER_GLOBAL_IMBALANCE') THEN
    RETURN QUERY
      SELECT j.journal_key, COALESCE(j.action,'journal'), COALESCE(SUM(p.amount_gnf),0),
             CASE WHEN COALESCE(SUM(p.amount_gnf),0)=0 THEN 'balanced' ELSE 'imbalanced' END,
             j.source_module, j.source_id::text, j.created_at
      FROM public.ledger_journals j
      LEFT JOIN public.ledger_postings p ON p.journal_id=j.id
      GROUP BY j.journal_key, j.action, j.source_module, j.source_id, j.created_at
      HAVING COALESCE(SUM(p.amount_gnf),0) <> 0
      ORDER BY j.created_at DESC LIMIT v_lim;

  ELSIF p_code IN ('TREASURY_SHORTFALL','TREASURY_SURPLUS','WALLET_LEDGER_MISMATCH',
                   'MASTER_WALLET_DEFICIT','PROVIDER_CLEARING_MISMATCH') THEN
    RETURN QUERY
      SELECT w.party_type::text, 'wallet class', SUM(w.balance_gnf)::bigint,
             'balance', 'chop_pay', NULL::text, MAX(w.updated_at)
      FROM public.wallets w GROUP BY w.party_type
      UNION ALL
      SELECT lp.account_code, 'ledger account', SUM(lp.amount_gnf)::bigint,
             'posted', 'ledger', NULL::text, MAX(lp.created_at)
      FROM public.ledger_postings lp GROUP BY lp.account_code;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.finance_treasury_drilldown(text,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_treasury_drilldown(text,int) TO authenticated, service_role;
