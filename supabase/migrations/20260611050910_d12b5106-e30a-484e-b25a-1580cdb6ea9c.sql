
-- =====================================================================
-- Phase 1d: Driver earning backfill + reconciliation (admin-only)
-- =====================================================================

-- ---------- Preview (read-only) ----------
CREATE OR REPLACE FUNCTION public.admin_preview_missing_driver_earnings()
RETURNS TABLE (
  ride_id uuid,
  driver_id uuid,
  client_id uuid,
  fare_gnf bigint,
  platform_fee_gnf bigint,
  driver_earning_gnf bigint,
  calculated_driver_earn_gnf bigint,
  ride_status text,
  completed_at timestamptz,
  hold_tx_id uuid,
  existing_wallet_tx_count integer,
  eligible boolean,
  reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid, 'god_admin'::public.app_role)
    OR public.has_role(v_uid, 'finance_admin'::public.app_role)
    OR public.has_role(v_uid, 'admin'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT r.id AS ride_id,
           r.driver_id,
           r.client_id,
           r.fare_gnf,
           r.platform_fee_gnf,
           r.driver_earning_gnf,
           COALESCE(
             r.driver_earning_gnf,
             GREATEST(r.fare_gnf - COALESCE(r.platform_fee_gnf, 0), 0)
           ) AS calc_earn,
           r.status::text AS ride_status,
           COALESCE(r.completed_at, r.updated_at) AS completed_at,
           r.hold_tx_id,
           (
             SELECT count(*)::int FROM wallet_transactions wt
             WHERE wt.related_entity = 'ride:'||r.id::text
               AND wt.type = 'ride_earning'
           ) AS existing_cnt
    FROM rides r
    WHERE r.status::text = 'completed'
      AND r.driver_id IS NOT NULL
  )
  SELECT b.ride_id, b.driver_id, b.client_id, b.fare_gnf, b.platform_fee_gnf,
         b.driver_earning_gnf, b.calc_earn, b.ride_status, b.completed_at,
         b.hold_tx_id, b.existing_cnt,
         (b.existing_cnt = 0 AND b.calc_earn > 0) AS eligible,
         CASE
           WHEN b.existing_cnt > 0 THEN 'already_credited'
           WHEN b.calc_earn <= 0 THEN 'no_earning_amount'
           ELSE 'eligible'
         END AS reason
  FROM base b
  WHERE b.existing_cnt = 0
  ORDER BY b.completed_at NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_preview_missing_driver_earnings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_missing_driver_earnings() TO authenticated, service_role;

