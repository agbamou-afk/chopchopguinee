DO $mig$
DECLARE src text; nsrc text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname='_qa_s13_run7' AND pronamespace='public'::regnamespace;
  nsrc := src;

  nsrc := replace(nsrc,
    '    ---------------------------------------------------------------- Envoyer replay + claims replay
    PERFORM public._qa_s13_flag(''envoyer_enabled'', true);',
    '    ---------------------------------------------------------------- Envoyer replay + claims replay
    PERFORM public._qa_s13_flag(''chop_pay_enabled'', true);
    PERFORM public._qa_s13_flag(''chop_pay_checkout_enabled'', true);
    PERFORM public._qa_s13_flag(''envoyer_enabled'', true);');

  nsrc := replace(nsrc,
    'A11.2 the new debt is persisted as an open charged receivable, never pre-settled'',
      v_dstate IN (''open'',''charged''), COALESCE(v_dstate,''null''));',
    'A11.2 the new debt is persisted as an outstanding receivable, never pre-settled'',
      v_dstate = ''outstanding'', COALESCE(v_dstate,''null''));');

  nsrc := replace(nsrc,
    'A11.4 creating the debt creates no cash, no provider asset and no captured revenue'',
      (v_ovd1->>''captured_revenue_gnf'')::bigint = (v_ovd0->>''captured_revenue_gnf'')::bigint
      AND (v_ovd1->>''verified_assets_gnf'')::bigint = (v_ovd0->>''verified_assets_gnf'')::bigint
      AND (v_ovd1->>''om_inbound_credited_gnf'')::bigint = (v_ovd0->>''om_inbound_credited_gnf'')::bigint,
      format(''rev %s->%s assets %s->%s'',
        v_ovd0->>''captured_revenue_gnf'', v_ovd1->>''captured_revenue_gnf'',
        v_ovd0->>''verified_assets_gnf'', v_ovd1->>''verified_assets_gnf''));',
    'A11.4 charging the debt recognises the fee only as a receivable-backed charge and creates no cash or provider asset'',
      (v_ovd1->>''captured_revenue_gnf'')::bigint - (v_ovd0->>''captured_revenue_gnf'')::bigint = v_debt_amt
      AND (v_ovd1->>''verified_assets_gnf'')::bigint = (v_ovd0->>''verified_assets_gnf'')::bigint
      AND (v_ovd1->>''om_inbound_credited_gnf'')::bigint = (v_ovd0->>''om_inbound_credited_gnf'')::bigint
      AND (v_ovd1->>''cancellation_debt_collected_gnf'')::bigint = (v_ovd0->>''cancellation_debt_collected_gnf'')::bigint,
      format(''rev %s->%s assets %s->%s collected %s->%s'',
        v_ovd0->>''captured_revenue_gnf'', v_ovd1->>''captured_revenue_gnf'',
        v_ovd0->>''verified_assets_gnf'', v_ovd1->>''verified_assets_gnf'',
        v_ovd0->>''cancellation_debt_collected_gnf'', v_ovd1->>''cancellation_debt_collected_gnf''));');

  IF nsrc = src THEN RAISE EXCEPTION 'harness patch did not apply'; END IF;
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_s13_run7() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$', nsrc);
END $mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run7() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run7() TO service_role;

INSERT INTO public._qa_s13_results(part, result)
SELECT 7, public._qa_s13_run7();