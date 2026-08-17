DO $$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname='marche_shopper_submit_purchase';
  src := replace(src, 'lr.actual_qty, i.qty)', 'lr.actual_qty, i.requested_qty)');
  EXECUTE src;
END $$;

DELETE FROM public._qa_board_run2;
DO $$
DECLARE r jsonb;
BEGIN
  r := public._qa_node4_marche_r8();
  INSERT INTO public._qa_board_run2(suite,total,failed,err)
  VALUES ('_qa_node4_marche_r8', (r->>'total')::int, (r->>'failed')::int, left((r->'failures')::text, 8000));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES ('_qa_node4_marche_r8',NULL,NULL,SQLERRM);
END $$;