-- ---------- Backfill (mutating, admin-only, idempotent) ----------
CREATE OR REPLACE FUNCTION public.admin_backfill_missing_driver_earnings(
  p_dry_run boolean DEFAULT true,
  p_limit integer DEFAULT 50,
  p_reason text DEFAULT 'Backfill missing driver ride earnings after txn_type enum repair'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_eligible_count int := 0;
  v_total_amount bigint := 0;
  v_credited int := 0;
  v_skipped int := 0;
  v_failed int := 0;
  v_total_credited bigint := 0;
  v_failures jsonb := '[]'::jsonb;
  v_sample jsonb := '[]'::jsonb;
  r RECORD;
  v_wallet_id uuid;
  v_ref text;
  v_existing_id uuid;
  v_new_tx_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid, 'god_admin'::public.app_role)
    OR public.has_role(v_uid, 'finance_admin'::public.app_role)
    OR public.has_role(v_uid, 'admin'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  IF p_limit IS NULL OR p_limit <= 0 OR p_limit > 1000 THEN
    p_limit := 50;
  END IF;

  -- Snapshot eligible totals (full set, not limited)
  SELECT count(*), COALESCE(SUM(calculated_driver_earn_gnf), 0)
    INTO v_eligible_count, v_total_amount
  FROM public.admin_preview_missing_driver_earnings()
  WHERE eligible = true;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'ride_id', ride_id,
            'driver_id', driver_id,
            'amount_gnf', calculated_driver_earn_gnf
         )), '[]'::jsonb)
    INTO v_sample
  FROM (
    SELECT ride_id, driver_id, calculated_driver_earn_gnf
    FROM public.admin_preview_missing_driver_earnings()
    WHERE eligible = true
    LIMIT 5
  ) s;

  IF p_dry_run THEN
    RETURN jsonb_build_object(
      'dry_run', true,
      'eligible_count', v_eligible_count,
      'total_amount_gnf', v_total_amount,
      'limit', p_limit,
      'sample', v_sample
    );
  END IF;

  FOR r IN
    SELECT ride_id, driver_id, calculated_driver_earn_gnf AS amount,
           fare_gnf, driver_earning_gnf
    FROM public.admin_preview_missing_driver_earnings()
    WHERE eligible = true
    ORDER BY completed_at NULLS LAST
    LIMIT p_limit
  LOOP
    BEGIN
      v_ref := 'ride_earning_backfill:'||r.ride_id::text;

      -- Idempotency pre-check
      SELECT id INTO v_existing_id FROM wallet_transactions WHERE reference = v_ref;
      IF v_existing_id IS NOT NULL THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;

      -- Ensure driver wallet exists (party_type='driver', owner=driver_id)
      SELECT id INTO v_wallet_id FROM wallets
        WHERE owner_user_id = r.driver_id AND party_type = 'driver';
      IF v_wallet_id IS NULL THEN
        INSERT INTO wallets (owner_user_id, party_type, balance_gnf)
          VALUES (r.driver_id, 'driver', 0)
        ON CONFLICT (owner_user_id, party_type) DO NOTHING;
        SELECT id INTO v_wallet_id FROM wallets
          WHERE owner_user_id = r.driver_id AND party_type = 'driver';
      END IF;

      IF v_wallet_id IS NULL THEN
        v_failed := v_failed + 1;
        v_failures := v_failures || jsonb_build_object('ride_id', r.ride_id, 'error', 'wallet_missing');
        CONTINUE;
      END IF;

      BEGIN
        INSERT INTO wallet_transactions (
          reference, type, status, amount_gnf,
          to_wallet_id, related_user_id, related_entity, description,
          metadata, completed_at
        ) VALUES (
          v_ref, 'ride_earning', 'completed', r.amount,
          v_wallet_id, r.driver_id, 'ride:'||r.ride_id::text, 'Rattrapage gain course',
          jsonb_build_object(
            'source', 'driver_earning_backfill',
            'ride_id', r.ride_id,
            'driver_id', r.driver_id,
            'fare_gnf', r.fare_gnf,
            'driver_earning_gnf', r.driver_earning_gnf,
            'reason', p_reason,
            'created_by_function', 'admin_backfill_missing_driver_earnings',
            'created_by_admin', v_uid
          ),
          now()
        )
        RETURNING id INTO v_new_tx_id;
      EXCEPTION WHEN unique_violation THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END;

      UPDATE wallets SET balance_gnf = balance_gnf + r.amount, updated_at = now()
       WHERE id = v_wallet_id;

      v_credited := v_credited + 1;
      v_total_credited := v_total_credited + r.amount;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;
      v_failures := v_failures || jsonb_build_object('ride_id', r.ride_id, 'error', SQLERRM);
    END;
  END LOOP;

  -- Audit log
  BEGIN
    INSERT INTO audit_logs (actor_user_id, actor_role, module, action, target_type, after, note)
    VALUES (
      v_uid, 'admin', 'wallet', 'driver_earning_backfill', 'wallet_transactions',
      jsonb_build_object(
        'credited', v_credited,
        'skipped', v_skipped,
        'failed', v_failed,
        'total_credited_gnf', v_total_credited,
        'eligible_total', v_eligible_count,
        'limit', p_limit
      ),
      p_reason
    );
  EXCEPTION WHEN OTHERS THEN
    NULL; -- never let audit failure block the result
  END;

  RETURN jsonb_build_object(
    'dry_run', false,
    'eligible_count_before', v_eligible_count,
    'total_amount_eligible_gnf', v_total_amount,
    'credited', v_credited,
    'skipped_already_credited', v_skipped,
    'failed', v_failed,
    'total_credited_gnf', v_total_credited,
    'remaining_missing', GREATEST(v_eligible_count - v_credited - v_skipped, 0),
    'failures', v_failures
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_backfill_missing_driver_earnings(boolean, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_backfill_missing_driver_earnings(boolean, integer, text) TO authenticated, service_role;
