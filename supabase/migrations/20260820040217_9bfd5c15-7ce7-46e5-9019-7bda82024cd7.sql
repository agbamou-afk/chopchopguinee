DO $mig$
DECLARE d text; o text; n text; tail text; add text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname='public' AND p.proname='_qa_node4_marche_r35';
  IF d IS NULL THEN RAISE EXCEPTION 'R35_HARNESS_NOT_FOUND'; END IF;

  o := $old$          AND (prosrc LIKE '%MERCHANT_ACCEPTED%' OR prosrc LIKE '%COURIER_AT_STORE%'$old$;
  n := $new$          -- Milestone authorship is a WRITER law. Read-only consumers (the STABLE R10
          -- ranking evidence helper) merely reference canonical metric names and are excluded.
          AND provolatile = 'v'
          AND (prosrc LIKE '%MERCHANT_ACCEPTED%' OR prosrc LIKE '%COURIER_AT_STORE%'$new$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'R35_C31_ANCHOR_NOT_FOUND'; END IF;
  d := replace(d, o, n);

  tail := $old$OR prosrc LIKE '%PICKED_UP''%')));$old$;
  add := $new$OR prosrc LIKE '%PICKED_UP''%')));

  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace
             AND proname='_marche_rank_evidence');
  r := r || public._qa_s13_ok('N4R35.C31b the R10 ranking helper only READS fulfillment telemetry',
        v_src IS NOT NULL
    AND (SELECT provolatile FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname='_marche_rank_evidence') = 's'
    AND v_src NOT LIKE '%INSERT INTO public.marche_fulfillment_observations%'
    AND v_src NOT LIKE '%INSERT INTO public.marche_fulfillment_events%'
    AND v_src NOT LIKE '%marche_fulfillment_event_append%', NULL);
  r := r || public._qa_s13_ok('N4R35.C31c ranking reuses canonical R5/R3.5 observations, not duplicate telemetry',
        v_src LIKE '%marche_fulfillment_observations%'
    AND v_src LIKE '%COMMIT_TO_MERCHANT_ACCEPTED%'
    AND v_src LIKE '%MERCHANT_ACCEPTED_TO_READY%', NULL);$new$;
  IF position(tail in d) = 0 THEN RAISE EXCEPTION 'R35_C31_TAIL_NOT_FOUND'; END IF;
  d := replace(d, tail, add);

  EXECUTE d;
END
$mig$;