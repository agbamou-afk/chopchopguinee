
-- Rides table for real trip records and driver payouts
CREATE TYPE public.ride_mode AS ENUM ('moto', 'toktok', 'food');
CREATE TYPE public.ride_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled');

CREATE TABLE public.rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL,
  driver_id UUID,
  mode public.ride_mode NOT NULL,
  pickup_lat NUMERIC(10,6) NOT NULL,
  pickup_lng NUMERIC(10,6) NOT NULL,
  dest_lat NUMERIC(10,6),
  dest_lng NUMERIC(10,6),
  fare_gnf BIGINT NOT NULL CHECK (fare_gnf >= 0),
  platform_fee_gnf BIGINT NOT NULL DEFAULT 0,
  driver_earning_gnf BIGINT NOT NULL DEFAULT 0,
  hold_tx_id UUID REFERENCES public.wallet_transactions(id),
  payment_tx_id UUID REFERENCES public.wallet_transactions(id),
  status public.ride_status NOT NULL DEFAULT 'pending',
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX idx_rides_client ON public.rides(client_id, created_at DESC);
CREATE INDEX idx_rides_driver ON public.rides(driver_id, created_at DESC);
CREATE INDEX idx_rides_status ON public.rides(status);

ALTER TABLE public.rides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Clients view own rides" ON public.rides
  FOR SELECT USING (auth.uid() = client_id);
CREATE POLICY "Drivers view assigned rides" ON public.rides
  FOR SELECT USING (auth.uid() = driver_id);
CREATE POLICY "Admins view all rides" ON public.rides
  FOR SELECT USING (public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER trg_rides_updated
BEFORE UPDATE ON public.rides
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Create a ride after a wallet hold has been placed
CREATE OR REPLACE FUNCTION public.ride_create(
  p_mode public.ride_mode,
  p_pickup_lat NUMERIC,
  p_pickup_lng NUMERIC,
  p_dest_lat NUMERIC,
  p_dest_lng NUMERIC,
  p_fare_gnf BIGINT,
  p_hold_tx_id UUID,
  p_driver_id UUID DEFAULT NULL
) RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  INSERT INTO public.rides (
    client_id, driver_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng,
    fare_gnf, hold_tx_id, status
  ) VALUES (
    v_uid, p_driver_id, p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng,
    p_fare_gnf, p_hold_tx_id, 'pending'
  ) RETURNING * INTO v_ride;
  RETURN v_ride;
END;
$$;

-- Complete a ride: capture from hold, split commission, credit driver wallet (or master)
CREATE OR REPLACE FUNCTION public.ride_complete(
  p_ride_id UUID,
  p_actual_fare_gnf BIGINT DEFAULT NULL,
  p_commission_bps INT DEFAULT 1500  -- 15% platform fee
) RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.rides;
  v_fare BIGINT;
  v_platform BIGINT;
  v_driver_earn BIGINT;
  v_payment public.wallet_transactions;
  v_to_party TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status = 'completed' THEN RETURN v_ride; END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;

  v_fare := COALESCE(p_actual_fare_gnf, v_ride.fare_gnf);
  v_platform := (v_fare * p_commission_bps) / 10000;
  v_driver_earn := v_fare - v_platform;

  IF v_ride.driver_id IS NOT NULL THEN
    v_to_party := 'driver';
  ELSE
    v_to_party := 'master';
  END IF;

  -- Capture from the original hold; full fare goes to driver wallet (or master if none)
  SELECT * INTO v_payment FROM public.wallet_capture(
    p_hold_id := v_ride.hold_tx_id,
    p_to_user_id := v_ride.driver_id,
    p_to_party_type := v_to_party,
    p_actual_amount_gnf := v_fare,
    p_description := 'Course ' || v_ride.mode::text
  );

  -- If driver was paid, transfer the platform commission from driver to master
  IF v_ride.driver_id IS NOT NULL AND v_platform > 0 THEN
    PERFORM public.wallet_internal_transfer(
      p_from_user_id := v_ride.driver_id,
      p_from_party_type := 'driver',
      p_to_user_id := NULL,
      p_to_party_type := 'master',
      p_amount_gnf := v_platform,
      p_description := 'Commission course ' || v_ride.id::text
    );
  END IF;

  UPDATE public.rides SET
    status = 'completed',
    fare_gnf = v_fare,
    platform_fee_gnf = v_platform,
    driver_earning_gnf = v_driver_earn,
    payment_tx_id = v_payment.id,
    completed_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  RETURN v_ride;
END;
$$;

-- Cancel ride: release the hold
CREATE OR REPLACE FUNCTION public.ride_cancel(
  p_ride_id UUID,
  p_reason TEXT DEFAULT 'Course annulée'
) RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status IN ('completed','cancelled') THEN RETURN v_ride; END IF;

  IF v_ride.hold_tx_id IS NOT NULL THEN
    PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
  END IF;

  UPDATE public.rides SET status = 'cancelled' WHERE id = p_ride_id RETURNING * INTO v_ride;
  RETURN v_ride;
END;
$$;

-- Helper: internal transfer used for commission split (security definer, no auth.uid check)
CREATE OR REPLACE FUNCTION public.wallet_internal_transfer(
  p_from_user_id UUID,
  p_from_party_type TEXT,
  p_to_user_id UUID,
  p_to_party_type TEXT,
  p_amount_gnf BIGINT,
  p_description TEXT
) RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_from_wallet public.wallets;
  v_to_wallet public.wallets;
  v_tx public.wallet_transactions;
BEGIN
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  SELECT * INTO v_from_wallet FROM public.wallets
    WHERE party_type = p_from_party_type::wallet_party_type
      AND ((p_from_user_id IS NULL AND user_id IS NULL) OR user_id = p_from_user_id)
    FOR UPDATE;
  IF v_from_wallet IS NULL THEN RAISE EXCEPTION 'Source wallet not found'; END IF;
  IF v_from_wallet.balance_gnf - v_from_wallet.held_gnf < p_amount_gnf THEN
    RAISE EXCEPTION 'Insufficient funds';
  END IF;

  SELECT * INTO v_to_wallet FROM public.wallets
    WHERE party_type = p_to_party_type::wallet_party_type
      AND ((p_to_user_id IS NULL AND user_id IS NULL) OR user_id = p_to_user_id)
    FOR UPDATE;
  IF v_to_wallet IS NULL THEN RAISE EXCEPTION 'Destination wallet not found'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - p_amount_gnf WHERE id = v_from_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount_gnf WHERE id = v_to_wallet.id;

  INSERT INTO public.wallet_transactions (
    from_wallet_id, to_wallet_id, amount_gnf, type, status, description
  ) VALUES (
    v_from_wallet.id, v_to_wallet.id, p_amount_gnf, 'transfer', 'completed', p_description
  ) RETURNING * INTO v_tx;

  RETURN v_tx;
END;
$$;
