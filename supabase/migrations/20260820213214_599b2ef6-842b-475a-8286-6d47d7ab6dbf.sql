DO $mig$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO d FROM pg_proc
   WHERE proname = '_qa_node5_identity_a2' AND pronamespace = 'public'::regnamespace;
  IF d IS NULL THEN RAISE EXCEPTION 'harness missing'; END IF;

  d := replace(d,
        'DECLARE' || chr(10) || '  r jsonb := ''[]''::jsonb;',
        'DECLARE' || chr(10) || '  v_qa_role text := current_user;' || chr(10) || '  r jsonb := ''[]''::jsonb;');
  d := replace(d,
        'EXECUTE ''RESET ROLE'';',
        'EXECUTE format(''SET LOCAL ROLE %I'', v_qa_role);');

  IF position('v_qa_role text := current_user' in d) = 0 THEN
    RAISE EXCEPTION 'declaration patch did not apply';
  END IF;
  IF position('RESET ROLE' in d) > 0 THEN
    RAISE EXCEPTION 'role restore patch did not apply';
  END IF;

  EXECUTE d;
END $mig$;