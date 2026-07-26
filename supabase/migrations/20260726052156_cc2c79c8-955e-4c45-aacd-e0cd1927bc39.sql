
CREATE OR REPLACE FUNCTION public.om_sandbox_assign_mock_driver(
  p_ride_id uuid,
  p_driver_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public._om_sandbox_require_active();
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF COALESCE((v_ride.metadata->>'sandbox')::boolean, false) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'not_a_sandbox_ride'; END IF;
  IF NOT public.is_god_admin(v_uid) AND v_ride.client_id <> v_uid THEN
    RAISE EXCEPTION 'forbidden'; END IF;
  IF v_ride.status <> 'pending' THEN
    RAISE EXCEPTION 'ride_not_pending: status=%', v_ride.status; END IF;
  IF p_driver_user_id IS NULL THEN RAISE EXCEPTION 'driver_user_id_required'; END IF;

  UPDATE public.rides
     SET driver_id = p_driver_user_id,
         metadata  = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
                       'sandbox_mock_driver_id', p_driver_user_id,
                       'sandbox_mock_assigned_at', now()),
         updated_at = now()
   WHERE id = p_ride_id;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'payments', 'sandbox.ride.mock_driver_assigned',
          'ride', p_ride_id::text,
          jsonb_build_object('mock_driver_id', p_driver_user_id));

  RETURN jsonb_build_object('ride_id', p_ride_id, 'driver_id', p_driver_user_id, 'is_sandbox', true);
END $$;
REVOKE ALL ON FUNCTION public.om_sandbox_assign_mock_driver(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.om_sandbox_assign_mock_driver(uuid,uuid) TO authenticated;
