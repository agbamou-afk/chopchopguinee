CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_semantics()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out jsonb; v_prev boolean;
BEGIN
  SELECT enabled INTO v_prev FROM public.feature_flags WHERE key='chop_pay_checkout_enabled';
  UPDATE public.feature_flags SET enabled = true WHERE key='chop_pay_checkout_enabled';
  PERFORM set_config('app.repas_fixture_verified','1', true);
  BEGIN
    v_out := public._qa_node3_repas_r7_semantics_fxcore();
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.repas_fixture_verified','', true);
    UPDATE public.feature_flags SET enabled = v_prev WHERE key='chop_pay_checkout_enabled';
    RAISE;
  END;
  PERFORM set_config('app.repas_fixture_verified','', true);
  UPDATE public.feature_flags SET enabled = v_prev WHERE key='chop_pay_checkout_enabled';
  RETURN v_out;
END; $$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_readtruth()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out jsonb; v_prev boolean;
BEGIN
  SELECT enabled INTO v_prev FROM public.feature_flags WHERE key='chop_pay_checkout_enabled';
  UPDATE public.feature_flags SET enabled = true WHERE key='chop_pay_checkout_enabled';
  PERFORM set_config('app.repas_fixture_verified','1', true);
  BEGIN
    v_out := public._qa_node3_repas_r7_readtruth_fxcore();
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.repas_fixture_verified','', true);
    UPDATE public.feature_flags SET enabled = v_prev WHERE key='chop_pay_checkout_enabled';
    RAISE;
  END;
  PERFORM set_config('app.repas_fixture_verified','', true);
  UPDATE public.feature_flags SET enabled = v_prev WHERE key='chop_pay_checkout_enabled';
  RETURN v_out;
END; $$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_ext()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out jsonb; v_prev boolean;
BEGIN
  SELECT enabled INTO v_prev FROM public.feature_flags WHERE key='chop_pay_checkout_enabled';
  UPDATE public.feature_flags SET enabled = true WHERE key='chop_pay_checkout_enabled';
  PERFORM set_config('app.repas_fixture_verified','1', true);
  BEGIN
    v_out := public._qa_node3_repas_r7_ext_fxcore();
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('app.repas_fixture_verified','', true);
    UPDATE public.feature_flags SET enabled = v_prev WHERE key='chop_pay_checkout_enabled';
    RAISE;
  END;
  PERFORM set_config('app.repas_fixture_verified','', true);
  UPDATE public.feature_flags SET enabled = v_prev WHERE key='chop_pay_checkout_enabled';
  RETURN v_out;
END; $$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_semantics() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_ext() FROM PUBLIC, anon, authenticated;