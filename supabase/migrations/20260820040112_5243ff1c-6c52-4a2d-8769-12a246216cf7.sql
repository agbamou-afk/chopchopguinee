DO $mig$
DECLARE d text; o text; n text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname='public' AND p.proname='_qa_node4_marche_r1';
  IF d IS NULL THEN RAISE EXCEPTION 'R1_HARNESS_NOT_FOUND'; END IF;

  o := $old$  r := r || public._qa_s13_ok('N4.B5 all Marché R1 primitives are SECURITY DEFINER with pinned search_path',
        v_n = 16, v_n::text);$old$;

  n := $new$  -- 17, not 16: marche_listings_discover has two arities since R10 (the canonical
  -- 8-argument core taking optional customer coordinates, plus the 6-argument delegate).
  -- Both must be SECURITY DEFINER with a pinned search_path.
  r := r || public._qa_s13_ok('N4.B5 all Marché R1 primitives are SECURITY DEFINER with pinned search_path',
        v_n = 17, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace
     AND p.proname = 'marche_listings_discover'
     AND p.prosecdef
     AND EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) c WHERE c LIKE 'search_path=%');
  r := r || public._qa_s13_ok('N4.B5a both discovery arities are SECURITY DEFINER with pinned search_path',
        v_n = 2, v_n::text);$new$;

  IF position(o in d) = 0 THEN RAISE EXCEPTION 'R1_B5_ANCHOR_NOT_FOUND'; END IF;
  d := replace(d, o, n);
  EXECUTE d;
END
$mig$;