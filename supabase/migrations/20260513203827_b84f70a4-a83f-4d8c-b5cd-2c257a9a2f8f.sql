CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TYPE public.saved_place_kind AS ENUM ('home', 'work', 'favorite');

CREATE TABLE public.saved_places (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  kind public.saved_place_kind NOT NULL DEFAULT 'favorite',
  label text NOT NULL,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  landmark_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX saved_places_user_idx ON public.saved_places(user_id);
CREATE UNIQUE INDEX saved_places_user_home_idx ON public.saved_places(user_id) WHERE kind = 'home';
CREATE UNIQUE INDEX saved_places_user_work_idx ON public.saved_places(user_id) WHERE kind = 'work';

ALTER TABLE public.saved_places ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own saved places"
  ON public.saved_places FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins read all saved places"
  ON public.saved_places FOR SELECT TO authenticated
  USING (is_any_admin(auth.uid()));

CREATE TRIGGER trg_saved_places_updated
  BEFORE UPDATE ON public.saved_places
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.landmarks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  aliases text[] NOT NULL DEFAULT '{}',
  category text NOT NULL,
  commune text,
  neighborhood text,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  popularity integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX landmarks_name_trgm ON public.landmarks USING gin (name public.gin_trgm_ops);
CREATE INDEX landmarks_active_idx ON public.landmarks(active) WHERE active;

ALTER TABLE public.landmarks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone read landmarks"
  ON public.landmarks FOR SELECT TO anon, authenticated
  USING (active);

CREATE POLICY "Admins manage landmarks"
  ON public.landmarks FOR ALL TO authenticated
  USING (is_any_admin(auth.uid())) WITH CHECK (is_any_admin(auth.uid()));

CREATE TRIGGER trg_landmarks_updated
  BEFORE UPDATE ON public.landmarks
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.landmarks (name, aliases, category, commune, neighborhood, lat, lng, popularity) VALUES
  ('Rond-point Bambeto', ARRAY['Bambeto'], 'rond_point', 'Ratoma', 'Bambeto', 9.6356, -13.6261, 100),
  ('Rond-point Hamdallaye', ARRAY['Hamdallaye'], 'rond_point', 'Ratoma', 'Hamdallaye', 9.5828, -13.6481, 95),
  ('Rond-point Cosa', ARRAY['Cosa'], 'rond_point', 'Ratoma', 'Cosa', 9.6464, -13.6118, 85),
  ('Carrefour Concasseur', ARRAY['Concasseur'], 'carrefour', 'Matoto', 'Tanene', 9.6132, -13.5732, 80),
  ('Carrefour Tanene', ARRAY['Tanene'], 'carrefour', 'Matoto', 'Tanene', 9.6072, -13.5689, 75),
  ('Mosquée Fayçal', ARRAY['Faycal', 'Mosquée Faycal'], 'mosquee', 'Matam', 'Donka', 9.5452, -13.6735, 95),
  ('Mosquée Senghor', ARRAY['Senghor'], 'mosquee', 'Kaloum', 'Sandervalia', 9.5166, -13.7141, 70),
  ('Marché Madina', ARRAY['Madina'], 'marche', 'Matam', 'Madina', 9.5356, -13.6724, 100),
  ('Marché Niger', ARRAY['Niger'], 'marche', 'Kaloum', 'Sandervalia', 9.5118, -13.7088, 75),
  ('Marché Taouyah', ARRAY['Taouyah'], 'marche', 'Ratoma', 'Taouyah', 9.5708, -13.6627, 70),
  ('Aéroport Gbessia', ARRAY['Aeroport', 'Conakry Airport', 'Gbessia'], 'aeroport', 'Matoto', 'Gbessia', 9.5770, -13.6128, 100),
  ('Port Autonome de Conakry', ARRAY['Port', 'PAC'], 'port', 'Kaloum', 'Boulbinet', 9.5099, -13.7129, 60),
  ('Hôpital Ignace Deen', ARRAY['Ignace Deen'], 'hopital', 'Kaloum', 'Sandervalia', 9.5135, -13.7099, 75),
  ('Hôpital Donka', ARRAY['Donka'], 'hopital', 'Dixinn', 'Donka', 9.5418, -13.6781, 85),
  ('Université Gamal Abdel Nasser', ARRAY['UGANC', 'Universite Gamal'], 'universite', 'Dixinn', 'Dixinn', 9.5512, -13.6742, 80),
  ('Stade du 28 Septembre', ARRAY['Stade 28 Septembre', '28 Septembre'], 'stade', 'Matam', 'Coleah', 9.5302, -13.6699, 90),
  ('Palais du Peuple', ARRAY['Palais Peuple'], 'monument', 'Kaloum', 'Sandervalia', 9.5145, -13.7042, 65),
  ('Belle Vue', ARRAY['Bellevue'], 'quartier', 'Dixinn', 'Belle Vue', 9.5481, -13.6862, 75),
  ('Kipé', ARRAY['Kipe'], 'quartier', 'Ratoma', 'Kipé', 9.5907, -13.6611, 80),
  ('Lambanyi', ARRAY['Lambagni'], 'quartier', 'Ratoma', 'Lambanyi', 9.6535, -13.6065, 70),
  ('Nongo', ARRAY[]::text[], 'quartier', 'Ratoma', 'Nongo', 9.6743, -13.6037, 70),
  ('Kaporo', ARRAY[]::text[], 'quartier', 'Ratoma', 'Kaporo', 9.6608, -13.6128, 65),
  ('Sonfonia', ARRAY[]::text[], 'quartier', 'Ratoma', 'Sonfonia', 9.6689, -13.5891, 65),
  ('Station Total Kipé', ARRAY['Total Kipe', 'Station Kipe'], 'station_service', 'Ratoma', 'Kipé', 9.5891, -13.6628, 60),
  ('Cathédrale Sainte-Marie', ARRAY['Cathedrale Conakry'], 'eglise', 'Kaloum', 'Sandervalia', 9.5142, -13.7106, 55);
