DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'wallets','wallet_transactions','ledger_postings','ledger_journals','ledger_accounts',
    'merchant_payables','claims_reserves','mission_financial_holds','driver_promo_credits',
    'customer_cancellation_debts','finance_policies'
  ] LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.%I FROM authenticated', t);
    EXECUTE format('GRANT SELECT ON public.%I TO authenticated', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
  END LOOP;
END $$;