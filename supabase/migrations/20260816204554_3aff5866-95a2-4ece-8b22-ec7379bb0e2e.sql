CREATE OR REPLACE FUNCTION public.marche_fulfillment_observation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF COALESCE(current_setting('marche.fulfillment_derive', true),'') = '1' THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'FULFILLMENT_OBSERVATION_DERIVED_ONLY';
END $fn$;

DELETE FROM public._qa_s13_results WHERE part IN (435, 9435);
INSERT INTO public._qa_s13_results(part, result)
SELECT 435, public._qa_node4_marche_r35();