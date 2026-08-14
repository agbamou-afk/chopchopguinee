-- 1. Trusted server-only fixture publication context (no production path can set it)
CREATE OR REPLACE FUNCTION public._food_restaurant_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_no_auth boolean := auth.uid() IS NULL;
  v_bypass boolean :=
    v_no_auth
    OR coalesce(current_setting('app.repas_publication_ctx', true), '') = '1'
    OR public._repas_caller_is_staff();
BEGIN
  IF v_bypass THEN
    IF TG_OP = 'INSERT'
       AND v_no_auth
       AND coalesce(current_setting('app.repas_fixture_verified', true), '') = '1'
       AND coalesce(NEW.verification_state, 'none') = 'none' THEN
      NEW.verification_state := 'verified';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.owner_user_id      := auth.uid();
    NEW.verification_state := 'none';
    NEW.choppay_enabled    := false;
    NEW.merchant_store_id  := NULL;
    NEW.status             := 'active';
    RETURN NEW;
  END IF;

  IF NEW.verification_state IS DISTINCT FROM OLD.verification_state THEN
    RAISE EXCEPTION 'RESTAURANT_PUBLICATION_IS_STAFF_ONLY';
  END IF;
  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
    RAISE EXCEPTION 'RESTAURANT_OWNER_IS_IMMUTABLE';
  END IF;
  IF NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id THEN
    RAISE EXCEPTION 'RESTAURANT_STORE_LINK_IS_STAFF_ONLY';
  END IF;
  IF NEW.choppay_enabled IS DISTINCT FROM OLD.choppay_enabled THEN
    RAISE EXCEPTION 'RESTAURANT_CHOPPAY_IS_STAFF_ONLY';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'RESTAURANT_STATUS_IS_STAFF_ONLY';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;

-- 2. Publication is required for quote and for commitment (fail closed, before any state)
CREATE OR REPLACE FUNCTION public._repas_assert_orderable_publication(p_r public.food_restaurants)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
BEGIN
  IF p_r.status <> 'active' THEN RAISE EXCEPTION 'RESTAURANT_NOT_ORDERABLE'; END IF;
  IF coalesce(p_r.verification_state,'none') <> 'verified' THEN
    RAISE EXCEPTION 'RESTAURANT_NOT_PUBLISHED';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public._repas_assert_orderable_publication(public.food_restaurants) FROM PUBLIC;

-- 3. Staff publication must not publish zero-menu supply
CREATE OR REPLACE FUNCTION public.repas_admin_set_publication(p_restaurant_id uuid, p_action text, p_reason text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r public.food_restaurants;
  v_before jsonb; v_new_state text; v_new_status text;
  v_role public.admin_role;
  v_menu int;
BEGIN
  IF NOT public._repas_caller_is_staff() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF p_action NOT IN ('publish','unpublish','suspend','reject') THEN
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  SELECT * INTO r FROM public.food_restaurants WHERE id = p_restaurant_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;

  IF p_action = 'publish' THEN
    SELECT count(*) INTO v_menu FROM public.food_menu_items WHERE restaurant_id = p_restaurant_id;
    IF coalesce(v_menu,0) = 0 THEN
      RAISE EXCEPTION 'PUBLISH_REQUIRES_MENU'
        USING DETAIL = 'a restaurant without any real menu item cannot be published';
    END IF;
  END IF;

  v_before := jsonb_build_object('verification_state', r.verification_state, 'status', r.status);

  v_new_state := CASE p_action
    WHEN 'publish'   THEN 'verified'
    WHEN 'unpublish' THEN 'none'
    WHEN 'suspend'   THEN 'suspended'
    WHEN 'reject'    THEN 'rejected'
  END;
  v_new_status := CASE WHEN p_action IN ('suspend','reject') THEN 'inactive' ELSE 'active' END;

  PERFORM set_config('app.repas_publication_ctx', '1', true);
  UPDATE public.food_restaurants
     SET verification_state = v_new_state,
         status = v_new_status,
         updated_at = now()
   WHERE id = p_restaurant_id;
  PERFORM set_config('app.repas_publication_ctx', '', true);

  v_role := CASE WHEN public._is_god_admin(auth.uid()) THEN 'god_admin'::public.admin_role
                 ELSE 'ops_admin'::public.admin_role END;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, before, after, note)
  VALUES (auth.uid(), v_role, 'repas', 'restaurant_' || p_action, 'food_restaurant', p_restaurant_id,
          v_before,
          jsonb_build_object('verification_state', v_new_state, 'status', v_new_status),
          nullif(btrim(coalesce(p_reason, '')), ''));

  RETURN jsonb_build_object('id', p_restaurant_id, 'verification_state', v_new_state, 'status', v_new_status);
END;
$function$;
