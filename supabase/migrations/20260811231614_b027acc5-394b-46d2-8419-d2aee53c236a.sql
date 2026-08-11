DO $mig$
DECLARE src text; nsrc text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_s13_run7' AND pronamespace='public'::regnamespace;
  nsrc := replace(src,
    '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_god), true);
    UPDATE public.merchant_stores SET status=''active'', merchant_status=''active'', onboarding_status=''approved''
     WHERE id = v_s1;',
    '    INSERT INTO public.user_roles(user_id, role) VALUES (v_god,''admin'') ON CONFLICT DO NOTHING;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_god), true);
    UPDATE public.merchant_stores SET status=''active'', merchant_status=''active'', onboarding_status=''approved''
     WHERE id = v_s1;');
  IF nsrc = src THEN RAISE EXCEPTION 'store admin patch did not apply'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_s13_run7() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$', nsrc);
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run7() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run7() TO service_role;

INSERT INTO public._qa_s13_results(part, result)
SELECT 7, public._qa_s13_run7();