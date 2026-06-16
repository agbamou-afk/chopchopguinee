
-- =========================================================================
-- CHOP Maps Phase 2A — canonical map_* namespace
-- Idempotent: safe to rerun across environments.
-- =========================================================================

-- 1. Shared verification enum (idempotent)
DO $$ BEGIN
  CREATE TYPE public.map_verification_status AS ENUM (
    'unverified','submitted','field_checked','admin_verified',
    'trusted','needs_review','duplicate','closed'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. Default confidence helper
CREATE OR REPLACE FUNCTION public.map_default_confidence(_status public.map_verification_status)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE _status
    WHEN 'unverified'      THEN 20
    WHEN 'submitted'       THEN 35
    WHEN 'field_checked'   THEN 60
    WHEN 'admin_verified'  THEN 80
    WHEN 'trusted'         THEN 95
    WHEN 'needs_review'    THEN 30
    WHEN 'duplicate'       THEN 10
    WHEN 'closed'          THEN 0
    ELSE 20
  END
$$;

-- =========================================================================
-- map_service_zones
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.map_service_zones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  commune text,
  district text,
  center_lat double precision,
  center_lng double precision,
  radius_meters integer,
  boundary_geojson jsonb,
  status text NOT NULL DEFAULT 'pilot'
    CHECK (status IN ('pilot','active','paused','inactive','needs_review')),
  priority text NOT NULL DEFAULT 'normal'
    CHECK (priority IN ('low','normal','high','critical')),
  services_enabled jsonb NOT NULL DEFAULT
    '{"moto":false,"repas":false,"marche":false,"envoyer":false,"agents":false}'::jsonb,
  verification_status public.map_verification_status NOT NULL DEFAULT 'unverified',
  confidence_score integer NOT NULL DEFAULT 20 CHECK (confidence_score BETWEEN 0 AND 100),
  ops_notes text,
  driver_notes text,
  merchant_notes text,
  coverage_notes text,
  verified_by uuid,
  verified_at timestamptz,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.map_service_zones TO authenticated;
GRANT SELECT ON public.map_service_zones TO anon;
GRANT ALL ON public.map_service_zones TO service_role;

ALTER TABLE public.map_service_zones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS msz_public_read ON public.map_service_zones;
CREATE POLICY msz_public_read ON public.map_service_zones
  FOR SELECT TO anon, authenticated
  USING (status IN ('active','pilot'));

DROP POLICY IF EXISTS msz_admin_read ON public.map_service_zones;
CREATE POLICY msz_admin_read ON public.map_service_zones
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS msz_admin_write ON public.map_service_zones;
CREATE POLICY msz_admin_write ON public.map_service_zones
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE INDEX IF NOT EXISTS idx_msz_status         ON public.map_service_zones(status);
CREATE INDEX IF NOT EXISTS idx_msz_priority       ON public.map_service_zones(priority);
CREATE INDEX IF NOT EXISTS idx_msz_verification   ON public.map_service_zones(verification_status);
CREATE INDEX IF NOT EXISTS idx_msz_commune        ON public.map_service_zones(commune);
CREATE INDEX IF NOT EXISTS idx_msz_district       ON public.map_service_zones(district);

DROP TRIGGER IF EXISTS trg_msz_updated_at ON public.map_service_zones;
CREATE TRIGGER trg_msz_updated_at
  BEFORE UPDATE ON public.map_service_zones
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =========================================================================
-- map_places
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.map_places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  aliases text[] NOT NULL DEFAULT ARRAY[]::text[],
  category text,
  commune text,
  neighborhood text,
  lat double precision,
  lng double precision,
  source text,
  verification_status public.map_verification_status NOT NULL DEFAULT 'unverified',
  confidence_score integer NOT NULL DEFAULT 20 CHECK (confidence_score BETWEEN 0 AND 100),
  verified_by uuid,
  verified_at timestamptz,
  last_reported_at timestamptz,
  duplicate_of uuid REFERENCES public.map_places(id) ON DELETE SET NULL,
  pickup_note text,
  entrance_note text,
  landmark_note text,
  operational_note text,
  active boolean NOT NULL DEFAULT true,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.map_places TO authenticated;
GRANT SELECT ON public.map_places TO anon;
GRANT ALL ON public.map_places TO service_role;

ALTER TABLE public.map_places ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mp_public_read ON public.map_places;
CREATE POLICY mp_public_read ON public.map_places
  FOR SELECT TO anon, authenticated
  USING (active = true);

DROP POLICY IF EXISTS mp_admin_read ON public.map_places;
CREATE POLICY mp_admin_read ON public.map_places
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS mp_admin_write ON public.map_places;
CREATE POLICY mp_admin_write ON public.map_places
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE INDEX IF NOT EXISTS idx_mp_category        ON public.map_places(category);
CREATE INDEX IF NOT EXISTS idx_mp_commune         ON public.map_places(commune);
CREATE INDEX IF NOT EXISTS idx_mp_neighborhood    ON public.map_places(neighborhood);
CREATE INDEX IF NOT EXISTS idx_mp_verification    ON public.map_places(verification_status);
CREATE INDEX IF NOT EXISTS idx_mp_confidence      ON public.map_places(confidence_score);
CREATE INDEX IF NOT EXISTS idx_mp_active          ON public.map_places(active);
CREATE INDEX IF NOT EXISTS idx_mp_duplicate_of    ON public.map_places(duplicate_of);

DROP TRIGGER IF EXISTS trg_mp_updated_at ON public.map_places;
CREATE TRIGGER trg_mp_updated_at
  BEFORE UPDATE ON public.map_places
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =========================================================================
-- map_driver_reports  (admin + reporter only)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.map_driver_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id uuid REFERENCES public.map_places(id) ON DELETE SET NULL,
  zone_id  uuid REFERENCES public.map_service_zones(id) ON DELETE SET NULL,
  reporter_id uuid,
  report_type text NOT NULL
    CHECK (report_type IN (
      'wrong_location','closed','duplicate','missing_entrance',
      'unsafe_pickup','name_incorrect','other'
    )),
  notes text,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','reviewed','resolved','dismissed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  resolved_by uuid
);

