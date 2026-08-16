DO $do$
DECLARE s text; old text; new text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r35';
  old := 'r := r || public._qa_s13_ok(''N4R35.C31 ORDER_COMMITTED is the only production-wired milestone'',
        (SELECT count(*) FROM pg_proc WHERE pronamespace=''public''::regnamespace
          AND proname NOT LIKE ''\_qa\_%'' AND proname <> ''marche_fulfillment_event_append''
          AND (prosrc LIKE ''%MERCHANT_ACCEPTED%'' OR prosrc LIKE ''%COURIER_AT_STORE%''
            OR prosrc LIKE ''%SHOPPING_STARTED%'' OR prosrc LIKE ''%PICKED_UP''''%'')
          AND proname NOT LIKE ''marche_fulfillment_recompute%'') = 0, NULL);';
  new := 'r := r || public._qa_s13_ok(''N4R35.C31 milestones are wired only by the authorized fulfillment state machine'',
        (SELECT coalesce(string_agg(proname, '','' ORDER BY proname), '''') FROM pg_proc
          WHERE pronamespace=''public''::regnamespace
          AND proname NOT LIKE ''\_qa\_%'' AND proname <> ''marche_fulfillment_event_append''
          AND proname NOT LIKE ''marche_fulfillment_recompute%''
          AND (prosrc LIKE ''%MERCHANT_ACCEPTED%'' OR prosrc LIKE ''%COURIER_AT_STORE%''
            OR prosrc LIKE ''%SHOPPING_STARTED%'' OR prosrc LIKE ''%PICKED_UP''''%''))
        = ''marche_courier_transition,marche_merchant_transition'',
        (SELECT coalesce(string_agg(proname, '','' ORDER BY proname), '''') FROM pg_proc
          WHERE pronamespace=''public''::regnamespace
          AND proname NOT LIKE ''\_qa\_%'' AND proname <> ''marche_fulfillment_event_append''
          AND proname NOT LIKE ''marche_fulfillment_recompute%''
          AND (prosrc LIKE ''%MERCHANT_ACCEPTED%'' OR prosrc LIKE ''%COURIER_AT_STORE%''
            OR prosrc LIKE ''%SHOPPING_STARTED%'' OR prosrc LIKE ''%PICKED_UP''''%'')));';
  IF position(old in s) = 0 THEN RAISE EXCEPTION 'C31_PATCH_ANCHOR_NOT_FOUND'; END IF;
  s := replace(s, old, new);
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r35() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS %L', s);
END $do$;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r35() FROM PUBLIC, anon, authenticated;

DELETE FROM public._qa_s13_results WHERE part = 46;
INSERT INTO public._qa_s13_results(part, result) VALUES (46, public._qa_node4_marche_r35());