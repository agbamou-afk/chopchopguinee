CREATE OR REPLACE FUNCTION public._professional_lane_require(
  p_user_id uuid, p_type text, p_source text DEFAULT NULL
) RETURNS public.professional_identities
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_row public.professional_identities;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_USER_REQUIRED';
  END IF;
  v_row := public._professional_identity_claim(p_user_id, p_type, p_source);
  RETURN v_row;
END $fn$;

REVOKE ALL ON FUNCTION public._professional_lane_require(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._professional_lane_require(uuid, text, text) FROM anon;
REVOKE ALL ON FUNCTION public._professional_lane_require(uuid, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public._professional_lane_require(uuid, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public._professional_artifact_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_type text := TG_ARGV[0];
  v_col  text := TG_ARGV[1];
  v_new  uuid;
  v_old  uuid;
BEGIN
  EXECUTE format('SELECT ($1).%I', v_col) INTO v_new USING NEW;
  IF v_new IS NULL THEN RETURN NEW; END IF;

  IF TG_OP = 'UPDATE' THEN
    EXECUTE format('SELECT ($1).%I', v_col) INTO v_old USING OLD;
    IF v_old IS NOT DISTINCT FROM v_new THEN RETURN NEW; END IF;
  END IF;

  PERFORM public._professional_lane_require(v_new, v_type, TG_TABLE_NAME);
  RETURN NEW;
END $fn$;

REVOKE ALL ON FUNCTION public._professional_artifact_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._professional_artifact_guard() FROM anon;
REVOKE ALL ON FUNCTION public._professional_artifact_guard() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._professional_artifact_guard() TO service_role;

DROP TRIGGER IF EXISTS professional_lane_guard ON public.driver_profiles;
CREATE TRIGGER professional_lane_guard
  BEFORE INSERT OR UPDATE OF user_id ON public.driver_profiles
  FOR EACH ROW EXECUTE FUNCTION public._professional_artifact_guard('driver','user_id');

DROP TRIGGER IF EXISTS professional_lane_guard ON public.driver_applications;
CREATE TRIGGER professional_lane_guard
  BEFORE INSERT OR UPDATE OF user_id ON public.driver_applications
  FOR EACH ROW EXECUTE FUNCTION public._professional_artifact_guard('driver','user_id');

DROP TRIGGER IF EXISTS professional_lane_guard ON public.merchant_stores;
CREATE TRIGGER professional_lane_guard
  BEFORE INSERT OR UPDATE OF owner_user_id ON public.merchant_stores
  FOR EACH ROW EXECUTE FUNCTION public._professional_artifact_guard('merchant','owner_user_id');

DROP TRIGGER IF EXISTS professional_lane_guard ON public.food_restaurants;
CREATE TRIGGER professional_lane_guard
  BEFORE INSERT OR UPDATE OF owner_user_id ON public.food_restaurants
  FOR EACH ROW EXECUTE FUNCTION public._professional_artifact_guard('merchant','owner_user_id');

DROP TRIGGER IF EXISTS professional_lane_guard ON public.merchants;
CREATE TRIGGER professional_lane_guard
  BEFORE INSERT OR UPDATE OF owner_user_id ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public._professional_artifact_guard('merchant','owner_user_id');