-- No anon read. No broad delete to authenticated.
GRANT SELECT, INSERT, UPDATE ON public.map_driver_reports TO authenticated;
GRANT ALL ON public.map_driver_reports TO service_role;

ALTER TABLE public.map_driver_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mdr_admin_read ON public.map_driver_reports;
CREATE POLICY mdr_admin_read ON public.map_driver_reports
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS mdr_reporter_read_own ON public.map_driver_reports;
CREATE POLICY mdr_reporter_read_own ON public.map_driver_reports
  FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());

DROP POLICY IF EXISTS mdr_reporter_insert ON public.map_driver_reports;
CREATE POLICY mdr_reporter_insert ON public.map_driver_reports
  FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS mdr_admin_update ON public.map_driver_reports;
CREATE POLICY mdr_admin_update ON public.map_driver_reports
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE INDEX IF NOT EXISTS idx_mdr_place_id    ON public.map_driver_reports(place_id);
CREATE INDEX IF NOT EXISTS idx_mdr_zone_id     ON public.map_driver_reports(zone_id);
CREATE INDEX IF NOT EXISTS idx_mdr_reporter    ON public.map_driver_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_mdr_status      ON public.map_driver_reports(status);
CREATE INDEX IF NOT EXISTS idx_mdr_report_type ON public.map_driver_reports(report_type);
CREATE INDEX IF NOT EXISTS idx_mdr_created_at  ON public.map_driver_reports(created_at DESC);

-- Trigger: review pressure, not automatic truth
CREATE OR REPLACE FUNCTION public.map_driver_report_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.place_id IS NOT NULL THEN
    UPDATE public.map_places
       SET last_reported_at = now(),
           verification_status = CASE
             WHEN verification_status IN ('unverified','submitted','field_checked')
               THEN 'needs_review'::public.map_verification_status
             ELSE verification_status
           END
     WHERE id = NEW.place_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mdr_on_insert ON public.map_driver_reports;
CREATE TRIGGER trg_mdr_on_insert
  AFTER INSERT ON public.map_driver_reports
  FOR EACH ROW EXECUTE FUNCTION public.map_driver_report_on_insert();

-- =========================================================================
-- map_fare_troncons  (admin-only / internal reference)
-- =========================================================================
CREATE TABLE IF NOT EXISTS public.map_fare_troncons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  departure_name text NOT NULL,
  destination_name text NOT NULL,
  raw_departure_name text NOT NULL,
  raw_destination_name text NOT NULL,
  departure_place_id uuid REFERENCES public.map_places(id) ON DELETE SET NULL,
  destination_place_id uuid REFERENCES public.map_places(id) ON DELETE SET NULL,
  day_price_gnf integer,
  night_price_gnf integer,
  source text,
  source_type text NOT NULL DEFAULT 'field_observed',
  collected_by uuid,
  collected_at timestamptz NOT NULL DEFAULT now(),
  verification_status public.map_verification_status NOT NULL DEFAULT 'submitted',
  confidence_score integer NOT NULL DEFAULT 60 CHECK (confidence_score BETWEEN 0 AND 100),
  is_bidirectional boolean NOT NULL DEFAULT true,
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Internal/admin-only. No anon, no broad authenticated read.
GRANT SELECT, INSERT, UPDATE ON public.map_fare_troncons TO authenticated;
GRANT ALL ON public.map_fare_troncons TO service_role;

