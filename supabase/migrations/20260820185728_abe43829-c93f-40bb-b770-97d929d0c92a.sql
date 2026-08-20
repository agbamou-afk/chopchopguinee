DO $mig$
DECLARE s text; s0 text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO s FROM pg_proc
   WHERE proname='_marche_ops_allowed_actions' AND pronamespace='public'::regnamespace;
  s0 := s;
  s := regexp_replace(s, 'a := a \|\| ''([a-z_]+)'';', 'a := array_append(a, ''\1''::text);', 'g');
  s := replace(s, 'a := a || ''add_note'' || ''assign'' || ''request_evidence'' || ''escalate'';',
                  'a := a || ARRAY[''add_note'',''assign'',''request_evidence'',''escalate'']::text[];');
  s := replace(s, 'a := a || ''resolve'' || ''dismiss'';',
                  'a := a || ARRAY[''resolve'',''dismiss'']::text[];');
  IF s = s0 OR position('a := a || ''' in s) > 0 THEN
    RAISE EXCEPTION 'PATCH_ALLOWED_ACTIONS_FAILED';
  END IF;
  EXECUTE s;
END $mig$;