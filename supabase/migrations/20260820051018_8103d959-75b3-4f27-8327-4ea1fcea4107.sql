DO $do$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r11';
  s := replace(s,
    'source_offer_id, merchant_fee_gnf, merchant_payable_gnf, delivery_address,',
    'source_offer_id, merchant_fee_gnf, merchant_payable_gnf, delivery_address,
        merchant_platform_fee_bps, fee_policy_id, fee_policy_effective_from,
        economics_snapshot, economics_resolved_at,');
  s := replace(s,
    'v_off, 200, 19800, ''QA Kaloum, Conakry'',',
    'v_off, 200, 19800, ''QA Kaloum, Conakry'',
        100,
        (SELECT id FROM public.finance_policies WHERE mission_type=''marche'' ORDER BY effective_from DESC LIMIT 1),
        (SELECT effective_from FROM public.finance_policies WHERE mission_type=''marche'' ORDER BY effective_from DESC LIMIT 1),
        jsonb_build_object(''qa'', true), now(),');
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11() RETURNS jsonb LANGUAGE plpgsql AS $qa$%s$qa$', s);
END $do$;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r11() TO postgres, service_role;
INSERT INTO public._qa_s13_results(part, result) VALUES (411, public._qa_node4_marche_r11());