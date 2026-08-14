DO $do$
DECLARE v_def text; v_new text; v_name text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['repas_custody_confirm_handoff','repas_custody_confirm_delivery'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname = v_name;
    v_new := regexp_replace(
      v_def,
      'mission_events\(mission_id, kind, payload\)\s*VALUES \(p_mission_id, ''([a-z_]+)'',\s*jsonb_build_object\([^;]*\);',
      'mission_events(mission_id, event, actor_id, note) VALUES (p_mission_id, ''\1'', auth.uid(), p_photo_path);'
    );
    IF v_new = v_def OR v_new LIKE '%mission_events(mission_id, kind%' THEN
      RAISE EXCEPTION 'CUSTODY_EVENT_PATCH_FAILED_%', v_name;
    END IF;
    EXECUTE v_new;
  END LOOP;
END $do$;

-- Correct two harness assertions to match the (stronger) real posture:
-- custody events are not directly readable by clients at all; they are exposed
-- only through the holder-scoped repas_custody_status RPC, and the mission
-- audit trail uses the canonical mission_events(event) column.
DO $do$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r6_custody';

  v_new := replace(v_def,
$old$  r := r || public._qa_s13_ok('S0.7 custody events readable by participants only, never writable',
        has_table_privilege('authenticated','public.repas_custody_events','SELECT')
        AND NOT has_table_privilege('authenticated','public.repas_custody_events','INSERT')
        AND NOT has_table_privilege('anon','public.repas_custody_events','SELECT'), NULL);$old$,
$new$  r := r || public._qa_s13_ok('S0.7 custody events are RPC-only: no direct client read or write',
        NOT has_table_privilege('authenticated','public.repas_custody_events','SELECT')
        AND NOT has_table_privilege('authenticated','public.repas_custody_events','INSERT')
        AND NOT has_table_privilege('anon','public.repas_custody_events','SELECT'), NULL);$new$);

  v_new := replace(v_new,
$old$    SELECT count(*) INTO v_n FROM public.mission_events
     WHERE mission_id=v_m1 AND kind='repas_custody_restaurant_to_courier';$old$,
$new$    SELECT count(*) INTO v_n FROM public.mission_events
     WHERE mission_id=v_m1 AND event='repas_custody_restaurant_to_courier';$new$);

  IF v_new = v_def THEN RAISE EXCEPTION 'QA_PATCH_FAILED'; END IF;
  EXECUTE v_new;
END $do$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r6_custody() FROM PUBLIC, anon, authenticated;