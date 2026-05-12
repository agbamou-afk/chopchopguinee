
CREATE INDEX IF NOT EXISTS idx_rides_pending_unassigned
  ON public.rides(created_at DESC)
  WHERE status = 'pending' AND driver_id IS NULL;

CREATE OR REPLACE FUNCTION public.ride_accept(p_ride_id uuid)
RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  UPDATE public.rides
     SET driver_id = v_uid, status = 'in_progress'
   WHERE id = p_ride_id
     AND driver_id IS NULL
     AND status = 'pending'
   RETURNING * INTO v_ride;

  IF v_ride.id IS NULL THEN
    RAISE EXCEPTION 'Ride not available';
  END IF;

  -- Ensure driver wallet exists
  INSERT INTO public.wallets (owner_user_id, party_type)
  VALUES (v_uid, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;

  RETURN v_ride;
END;
$$;
