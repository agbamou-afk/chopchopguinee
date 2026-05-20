-- Driver capabilities
ALTER TABLE public.driver_profiles
  ADD COLUMN IF NOT EXISTS capabilities text[] NOT NULL DEFAULT ARRAY['rides_moto']::text[];

-- Enums for mission system
DO $$ BEGIN
  CREATE TYPE public.mission_type AS ENUM ('ride', 'food_delivery', 'marketplace_delivery', 'package_delivery');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.mission_state AS ENUM (
    'assigned','heading_to_pickup','arrived_pickup','picked_up',
    'heading_to_dropoff','arrived_dropoff','delivered','failed'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Missions table
CREATE TABLE IF NOT EXISTS public.missions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type public.mission_type NOT NULL,
  state public.mission_state NOT NULL DEFAULT 'assigned',
  courier_id uuid,
  customer_id uuid NOT NULL,
  merchant_id uuid,
  pickup_address text,
  pickup_lat double precision,
  pickup_lng double precision,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  payload_summary text,
  estimated_earning_gnf bigint NOT NULL DEFAULT 0,
  estimated_distance_m integer,
  estimated_duration_s integer,
  ref_ride_id uuid,
  ref_food_order_id uuid,
  ref_market_order_id uuid,
  pickup_confirmed_at timestamptz,
  pickup_confirmed_by uuid,
  dropoff_confirmed_at timestamptz,
  dropoff_confirmed_by uuid,
  issue_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_missions_courier ON public.missions(courier_id);
CREATE INDEX IF NOT EXISTS idx_missions_customer ON public.missions(customer_id);
CREATE INDEX IF NOT EXISTS idx_missions_merchant ON public.missions(merchant_id);
CREATE INDEX IF NOT EXISTS idx_missions_state ON public.missions(state);

ALTER TABLE public.missions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Courier reads own missions" ON public.missions
  FOR SELECT USING (auth.uid() = courier_id);

CREATE POLICY "Customer reads own missions" ON public.missions
  FOR SELECT USING (auth.uid() = customer_id);

CREATE POLICY "Merchant reads own missions" ON public.missions
  FOR SELECT USING (auth.uid() = merchant_id);

CREATE POLICY "Admins manage missions" ON public.missions
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Courier updates own mission" ON public.missions
  FOR UPDATE USING (auth.uid() = courier_id)
  WITH CHECK (auth.uid() = courier_id);

CREATE POLICY "Merchant updates own mission" ON public.missions
  FOR UPDATE USING (auth.uid() = merchant_id)
  WITH CHECK (auth.uid() = merchant_id);

CREATE POLICY "Customer updates own mission" ON public.missions
  FOR UPDATE USING (auth.uid() = customer_id)
  WITH CHECK (auth.uid() = customer_id);

-- updated_at trigger
CREATE TRIGGER trg_missions_updated_at
  BEFORE UPDATE ON public.missions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Mission events log
CREATE TABLE IF NOT EXISTS public.mission_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL REFERENCES public.missions(id) ON DELETE CASCADE,
  event text NOT NULL,
  actor_id uuid,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mission_events_mission ON public.mission_events(mission_id);

ALTER TABLE public.mission_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Participants read mission events" ON public.mission_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_events.mission_id
        AND (auth.uid() = m.courier_id OR auth.uid() = m.customer_id OR auth.uid() = m.merchant_id)
    ) OR has_role(auth.uid(), 'admin'::app_role)
  );

CREATE POLICY "Participants insert mission events" ON public.mission_events
  FOR INSERT WITH CHECK (
    auth.uid() = actor_id AND EXISTS (
      SELECT 1 FROM public.missions m
      WHERE m.id = mission_events.mission_id
        AND (auth.uid() = m.courier_id OR auth.uid() = m.customer_id OR auth.uid() = m.merchant_id)
    )
  );

CREATE POLICY "Admins manage mission events" ON public.mission_events
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));