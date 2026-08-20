DO $mig$
DECLARE s text; s0 text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO s FROM pg_proc
   WHERE proname='marche_ops_case_open' AND pronamespace='public'::regnamespace;
  s0 := s;
  s := replace(s, 'IF v_role NOT IN (''operations_admin'',''god_admin'') THEN',
                  'IF COALESCE(v_role,'''') NOT IN (''operations_admin'',''god_admin'') THEN');
  IF s = s0 THEN RAISE EXCEPTION 'PATCH_OPEN_FAILED'; END IF;
  EXECUTE s;

  SELECT pg_get_functiondef(oid) INTO s FROM pg_proc
   WHERE proname='marche_ops_signal' AND pronamespace='public'::regnamespace;
  s0 := s;
  s := replace(s, 'IF v_role NOT IN (''operations_admin'',''god_admin'') AND current_user <> ''service_role'' THEN',
                  'IF COALESCE(v_role,'''') NOT IN (''operations_admin'',''god_admin'') AND current_user <> ''service_role'' THEN');
  IF s = s0 THEN RAISE EXCEPTION 'PATCH_SIGNAL_FAILED'; END IF;
  EXECUTE s;

  SELECT pg_get_functiondef(oid) INTO s FROM pg_proc
   WHERE proname='marche_ops_command' AND pronamespace='public'::regnamespace;
  s0 := s;
  s := replace(s, 'IF NOT (v_allowed @> to_jsonb(ARRAY[p_action])) THEN',
                  'IF NOT (v_allowed @> jsonb_build_array(p_action)) THEN');
  IF s = s0 THEN RAISE EXCEPTION 'PATCH_COMMAND_FAILED'; END IF;
  EXECUTE s;
END $mig$;

REVOKE ALL ON FUNCTION public.marche_ops_case_open(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marche_ops_signal(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marche_ops_command(uuid,text,uuid,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marche_ops_case_open(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_ops_signal(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_ops_command(uuid,text,uuid,text,text,jsonb) TO authenticated;