DO $$
DECLARE r record; v_sql text;
BEGIN
  FOR r IN
    SELECT c.oid, c.proname FROM pg_proc c JOIN pg_namespace cn ON cn.oid=c.pronamespace
     WHERE cn.nspname='public' AND c.proname IN ('_qa_s13_run1','_qa_s13_run6','_qa_s13_run7_fxcore')
  LOOP
    v_sql := pg_get_functiondef(r.oid);
    v_sql := replace(v_sql,'driver_cashout_mark_paid(','driver_cashout_mark_paid__g2(');
    v_sql := replace(v_sql,'payout_reject_release(','payout_reject_release__g2(');
    v_sql := replace(v_sql,'driver_cashout_reject_request(','driver_cashout_reject_request__g2(');
    v_sql := replace(v_sql, 'FUNCTION public.'||r.proname||'__g2(', 'FUNCTION public.'||r.proname||'(');
    EXECUTE v_sql;
  END LOOP;
END $$;