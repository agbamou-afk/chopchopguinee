DO $mig$
DECLARE s text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc WHERE proname='_qa_node4_marche_r11';
  s := replace(s,
    'DELETE FROM public.finance_evidence_refs WHERE provider_reference LIKE ''QA-N411-%'';',
    'DELETE FROM public.finance_evidence_refs WHERE evidence_ref ILIKE ''qa-n411-%'';');
  EXECUTE format('CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11() RETURNS jsonb LANGUAGE plpgsql AS %L', s);
END $mig$;