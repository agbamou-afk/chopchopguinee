DO $mig$
DECLARE
  v_def text;
  b_old text := 'j.kind::text||''/''||COALESCE(j.amount_gnf::text,''-'')';
  b_new text := 'j.action::text';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_readtruth';
  IF position(b_old in v_def) = 0 THEN RAISE EXCEPTION 'ANCHOR'; END IF;
  EXECUTE replace(v_def, b_old, b_new);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;