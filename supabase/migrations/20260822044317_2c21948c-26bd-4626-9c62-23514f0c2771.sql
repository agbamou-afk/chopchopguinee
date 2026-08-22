INSERT INTO public.feature_flags (key, enabled, description) VALUES
  ('service_moto_enabled', true, 'Exposition client — carte/tuile Course Moto dans les surfaces de découverte publiques. OFF = entrée non rendue (aucun placeholder).'),
  ('service_toktok_enabled', true, 'Exposition client — carte/tuile Course Bonbonna (toktok) dans les surfaces de découverte publiques. OFF = entrée non rendue.'),
  ('service_repas_enabled', true, 'Exposition client — carte/tuile Repas dans les surfaces de découverte publiques. OFF = entrée non rendue.'),
  ('service_marche_enabled', true, 'Exposition client — carte/tuile Marché dans les surfaces de découverte publiques. OFF = entrée non rendue.'),
  ('service_scan_enabled', true, 'Exposition client — entrée Scanner QR dans les surfaces de découverte publiques. OFF = entrée non rendue.'),
  ('merchant_recruitment_enabled', true, 'Exposition client — entonnoir « Devenir marchand » (tuile + route /devenir-marchand). Indépendant des flags transactionnels Marché/Repas.'),
  ('driver_recruitment_enabled', true, 'Exposition client — entonnoir « Devenir chauffeur » (tuile + route /driver/apply). Indépendant des flags de course.')
ON CONFLICT (key) DO NOTHING;