CREATE OR REPLACE FUNCTION public.repas_admin_set_publication(
  p_restaurant_id uuid,
  p_action text,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.food_restaurants;
  v_before jsonb; v_new_state text; v_new_status text;
  v_role public.admin_role;
BEGIN
  IF NOT public._repas_caller_is_staff() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF p_action NOT IN ('publish','unpublish','suspend','reject') THEN
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  SELECT * INTO r FROM public.food_restaurants WHERE id = p_restaurant_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;

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
$$;

REVOKE ALL ON FUNCTION public.repas_admin_set_publication(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_admin_set_publication(uuid, text, text) TO authenticated, service_role;

INSERT INTO public._qa_s13_results(part, result)
SELECT 980, jsonb_build_object(
  'total', v->>'total',
  'failed', v->>'failed',
  'failures', (SELECT jsonb_agg(e) FROM jsonb_array_elements(v->'results') e WHERE (e->>'ok')::boolean IS NOT TRUE)
) FROM (SELECT public._qa_node3_repas_r8_discovery() AS v) s;