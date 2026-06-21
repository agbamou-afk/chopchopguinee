
-- =====================================================================
-- 1) Master wallet singleton
-- =====================================================================

-- Enforce single master wallet row.
CREATE UNIQUE INDEX IF NOT EXISTS wallets_singleton_master
  ON public.wallets ((true)) WHERE party_type = 'master';

CREATE OR REPLACE FUNCTION public.wallet_ensure_master()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.wallets WHERE party_type = 'master' LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type, status)
    VALUES (NULL, 'master', 'active')
    ON CONFLICT DO NOTHING
    RETURNING id INTO v_id;
    IF v_id IS NULL THEN
      SELECT id INTO v_id FROM public.wallets WHERE party_type = 'master' LIMIT 1;
    END IF;
  END IF;
  RETURN v_id;
END $$;

REVOKE ALL ON FUNCTION public.wallet_ensure_master() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wallet_ensure_master() TO authenticated, service_role;

SELECT public.wallet_ensure_master();

CREATE OR REPLACE FUNCTION public.wallet_get_master_balance()
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance bigint;
BEGIN
  IF v_uid IS NULL OR NOT public.is_god_admin(v_uid) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  SELECT balance_gnf INTO v_balance FROM public.wallets WHERE party_type = 'master' LIMIT 1;
  RETURN COALESCE(v_balance, 0);
END $$;

REVOKE ALL ON FUNCTION public.wallet_get_master_balance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.wallet_get_master_balance() TO authenticated, service_role;

-- Tighten wallets RLS so only god admins can see/manage the master wallet row.
DROP POLICY IF EXISTS "Admins view all wallets" ON public.wallets;
DROP POLICY IF EXISTS "Admins manage wallets" ON public.wallets;

CREATE POLICY "Admins view non-master wallets"
  ON public.wallets FOR SELECT
  USING (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    AND party_type <> 'master'
  );

CREATE POLICY "God admins view master wallet"
  ON public.wallets FOR SELECT
  USING (
    party_type = 'master' AND public.is_god_admin(auth.uid())
  );

CREATE POLICY "Admins manage non-master wallets"
  ON public.wallets FOR ALL
  USING (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    AND party_type <> 'master'
  )
  WITH CHECK (
    public.has_role(auth.uid(), 'admin'::public.app_role)
    AND party_type <> 'master'
  );

-- =====================================================================
-- 2) ride_cancel with 10% client cancellation fee after driver assigned
-- =====================================================================

