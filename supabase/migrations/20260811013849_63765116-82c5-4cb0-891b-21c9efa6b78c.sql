REVOKE ALL ON public.merchant_settlement_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.merchant_settlement_requests FROM authenticated;
GRANT SELECT ON public.merchant_settlement_requests TO authenticated;
GRANT ALL ON public.merchant_settlement_requests TO service_role;

DELETE FROM public._qa_s7_results WHERE part = 4;
INSERT INTO public._qa_s7_results(part, result) VALUES (4, public._qa_s7_run4());