DO $$
DECLARE r record; w record; d text;
BEGIN
  -- 1) rename every wrapped inner function `x__g2` -> `_g2i_x`
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) args
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname LIKE '%\_\_g2'
  LOOP
    EXECUTE format('ALTER FUNCTION public.%I(%s) RENAME TO %I',
                   r.proname, r.args, '_g2i_' || left(r.proname, length(r.proname) - 4));
  END LOOP;

  -- 2) repoint every caller (wrappers + QA harnesses) at the new inner names
  FOR w IN
    SELECT p.oid, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.prosrc LIKE '%\_\_g2(%'
  LOOP
    d := pg_get_functiondef(w.oid);
    d := regexp_replace(d, '(?<![A-Za-z0-9_])(?:public\.)?([a-z0-9_]+)__g2\(', 'public._g2i_\1(', 'g');
    EXECUTE d;
  END LOOP;
END $$;