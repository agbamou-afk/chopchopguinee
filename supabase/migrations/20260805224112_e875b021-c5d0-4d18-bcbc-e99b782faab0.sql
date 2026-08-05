DO $mig$
DECLARE src text; newsrc text; n int := 0;
  guard text := E'  IF (auth.uid() IS NOT NULL) AND NOT public._finance_privileged(auth.uid()) THEN\n    RAISE EXCEPTION ''Not authorized'';\n  END IF;\n';
BEGIN
  -- 1. driver_mission_hold_release: hoist guard above the row lookup
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc
   WHERE proname = 'driver_mission_hold_release' AND pronargs = 4;
  newsrc := replace(src,
    E'BEGIN\n  FOR v_h IN',
    E'BEGIN\n' || guard || E'  FOR v_h IN');
  IF newsrc = src THEN RAISE EXCEPTION 'release anchor not found'; END IF;
  EXECUTE newsrc;

  -- 2. driver_mission_fee_capture: hoist guard above the row lookup
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = 'driver_mission_fee_capture';
  newsrc := replace(src,
    E'BEGIN\n  SELECT * INTO v_h FROM public.mission_financial_holds',
    E'BEGIN\n' || guard || E'  SELECT * INTO v_h FROM public.mission_financial_holds');
  IF newsrc = src THEN RAISE EXCEPTION 'fee capture anchor not found'; END IF;
  EXECUTE newsrc;

  -- 3. driver_funding_allocate: add a caller guard (internal helper)
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = 'driver_funding_allocate';
  newsrc := replace(src,
    E'BEGIN\n  SELECT * INTO v_w FROM public.wallets',
    E'BEGIN\n' || guard || E'  SELECT * INTO v_w FROM public.wallets');
  IF newsrc = src THEN RAISE EXCEPTION 'funding allocate anchor not found'; END IF;
  EXECUTE newsrc;
END $mig$;

REVOKE ALL ON FUNCTION public.driver_mission_hold_release(text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.driver_mission_fee_capture(text, uuid, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.driver_funding_allocate(uuid, bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.driver_mission_hold_release(text, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.driver_mission_fee_capture(text, uuid, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.driver_funding_allocate(uuid, bigint, text) TO service_role;