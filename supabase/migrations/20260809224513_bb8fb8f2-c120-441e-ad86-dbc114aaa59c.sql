DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public._qa_s3b_run()'::regprocedure) INTO d;
  d := replace(d, 'notes', 'note');
  EXECUTE d;
END $$;