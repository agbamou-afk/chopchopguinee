DO $mig$
DECLARE d text; snippet text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE proname = '_qa_node4_marche_r1';
  snippet := '  SELECT public._qa_users_count(ARRAY[v_seller, v_pend, v_comm, v_other, v_adm]) INTO v_n;
  r := r || public._qa_s13_ok(''N4.S26b zero auth fixture residue'', v_n = 0, v_n::text);
';
  IF position(snippet in d) = 0 THEN
    RAISE EXCEPTION 'R1 S26b snippet not found; aborting';
  END IF;
  d := replace(d, snippet, '');
  EXECUTE d;
END
$mig$;