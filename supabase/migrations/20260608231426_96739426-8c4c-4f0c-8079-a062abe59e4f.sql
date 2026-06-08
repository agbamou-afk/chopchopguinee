
ALTER TABLE public.wallets DROP CONSTRAINT IF EXISTS wallet_balance_nonneg;
ALTER TABLE public.wallets ADD CONSTRAINT wallet_balance_nonneg
  CHECK (
    (party_type = 'master') OR (balance_gnf >= 0 AND held_gnf >= 0)
  );
