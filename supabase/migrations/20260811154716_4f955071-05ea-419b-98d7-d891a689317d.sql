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
      FILTER (WHERE state NOT IN ('settled','reversed')),0) AS payable_outstanding,
    COALESCE(SUM(funded_gnf),0)  AS payable_funded,
    COALESCE(SUM(settled_gnf),0) AS payable_settled,
    count(*) FILTER (WHERE state NOT IN ('settled','reversed')) AS payable_open_count
  FROM public.merchant_payables
),
po AS (
  SELECT
    COALESCE(SUM(reservation_gnf) FILTER (WHERE status NOT IN ('settled','rejected','released')),0) AS reserved,
    count(*)  FILTER (WHERE status NOT IN ('settled','rejected','released')) AS reserved_count,
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
      FILTER (WHERE state NOT IN ('paid','waived','reversed','exempt')),0) AS outstanding,
    COALESCE(SUM(paid_gnf),0)   AS collected,
    COALESCE(SUM(waived_gnf),0) AS waived,
    count(*) FILTER (WHERE state NOT IN ('paid','waived','reversed','exempt')) AS open_count
  FROM public.customer_cancellation_debts
),
cl AS (
  SELECT
    COALESCE(SUM(GREATEST(authorized_gnf - paid_gnf - released_gnf,0))
      FILTER (WHERE state NOT IN ('paid','denied','released','reversed')),0) AS recognized_obligation,
    COALESCE(SUM(declared_value_gnf)
      FILTER (WHERE state NOT IN ('paid','denied','released','reversed')),0) AS open_exposure,
    COALESCE(SUM(paid_gnf),0)     AS paid,
    COALESCE(SUM(released_gnf),0) AS released,
    count(*) FILTER (WHERE state NOT IN ('paid','denied','released','reversed')) AS open_count
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
      SELECT mp.payable_key::text, mp.source_module::text,
             GREATEST(mp.amount_gnf - mp.settled_gnf,0)::bigint, mp.state::text,
             mp.source_module::text, mp.source_id::text, mp.created_at
      FROM public.merchant_payables mp
      WHERE mp.state NOT IN ('settled','reversed')
      ORDER BY mp.created_at DESC LIMIT v_lim;

  ELSIF p_code = 'CLAIM_RESERVE_MISMATCH' THEN
    RETURN QUERY
      SELECT c.claim_key::text, COALESCE(c.reason,'claim')::text,
             GREATEST(c.authorized_gnf - c.paid_gnf - c.released_gnf,0)::bigint, c.state::text,
             c.source_module::text, c.source_id::text, c.created_at
      FROM public.claims_reserves c
      WHERE c.state NOT IN ('paid','denied','released','reversed')
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
