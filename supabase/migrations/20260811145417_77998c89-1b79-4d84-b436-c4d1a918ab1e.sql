REVOKE ALL ON public.payout_orders FROM anon, authenticated;
REVOKE ALL ON public.payout_provider_evidence FROM anon, authenticated;
REVOKE ALL ON public.payout_settlement_allocations FROM anon, authenticated;
REVOKE ALL ON public.merchant_settlement_schedule_runs FROM anon, authenticated;
GRANT SELECT ON public.payout_orders TO authenticated;
GRANT SELECT ON public.payout_settlement_allocations TO authenticated;
GRANT ALL ON public.payout_orders TO service_role;
GRANT ALL ON public.payout_provider_evidence TO service_role;
GRANT ALL ON public.payout_settlement_allocations TO service_role;
GRANT ALL ON public.merchant_settlement_schedule_runs TO service_role;
REVOKE ALL ON public._qa_s11_results FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s11_fixture_store(p_owner uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.merchant_stores (name, slug, owner_user_id, phone)
  VALUES ('QA S11 Store', 'qa-s11-' || substr(gen_random_uuid()::text,1,12), p_owner, '+224620000111')
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public._qa_s11_fixture_store(uuid) FROM PUBLIC, anon, authenticated;