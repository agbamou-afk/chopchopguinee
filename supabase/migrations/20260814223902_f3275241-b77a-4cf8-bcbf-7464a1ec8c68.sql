DO $$
DECLARE n int; msg text := NULL;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims','{"role":"anon"}', true);
    SET LOCAL ROLE anon;
    EXECUTE 'SELECT count(*)::int FROM public.marketplace_listings' INTO n;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; msg := SQLERRM; END;
  INSERT INTO public._qa_s13_results(part, result)
  VALUES (9961, jsonb_build_array(jsonb_build_object('label','anon diag2','ok', msg IS NULL,'detail', COALESCE(msg, n::text))));
END $$;