ALTER TABLE public.finance_policies DROP CONSTRAINT finance_policies_mission_type_chk;
ALTER TABLE public.finance_policies ADD CONSTRAINT finance_policies_mission_type_chk
  CHECK (mission_type = ANY (ARRAY['ride'::text,'bonbonna'::text,'taxi'::text,'repas'::text,'marche'::text,'envoyer'::text]));