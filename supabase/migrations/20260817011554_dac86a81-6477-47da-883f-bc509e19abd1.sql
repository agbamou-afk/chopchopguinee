DO $mig$
DECLARE src text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc
   WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r65';
  IF position(E'-- ============== G. IDEMPOTENCY ==============\n' IN src) = 0 THEN
    RAISE EXCEPTION 'ANCHOR_NOT_FOUND';
  END IF;
  src := replace(src,
    E'-- ============== G. IDEMPOTENCY ==============\n',
    E'-- ============== G. IDEMPOTENCY ==============\n    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_buy), true);\n');
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r65() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS ' || quote_literal(src);
END $mig$;

TRUNCATE public._qa_r65_trace;
DELETE FROM public._qa_board_run2 WHERE suite = '_qa_node4_marche_r65';
DO $$
DECLARE v jsonb;
BEGIN
  v := public._qa_node4_marche_r65();
  INSERT INTO public._qa_board_run2(suite,total,failed,err)
  VALUES ('_qa_node4_marche_r65', (v->>'total')::int, (v->>'failed')::int,
          left(COALESCE(v->'failures','[]'::jsonb)::text, 6000));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public._qa_board_run2(suite,total,failed,err)
  VALUES ('_qa_node4_marche_r65', -1, -1, SQLERRM);
END $$;