DO $do$
DECLARE v text;
BEGIN
  SELECT body INTO v FROM public._qa_patch_buffer WHERE id = 1;
  IF v IS NULL THEN RAISE EXCEPTION 'patch buffer empty'; END IF;
  EXECUTE v;
END $do$;

REVOKE ALL ON FUNCTION public._qa_s13_run4() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run4() TO service_role;

DROP TABLE IF EXISTS public._qa_patch_buffer;