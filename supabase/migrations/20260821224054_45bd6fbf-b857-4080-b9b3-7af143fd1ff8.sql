REVOKE ALL ON public.dormant_closed_account_liabilities FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.dormant_closed_account_liabilities FROM authenticated;
GRANT SELECT ON public.dormant_closed_account_liabilities TO authenticated;
GRANT ALL ON public.dormant_closed_account_liabilities TO service_role;
