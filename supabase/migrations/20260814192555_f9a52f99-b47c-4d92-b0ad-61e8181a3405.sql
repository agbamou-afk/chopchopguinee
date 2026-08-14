DO $do$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r8_extra';
  v_src := replace(v_src,
    $old$    r := r || public._qa_s13_ok('P15.4 an anonymous caller matches no restaurant INSERT predicate',$old$,
    $new$    PERFORM set_config('request.jwt.claims', ''::text, true);
    r := r || public._qa_s13_ok('P15.4 an anonymous caller matches no restaurant INSERT predicate',$new$);
  EXECUTE v_src;
END
$do$;
