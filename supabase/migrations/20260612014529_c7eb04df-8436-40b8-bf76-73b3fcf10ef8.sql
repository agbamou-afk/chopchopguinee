
-- Phase 6C: Admin ops RPCs for Repas settlement

-- Admin: link a food restaurant to a merchant store.
CREATE OR REPLACE FUNCTION public.admin_link_restaurant_to_merchant_store(
  p_restaurant_id uuid,
  p_merchant_store_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restaurant_name text;
  v_store_name text;
  v_store_status text;
  v_old_store uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT name, merchant_store_id INTO v_restaurant_name, v_old_store
    FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF v_restaurant_name IS NULL THEN
    RAISE EXCEPTION 'restaurant_not_found' USING ERRCODE = 'P0002';
  END IF;

  SELECT name, onboarding_status INTO v_store_name, v_store_status
    FROM public.merchant_stores WHERE id = p_merchant_store_id;
  IF v_store_name IS NULL THEN
    RAISE EXCEPTION 'merchant_store_not_found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.food_restaurants
     SET merchant_store_id = p_merchant_store_id, updated_at = now()
   WHERE id = p_restaurant_id;

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, action, resource_type, resource_id, metadata)
    VALUES (
      auth.uid(),
      'repas.restaurant.link_merchant_store',
      'food_restaurant',
      p_restaurant_id,
      jsonb_build_object(
        'restaurant_name', v_restaurant_name,
        'merchant_store_id', p_merchant_store_id,
        'merchant_store_name', v_store_name,
        'merchant_store_status', v_store_status,
        'previous_merchant_store_id', v_old_store
      )
    );
  EXCEPTION WHEN OTHERS THEN
    -- audit failure is non-fatal
    NULL;
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'restaurant_id', p_restaurant_id,
    'merchant_store_id', p_merchant_store_id,
    'merchant_store_name', v_store_name,
    'merchant_store_status', v_store_status,
    'previous_merchant_store_id', v_old_store
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_link_restaurant_to_merchant_store(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_link_restaurant_to_merchant_store(uuid, uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_link_restaurant_to_merchant_store(uuid, uuid) IS
  'Phase 6C: admin-only restaurant<->merchant_store linkage with audit_logs trail.';

-- Admin wrapper around repas_capture_and_settle_order (callable from admin UI).
CREATE OR REPLACE FUNCTION public.admin_repas_capture_and_settle_order(
  p_food_order_id uuid,
  p_reason text DEFAULT 'Admin capture'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  v_result := public.repas_capture_and_settle_order(p_food_order_id, COALESCE(p_reason, 'Admin capture'));

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, action, resource_type, resource_id, metadata)
    VALUES (
      auth.uid(),
      'repas.payment.capture_and_settle',
      'food_order',
      p_food_order_id,
      v_result
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_repas_capture_and_settle_order(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_repas_capture_and_settle_order(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_repas_capture_and_settle_order(uuid, text) IS
  'Phase 6C: admin-only wrapper invoking repas_capture_and_settle_order, with audit trail.';
