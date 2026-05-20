-- Driver district affinity (lightweight, no dispatch lock)
ALTER TABLE public.driver_profiles
  ADD COLUMN IF NOT EXISTS preferred_district text,
  ADD COLUMN IF NOT EXISTS current_operating_district text,
  ADD COLUMN IF NOT EXISTS last_seen_district text;

-- District-aware issue reporting
ALTER TABLE public.missions
  ADD COLUMN IF NOT EXISTS issue_district text,
  ADD COLUMN IF NOT EXISTS issue_hub_id uuid;

-- District HQ / hub model (future-ready, lightly used)
CREATE TABLE IF NOT EXISTS public.district_hubs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  district text NOT NULL,
  name text NOT NULL,
  partner_type text NOT NULL DEFAULT 'partner',
  address text,
  lat double precision,
  lng double precision,
  phone text,
  available_services text[] NOT NULL DEFAULT '{}'::text[],
  merchant_id uuid,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_district_hubs_district ON public.district_hubs(district);
CREATE INDEX IF NOT EXISTS idx_district_hubs_status ON public.district_hubs(status);

ALTER TABLE public.district_hubs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone read active hubs" ON public.district_hubs;
CREATE POLICY "Anyone read active hubs"
  ON public.district_hubs FOR SELECT
  TO anon, authenticated
  USING (status = 'active' OR can_manage_operations(auth.uid()));

DROP POLICY IF EXISTS "Ops manage hubs" ON public.district_hubs;
CREATE POLICY "Ops manage hubs"
  ON public.district_hubs FOR ALL
  TO authenticated
  USING (can_manage_operations(auth.uid()))
  WITH CHECK (can_manage_operations(auth.uid()));

DROP TRIGGER IF EXISTS trg_district_hubs_updated_at ON public.district_hubs;
CREATE TRIGGER trg_district_hubs_updated_at
  BEFORE UPDATE ON public.district_hubs
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();