CREATE OR REPLACE FUNCTION public.ride_cancel(
  p_ride_id uuid,
  p_reason text DEFAULT 'Course annulée'::text
)
RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_cancelled_by text;
  v_driver_deployed boolean;
  v_fee_gnf bigint := 0;
  v_master_wallet uuid;
  v_fee_tx public.wallet_transactions;
  v_release_status text := 'not_applicable';
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  IF v_ride.client_id = v_uid THEN v_cancelled_by := 'client';
  ELSIF v_ride.driver_id = v_uid THEN v_cancelled_by := 'driver';
  ELSIF public.has_role(v_uid, 'admin') THEN v_cancelled_by := 'admin';
  ELSE RAISE EXCEPTION 'Not authorized'; END IF;

  -- Already terminal: idempotent no-op (still unstick driver presence).
  IF v_ride.status IN ('completed','cancelled') THEN
    IF v_ride.driver_id IS NOT NULL THEN
      UPDATE public.driver_profiles SET presence = 'online', last_seen_at = now()
        WHERE user_id = v_ride.driver_id AND presence = 'on_trip';
    END IF;
    RETURN v_ride;
  END IF;

  -- Ride already in progress: client cannot cancel (driver/admin can).
  IF v_ride.status = 'in_progress' AND v_cancelled_by = 'client' THEN
    RAISE EXCEPTION 'ride_in_progress_cancel_not_allowed';
  END IF;

  v_driver_deployed := (v_ride.driver_id IS NOT NULL);

  -- Client cancellation fee path: 10% to master wallet, remainder released.
  IF v_cancelled_by = 'client'
     AND v_driver_deployed
     AND v_ride.hold_tx_id IS NOT NULL
     AND COALESCE((v_ride.metadata->>'cancellation_fee_gnf')::bigint, 0) = 0
  THEN
    v_fee_gnf := GREATEST(0, ROUND(v_ride.fare_gnf * 0.10)::bigint);
    IF v_fee_gnf > 0 THEN
      BEGIN
        v_master_wallet := public.wallet_ensure_master();
        -- wallet_capture releases the full hold and credits the captured
        -- amount to the master wallet; this both takes the 10% fee and
        -- refunds the remainder of the hold to the client in one step.
        v_fee_tx := public.wallet_capture(
          p_hold_id          := v_ride.hold_tx_id,
          p_to_user_id       := NULL,
          p_to_party_type    := 'master'::public.party_type,
          p_actual_amount_gnf:= v_fee_gnf,
          p_description      := 'Frais d''annulation client CHOPCHOP'
        );
        v_release_status := 'fee_captured';
      EXCEPTION WHEN OTHERS THEN
        -- Fallback to plain release so cancellation never breaks.
        v_release_status := 'fee_capture_error: ' || SQLERRM || ' — fallback release';
        v_fee_gnf := 0;
        BEGIN
          PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        EXCEPTION WHEN OTHERS THEN
          v_release_status := v_release_status || ' — release_error: ' || SQLERRM;
        END;
      END;
    ELSE
      -- Fee rounds to zero (tiny fare): just release.
      BEGIN
        PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        v_release_status := 'released_no_fee';
      EXCEPTION WHEN OTHERS THEN
        v_release_status := 'release_error: ' || SQLERRM;
      END;
    END IF;
  ELSIF v_ride.hold_tx_id IS NOT NULL THEN
    -- No-fee path: original behaviour (driver cancel, admin cancel, or
    -- client cancel before driver assigned).
    BEGIN
      PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
      v_release_status := 'released_or_noop';
    EXCEPTION WHEN OTHERS THEN
      v_release_status := 'release_error: ' || SQLERRM;
    END;
  END IF;

  UPDATE public.ride_offers
     SET status = 'cancelled', responded_at = COALESCE(responded_at, now())
   WHERE ride_id = p_ride_id AND status = 'pending';

  UPDATE public.rides
     SET status = 'cancelled',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'cancelled_by', v_cancelled_by,
           'cancelled_at', to_jsonb(now()),
           'cancel_reason', p_reason,
           'hold_release', v_release_status,
           'cancellation_fee_gnf', v_fee_gnf,
           'cancellation_fee_tx_id', COALESCE(v_fee_tx.id::text, NULL),
           'driver_deployed_at_cancel', v_driver_deployed
         ),
         updated_at = now()
   WHERE id = p_ride_id
   RETURNING * INTO v_ride;

  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence = 'online', last_seen_at = now()
      WHERE user_id = v_ride.driver_id AND presence = 'on_trip';
  END IF;

  IF v_fee_gnf > 0 THEN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_uid, 'wallet', 'cancellation_fee_captured', 'ride', p_ride_id::text,
            jsonb_build_object('fee_gnf', v_fee_gnf, 'fee_tx_id', v_fee_tx.id),
            'Frais d''annulation client collectés par CHOPCHOP');
  END IF;

  RETURN v_ride;
END $$;

-- Grants unchanged from the original ride_cancel definition.
REVOKE ALL ON FUNCTION public.ride_cancel(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ride_cancel(uuid, text) TO authenticated;

-- =====================================================================
-- 3) driver_cashout_requests table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.driver_cashout_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  wallet_id uuid NOT NULL REFERENCES public.wallets(id),
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0 AND amount_gnf % 5000 = 0),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','paid','rejected','cancelled')),
  payout_method text NOT NULL DEFAULT 'orange_money',
  payout_phone text NOT NULL,
  driver_note text,
  admin_note text,
  provider_reference text,
  rejected_reason text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  paid_by uuid,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.driver_cashout_requests TO authenticated;
