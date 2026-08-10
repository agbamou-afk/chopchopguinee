DO $do$
DECLARE v_def text;
BEGIN
  v_def := pg_get_functiondef('public._qa_s4_run()'::regprocedure);
  v_def := replace(v_def,
    'ALTER TABLE public.ledger_postings DISABLE TRIGGER USER;',
    'SET CONSTRAINTS ALL IMMEDIATE; ALTER TABLE public.ledger_postings DISABLE TRIGGER USER;');
  EXECUTE v_def;
END $do$;