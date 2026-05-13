
DO $$ BEGIN
  CREATE TYPE public.rating_direction AS ENUM ('client_to_driver','driver_to_client');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.ride_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id uuid NOT NULL,
  rater_id uuid NOT NULL,
  ratee_id uuid NOT NULL,
  direction public.rating_direction NOT NULL,
  score smallint NOT NULL CHECK (score BETWEEN 1 AND 5),
  comment text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (ride_id, direction)
);

CREATE INDEX IF NOT EXISTS idx_ride_ratings_ratee ON public.ride_ratings(ratee_id);
CREATE INDEX IF NOT EXISTS idx_ride_ratings_ride ON public.ride_ratings(ride_id);

ALTER TABLE public.ride_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Participants read own ratings" ON public.ride_ratings;
CREATE POLICY "Participants read own ratings" ON public.ride_ratings
  FOR SELECT TO authenticated
  USING (
    auth.uid() = rater_id
    OR auth.uid() = ratee_id
    OR EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_ratings.ride_id
        AND (r.client_id = auth.uid() OR r.driver_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "Admins read all ratings" ON public.ride_ratings;
CREATE POLICY "Admins read all ratings" ON public.ride_ratings
  FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));

-- Inserts go through the RPC (security definer), so no INSERT policy.

CREATE OR REPLACE FUNCTION public.ride_rate(
  p_ride_id uuid,
  p_score smallint,
  p_comment text DEFAULT NULL,
  p_direction public.rating_direction DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides%ROWTYPE;
  v_dir public.rating_direction;
  v_ratee uuid;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF p_score IS NULL OR p_score < 1 OR p_score > 5 THEN RAISE EXCEPTION 'score must be 1..5'; END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride not found'; END IF;
  IF v_ride.status <> 'completed' THEN RAISE EXCEPTION 'ride not completed'; END IF;

  IF v_uid = v_ride.client_id THEN
    v_dir := 'client_to_driver'; v_ratee := v_ride.driver_id;
  ELSIF v_uid = v_ride.driver_id THEN
    v_dir := 'driver_to_client'; v_ratee := v_ride.client_id;
  ELSE
    RAISE EXCEPTION 'not a participant';
  END IF;

  IF p_direction IS NOT NULL AND p_direction <> v_dir THEN
    RAISE EXCEPTION 'direction mismatch';
  END IF;
  IF v_ratee IS NULL THEN RAISE EXCEPTION 'no counterpart to rate'; END IF;

  INSERT INTO public.ride_ratings(ride_id, rater_id, ratee_id, direction, score, comment)
  VALUES (p_ride_id, v_uid, v_ratee, v_dir, p_score, NULLIF(btrim(p_comment), ''))
  RETURNING id INTO v_id;

  -- Recompute the driver's average if the rating targets a driver
  IF v_dir = 'client_to_driver' THEN
    UPDATE public.driver_profiles dp
    SET rating = COALESCE((
      SELECT ROUND(AVG(score)::numeric, 2)
      FROM public.ride_ratings
      WHERE ratee_id = dp.user_id AND direction = 'client_to_driver'
    ), 0),
    updated_at = now()
    WHERE dp.user_id = v_ratee;
  END IF;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ride_rate(uuid, smallint, text, public.rating_direction) TO authenticated;
