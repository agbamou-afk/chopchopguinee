REVOKE ALL ON TABLE public.marche_procurement_requests FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.marche_procurement_request_items FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.marche_procurement_authorizations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.marche_procurement_events FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.marche_procurement_price_observations FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.marche_procurement_requests TO service_role;
GRANT ALL ON TABLE public.marche_procurement_request_items TO service_role;
GRANT ALL ON TABLE public.marche_procurement_authorizations TO service_role;
GRANT ALL ON TABLE public.marche_procurement_events TO service_role;
GRANT ALL ON TABLE public.marche_procurement_price_observations TO service_role;

DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT oid::regprocedure AS sig FROM pg_proc
            WHERE pronamespace='public'::regnamespace AND proname LIKE '%procurement%' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', p.sig);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.marche_procurement_quote(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_authorize(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_increase(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_cancel(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_get(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_list(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_observation_record(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_settle_internal(uuid,bigint,text) TO service_role;

CREATE TABLE IF NOT EXISTS public._qa_r65_trace (
  seq bigserial PRIMARY KEY, ok boolean, label text, detail text);
REVOKE ALL ON TABLE public._qa_r65_trace FROM PUBLIC, anon, authenticated;