ALTER TABLE public.map_fare_troncons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mft_admin_read ON public.map_fare_troncons;
CREATE POLICY mft_admin_read ON public.map_fare_troncons
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS mft_admin_write ON public.map_fare_troncons;
CREATE POLICY mft_admin_write ON public.map_fare_troncons
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_mft_unique_raw
  ON public.map_fare_troncons (lower(raw_departure_name), lower(raw_destination_name));
CREATE INDEX IF NOT EXISTS idx_mft_dep_place    ON public.map_fare_troncons(departure_place_id);
CREATE INDEX IF NOT EXISTS idx_mft_dest_place   ON public.map_fare_troncons(destination_place_id);
CREATE INDEX IF NOT EXISTS idx_mft_verification ON public.map_fare_troncons(verification_status);
CREATE INDEX IF NOT EXISTS idx_mft_active       ON public.map_fare_troncons(is_active);

DROP TRIGGER IF EXISTS trg_mft_updated_at ON public.map_fare_troncons;
CREATE TRIGGER trg_mft_updated_at
  BEFORE UPDATE ON public.map_fare_troncons
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =========================================================================
-- Seed: 40 field-observed Conakry moto tronçons (idempotent)
-- =========================================================================
INSERT INTO public.map_fare_troncons
  (departure_name, destination_name, raw_departure_name, raw_destination_name,
   day_price_gnf, night_price_gnf, source, source_type,
   verification_status, confidence_score, is_bidirectional, is_active)
VALUES
  ('Km36','Lansanayah Barrage','Km36','Lansanayah Barrage',7000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Lansanayah Barrage','Dabompa','Lansanayah Barrage','Dabompa',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Dabompa','Tombolia','Dabompa','Tombolia',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Tombolia','Enta','Tombolia','Enta',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Enta','Kissosso','Enta','Kissosso',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Kissosso','Sangoyah','Kissosso','Sangoyah',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Sangoyah','Matoto','Sangoyah','Matoto',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Matoto','Tannerie','Matoto','Tannerie',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Tannerie','Yimbayah','Tannerie','Yimbayah',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Yimbayah','Aéroport','Yimbayah','Aeroport',7000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Aéroport','Gbessia','Aeroport','Gbessia',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Gbessia','Bonfi','Gbessia','Bonfi',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Bonfi','Kenien','Bonfi','Kenien',7000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Kenien','Madina','Kenien','Madina',5000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Madina','Coleyah','Madina','Coleyah',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Coleyah','En Ville','Coleyah','En Ville',10000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Aéroport','Kipé','Aeroport','Kipe',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Kipé','Nongo','Kipe','Nongo',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Nongo','Lambanyi','Nongo','Lambanyi',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Lambanyi','Foula Madina','Lambanyi','Foula Madina',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Foula Madina','Yatayah','Foula Madina','Yatayah',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Yatayah','Cobayah','Yatayah','Cobayah',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Cobayah','Sonfonia','Cobayah','Sonfonia',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('UGLC','T7','UGLC','T7',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('T7','Tombolia','T7','Tombolia',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('T7','T8','T7','T8',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('T8','Cimenterie','T8','Cimenterie',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Cimenterie','T10','Cimenterie','T10',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('T10','Kagbelen','T10','Kagbelen',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Kagbelen','Km6','Kagbelen','Km6',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Lansanayah Barrage','Cimenterie','Lansanayah Barrage','Cimenterie',3000,5000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Kissosso','T5','Kissosso','T5',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Sangoyah','Enco5','Sangoyah','Enco5',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Enco5','T5','Enco5','T5',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('T5','T6','T5','T6',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('T6','T7','T6','T7',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Tannerie','Cosa','Tannerie','Cosa',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Aéroport','Bambeto','Aeroport','Bambeto',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Gbessia','Hamdallaye','Gbessia','Hamdallaye',10000,15000,'field_conakry_2026','field_observed','submitted',60,true,true),
  ('Kenien','Belle-vue','Kenien','Belle-vue',5000,10000,'field_conakry_2026','field_observed','submitted',60,true,true)
ON CONFLICT (lower(raw_departure_name), lower(raw_destination_name)) DO NOTHING;
