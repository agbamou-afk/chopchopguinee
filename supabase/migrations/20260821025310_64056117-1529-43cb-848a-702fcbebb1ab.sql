DO $mig$
DECLARE
  def text := pg_get_functiondef('public._qa_node5_identity_a6'::regproc);
  anchor text := E'  UPDATE public.driver_profiles SET status=''approved'' WHERE user_id IN (u_d, u_rel);';
  ins text := E'\n  UPDATE public.profiles SET phone = ''+22462'' || lpad((floor(random()*10000000))::bigint::text, 7, ''0'')\n   WHERE user_id = ANY(ARRAY[u_c, u_d, u_p, u_rel, u_m, u_ops]) AND (phone IS NULL OR phone = '''');';
  occ int;
BEGIN
  occ := (length(def) - length(replace(def, anchor, ''))) / length(anchor);
  IF occ <> 1 THEN RAISE EXCEPTION 'A6_QA_ANCHOR occurrences=%', occ; END IF;
  EXECUTE replace(def, anchor, anchor || ins);
END $mig$;