GRANT ALL    ON public.driver_cashout_requests TO service_role;

ALTER TABLE public.driver_cashout_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Driver reads own cashout requests"
  ON public.driver_cashout_requests FOR SELECT
  USING (driver_user_id = auth.uid());

CREATE POLICY "Finance/God admin reads all cashout requests"
  ON public.driver_cashout_requests FOR SELECT
  USING (public.can_manage_wallet(auth.uid()));

-- No INSERT/UPDATE/DELETE policies: all mutations go through SECURITY
-- DEFINER RPCs below.

CREATE INDEX IF NOT EXISTS driver_cashout_requests_status_idx
  ON public.driver_cashout_requests (status, requested_at DESC);
CREATE INDEX IF NOT EXISTS driver_cashout_requests_driver_idx
  ON public.driver_cashout_requests (driver_user_id, requested_at DESC);

CREATE TRIGGER driver_cashout_requests_touch
  BEFORE UPDATE ON public.driver_cashout_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- =====================================================================
-- 4) Cashout RPCs
-- =====================================================================

CREATE OR REPLACE FUNCTION public.driver_cashout_create_request(
  p_amount_gnf bigint,
  p_payout_phone text,
  p_driver_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.wallets;
  v_pending_total bigint;
  v_available bigint;
  v_id uuid;
  v_phone text := trim(coalesce(p_payout_phone,''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;
  IF p_amount_gnf % 5000 <> 0 THEN
    RAISE EXCEPTION 'amount_must_be_multiple_of_5000';
  END IF;
  IF length(v_phone) < 8 THEN
    RAISE EXCEPTION 'invalid_payout_phone';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'driver'
   FOR UPDATE;
  IF v_wallet.id IS NULL THEN
    RAISE EXCEPTION 'driver_wallet_not_found';
  END IF;

  v_available := GREATEST(0, v_wallet.balance_gnf - v_wallet.held_gnf);

  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_pending_total
    FROM public.driver_cashout_requests
   WHERE driver_user_id = v_uid AND status IN ('pending','approved');

  IF (v_pending_total + p_amount_gnf) > v_available THEN
    RAISE EXCEPTION 'insufficient_available_balance';
  END IF;

  INSERT INTO public.driver_cashout_requests
    (driver_user_id, wallet_id, amount_gnf, payout_phone, driver_note)
  VALUES
    (v_uid, v_wallet.id, p_amount_gnf, v_phone, NULLIF(trim(coalesce(p_driver_note,'')),''))
  RETURNING id INTO v_id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'wallet', 'driver_cashout_requested', 'driver_cashout_request', v_id::text,
          jsonb_build_object('amount_gnf', p_amount_gnf, 'payout_phone', v_phone));

  RETURN v_id;
END $$;

REVOKE ALL ON FUNCTION public.driver_cashout_create_request(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_cashout_create_request(bigint, text, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.driver_cashout_cancel_request(p_id uuid)
RETURNS public.driver_cashout_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req public.driver_cashout_requests;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_req FROM public.driver_cashout_requests WHERE id = p_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_req.driver_user_id <> v_uid THEN RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'not_cancellable'; END IF;

  UPDATE public.driver_cashout_requests
     SET status = 'cancelled', updated_at = now()
   WHERE id = p_id
   RETURNING * INTO v_req;
  RETURN v_req;
END $$;

REVOKE ALL ON FUNCTION public.driver_cashout_cancel_request(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_cashout_cancel_request(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.driver_cashout_reject_request(
  p_id uuid,
  p_reason text
)
RETURNS public.driver_cashout_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req public.driver_cashout_requests;
BEGIN
  IF v_uid IS NULL OR NOT public.can_manage_wallet(v_uid) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  SELECT * INTO v_req FROM public.driver_cashout_requests WHERE id = p_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;
  IF v_req.status NOT IN ('pending','approved') THEN
    RAISE EXCEPTION 'not_rejectable';
  END IF;

  UPDATE public.driver_cashout_requests
     SET status = 'rejected',
         rejected_reason = p_reason,
         reviewed_by = v_uid,
         reviewed_at = now(),
         updated_at = now()
   WHERE id = p_id
   RETURNING * INTO v_req;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_uid, 'wallet', 'driver_cashout_rejected', 'driver_cashout_request', p_id::text,
          jsonb_build_object('amount_gnf', v_req.amount_gnf), p_reason);

  RETURN v_req;
END $$;

REVOKE ALL ON FUNCTION public.driver_cashout_reject_request(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_cashout_reject_request(uuid, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.driver_cashout_mark_paid(
  p_id uuid,
  p_provider_reference text,
  p_admin_note text DEFAULT NULL
)
RETURNS public.driver_cashout_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_req public.driver_cashout_requests;
  v_wallet public.wallets;
  v_available bigint;
  v_ref text;
  v_tx_id uuid;
BEGIN
  IF v_uid IS NULL OR NOT public.can_manage_wallet(v_uid) THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  IF p_provider_reference IS NULL OR length(trim(p_provider_reference)) = 0 THEN
    RAISE EXCEPTION 'provider_reference_required';
  END IF;

  SELECT * INTO v_req FROM public.driver_cashout_requests WHERE id = p_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'not_found'; END IF;

  -- Idempotent: already paid → return as-is, no double debit.
  IF v_req.status = 'paid' THEN RETURN v_req; END IF;

  IF v_req.status NOT IN ('pending','approved') THEN
    RAISE EXCEPTION 'not_payable';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE id = v_req.wallet_id FOR UPDATE;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'driver_wallet_not_found'; END IF;

  v_available := GREATEST(0, v_wallet.balance_gnf - v_wallet.held_gnf);
  IF v_available < v_req.amount_gnf THEN
    RAISE EXCEPTION 'insufficient_balance_at_payout';
  END IF;

  -- Debit driver wallet.
  UPDATE public.wallets
     SET balance_gnf = balance_gnf - v_req.amount_gnf
   WHERE id = v_wallet.id;

  v_ref := 'CC-CO-' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'payout', 'completed', v_req.amount_gnf,
    v_wallet.id, NULL, v_req.driver_user_id,
    'driver_cashout_request:' || v_req.id::text,
    'Versement chauffeur via Orange Money', now(),
    jsonb_build_object(
      'provider_reference', p_provider_reference,
      'payout_phone', v_req.payout_phone,
      'cashout_request_id', v_req.id
    )
  ) RETURNING id INTO v_tx_id;

  UPDATE public.driver_cashout_requests
     SET status = 'paid',
         provider_reference = p_provider_reference,
         admin_note = COALESCE(NULLIF(trim(coalesce(p_admin_note,'')),''), admin_note),
         paid_by = v_uid,
         paid_at = now(),
         reviewed_by = COALESCE(reviewed_by, v_uid),
         reviewed_at = COALESCE(reviewed_at, now()),
         updated_at = now()
   WHERE id = p_id
   RETURNING * INTO v_req;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'wallet', 'driver_cashout_paid', 'driver_cashout_request', p_id::text,
          jsonb_build_object(
            'amount_gnf', v_req.amount_gnf,
            'provider_reference', p_provider_reference,
            'wallet_tx_id', v_tx_id
          ));

  RETURN v_req;
END $$;

REVOKE ALL ON FUNCTION public.driver_cashout_mark_paid(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_cashout_mark_paid(uuid, text, text) TO authenticated;
