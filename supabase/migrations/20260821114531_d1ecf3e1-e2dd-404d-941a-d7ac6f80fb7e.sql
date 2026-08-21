CREATE OR REPLACE FUNCTION public._professional_state_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type  text := TG_ARGV[0];
  v_owner uuid;
  v_live  boolean;
BEGIN
  IF TG_TABLE_NAME = 'driver_profiles' THEN
    IF NEW.status NOT IN ('approved','suspended') THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
    -- Sanctions must stay available even for an orphaned professional artifact.
    IF NEW.status = 'suspended' THEN RETURN NEW; END IF;
    v_owner := NEW.user_id;
  ELSIF TG_TABLE_NAME = 'merchant_stores' THEN
    IF NEW.status NOT IN ('active','suspended','paused')
       AND COALESCE(NEW.onboarding_status,'') <> 'approved' THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE'
       AND OLD.status = NEW.status
       AND OLD.onboarding_status IS NOT DISTINCT FROM NEW.onboarding_status THEN RETURN NEW; END IF;
    -- Only an OPERATIONAL end state requires a live professional lane; moving a
    -- store into a non-operational state (suspend / pause / de-approve) is a
    -- safety action and must never be blocked by a released lane.
    IF NOT (NEW.status = 'active' AND COALESCE(NEW.onboarding_status,'') = 'approved') THEN
      RETURN NEW;
    END IF;
    v_owner := NEW.owner_user_id;
  ELSE
    RETURN NEW;
  END IF;

  IF v_owner IS NULL THEN RETURN NEW; END IF;

  SELECT true INTO v_live FROM public.professional_identities
   WHERE user_id = v_owner AND claim_state = 'active' AND professional_type = v_type
   LIMIT 1;

  IF v_live IS NOT TRUE THEN
    RAISE EXCEPTION 'PROFESSIONAL_LANE_RELEASED';
  END IF;
  RETURN NEW;
END $function$;