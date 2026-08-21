DO $mig$
DECLARE v_src text; v_new text;
BEGIN
  v_src := pg_get_functiondef('public._qa_node4_marche_r15()'::regprocedure);
  v_new := replace(v_src,
    E'r := r || public._qa_s13_ok(''N4R15.B6c publishing a storeless row is refused'',\n          v_err = ''MERCHANT_STORE_REQUIRED'', v_err);',
    E'-- Node 5 A7: a classless legacy seller is now refused on professional identity\n    -- first; either canonical refusal proves the storeless row is unpublishable.\n    r := r || public._qa_s13_ok(''N4R15.B6c publishing a storeless row is refused'',\n          v_err IN (''MERCHANT_STORE_REQUIRED'',''PROFESSIONAL_IDENTITY_REQUIRED''), v_err);');
  IF v_new = v_src THEN RAISE EXCEPTION 'R15_B6C_ANCHOR_MISSING'; END IF;
  EXECUTE v_new;
END $mig$;