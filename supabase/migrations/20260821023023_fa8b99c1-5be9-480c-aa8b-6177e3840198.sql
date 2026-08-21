DO $mig$
DECLARE
  fns text[] := ARRAY[
    '_qa_s13_driver','_qa_s13_run1','_qa_s13_run2','_qa_s13_run3_fxcore','_qa_s13_run4',
    '_qa_node0_course','_qa_node1_bonbonna','_qa_node1_bonbonna_matrix','_qa_node2_taxi_full',
    '_qa_node3_repas_r1_r4_fxcore','_qa_node3_repas_r5_runtime_core',
    '_qa_node3_repas_r6_custody_fxcore','_qa_node3_repas_r7_ext','_qa_node3_repas_r7_semantics'
  ];
  fn text;
  def text; rest text; head text; rest2 text; stmt text; vals text;
  newdef text; indent text; claims text; uid text;
  pos int; endpos int; oc int; sites int; total_sites int := 0;
BEGIN
  FOREACH fn IN ARRAY fns LOOP
    def := pg_get_functiondef(('public.' || fn)::regproc);
    IF position('_professional_lane_require' in def) > 0 THEN
      RAISE NOTICE 'skip % (already composes the lane claim)', fn;
      CONTINUE;
    END IF;

    rest := def; newdef := ''; sites := 0;
    LOOP
      pos := position('INSERT INTO public.driver_profiles' in rest);
      EXIT WHEN pos = 0;
      head  := substr(rest, 1, pos - 1);
      rest2 := substr(rest, pos);
      endpos := position(';' in rest2);
      IF endpos = 0 THEN RAISE EXCEPTION 'QA_PATCH_UNTERMINATED_INSERT in %', fn; END IF;
      stmt := substr(rest2, 1, endpos);
      rest := substr(rest2, endpos + 1);

      indent := COALESCE(substring(head from '[ \t]*$'), '  ');

      vals := substr(stmt, position('VALUES' in stmt));
      oc := position('ON CONFLICT' in vals);
      IF oc > 0 THEN vals := substr(vals, 1, oc - 1); END IF;

      claims := '';
      FOR uid IN
        SELECT DISTINCT (m)[1]
          FROM regexp_matches(vals, '\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', 'g') AS m
      LOOP
        claims := claims || indent
               || 'PERFORM public._professional_lane_require(' || uid
               || ', ''driver'', ''qa_fixture'');' || E'\n';
      END LOOP;

      IF claims = '' THEN
        RAISE EXCEPTION 'QA_PATCH_NO_FIXTURE_UID in % : %', fn, left(stmt, 200);
      END IF;

      newdef := newdef || head || claims || stmt;
      sites := sites + 1;
    END LOOP;

    IF sites = 0 THEN
      RAISE EXCEPTION 'QA_PATCH_NO_INSERT_SITE in %', fn;
    END IF;

    newdef := newdef || rest;
    EXECUTE newdef;
    total_sites := total_sites + sites;
    RAISE NOTICE 'patched % (% driver fixture site(s))', fn, sites;
  END LOOP;

  RAISE NOTICE 'QA driver fixture remediation: % site(s) across % function(s)', total_sites, array_length(fns, 1);
END $mig$;