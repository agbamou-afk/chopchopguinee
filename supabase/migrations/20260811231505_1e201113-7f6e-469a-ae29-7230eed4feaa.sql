DO $mig$
DECLARE src text; nsrc text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_s13_run7' AND pronamespace='public'::regnamespace;
  nsrc := replace(src,
    '    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type=''client'';
    v_res := public.admin_package_claim_resolve(v_pkg2,''customer_upheld'',''qa p7 claim'',''evidence/p7.jpg'', 50000);',
    '    BEGIN v_res := public.admin_package_claim_resolve(v_pkg2,''customer_upheld'',''qa p7 undocumented'',''evidence/p7.jpg'', 50000);
      v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''C11b no claim money is paid before a God-Admin investigated documented value exists'',
      v_err <> ''NO_ERROR'', v_err);
    PERFORM public.admin_package_claim_set_documented_value(v_pkg2, 50000, ''evidence/p7.jpg'', ''qa p7 investigation'');
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type=''client'';
    v_res := public.admin_package_claim_resolve(v_pkg2,''customer_upheld'',''qa p7 claim'',''evidence/p7.jpg'', 50000);');
  IF nsrc = src THEN RAISE EXCEPTION 'claim patch did not apply'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_s13_run7() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$', nsrc);
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run7() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run7() TO service_role;

INSERT INTO public._qa_s13_results(part, result)
SELECT 7, public._qa_s13_run7();