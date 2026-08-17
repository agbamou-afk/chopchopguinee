DELETE FROM public._qa_board_run2 WHERE suite = 'node4_marche_r65';
DO $$
DECLARE v jsonb;
BEGIN
  BEGIN
    v := public._qa_node4_marche_r65();
    INSERT INTO public._qa_board_run2(suite, total, failed, err)
    VALUES ('node4_marche_r65', (v->>'total')::int, (v->>'failed')::int, NULL);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public._qa_board_run2(suite, total, failed, err)
    VALUES ('node4_marche_r65', NULL, NULL, SQLERRM);
  END;
END $$;