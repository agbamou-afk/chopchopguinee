CREATE OR REPLACE FUNCTION public._qa_node4_marche_r13_patch_marker() RETURNS void LANGUAGE sql AS $$ SELECT NULL::void $$;
DROP FUNCTION public._qa_node4_marche_r13_patch_marker();

DO $patch$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_node4_marche_r13';

  src := replace(src,
    $old$    PERFORM public.marche_listing_update(l_b, jsonb_build_object('status','paused'));$old$,
    $new$    PERFORM public.marche_listing_update(l_b, jsonb_build_object('availability','sold'));$new$);
  src := replace(src,
    $old$'N4R13.C12 a paused listing is reported unavailable',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'status'='unavailable', v_rev->'lines'->0->>'reason');$old$,
    $new$'N4R13.C12 a sold-out listing is reported unavailable',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'status'='unavailable'
      AND v_rev->'lines'->0->>'reason'='LISTING_SOLD',
          COALESCE(v_rev->'lines'->0->>'status','?')||'/'||COALESCE(v_rev->'lines'->0->>'reason','?'));$new$);
  src := replace(src,
    $old$    PERFORM public.marche_listing_update(l_b, jsonb_build_object('status','active'));$old$,
    $new$    PERFORM public.marche_listing_update(l_b, jsonb_build_object('availability','available'));$new$);
  src := replace(src,
    $old$COALESCE(NULLIF(v_case->'case'->>'id',''), v_case->>'id')::uuid$old$,
    $new$(v_case->>'case_id')::uuid$new$);

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r13() RETURNS jsonb LANGUAGE plpgsql SET statement_timeout TO ''60s'' AS %L',
    src);
END $patch$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r13() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r13() TO service_role;