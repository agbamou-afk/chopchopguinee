
-- 1) payment_receiving_accounts table
CREATE TABLE IF NOT EXISTS public.payment_receiving_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL DEFAULT 'orange_money',
  label text NOT NULL,
  phone_e164 text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  public_instructions text,
  admin_notes text,
  created_by uuid,
  updated_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payment_receiving_accounts_provider_chk
    CHECK (provider IN ('orange_money','mtn_money','cash','manual'))
);

CREATE INDEX IF NOT EXISTS idx_pra_active_provider
  ON public.payment_receiving_accounts (provider, is_active);

-- Grants: finance/god admins manage via authenticated; no anon access.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.payment_receiving_accounts TO authenticated;
GRANT ALL ON public.payment_receiving_accounts TO service_role;

ALTER TABLE public.payment_receiving_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Finance admins manage receiving accounts"
  ON public.payment_receiving_accounts
  FOR ALL TO authenticated
  USING (public.can_manage_wallet(auth.uid()))
  WITH CHECK (public.can_manage_wallet(auth.uid()));

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_pra_updated_at ON public.payment_receiving_accounts;
CREATE TRIGGER trg_pra_updated_at
BEFORE UPDATE ON public.payment_receiving_accounts
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 2) Link topup_requests to receiving account
ALTER TABLE public.topup_requests
  ADD COLUMN IF NOT EXISTS receiving_account_id uuid
    REFERENCES public.payment_receiving_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_topup_requests_receiving_account
  ON public.topup_requests (receiving_account_id);

-- 3) Sanitized RPC for customers — returns only safe fields
CREATE OR REPLACE FUNCTION public.get_active_payment_receiving_accounts()
RETURNS TABLE (
  id uuid,
  provider text,
  label text,
  phone_e164 text,
  public_instructions text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, provider, label, phone_e164, public_instructions
  FROM public.payment_receiving_accounts
  WHERE is_active = true
  ORDER BY provider, label;
$$;

REVOKE ALL ON FUNCTION public.get_active_payment_receiving_accounts() FROM public;
GRANT EXECUTE ON FUNCTION public.get_active_payment_receiving_accounts() TO authenticated;

-- 4) Update wallet_topup_om_create to accept & validate a receiving account
CREATE OR REPLACE FUNCTION public.wallet_topup_om_create(
  p_amount_gnf bigint,
  p_receiving_account_id uuid DEFAULT NULL
)
RETURNS public.topup_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.wallets;
  v_phone text;
  v_ref text;
  v_row public.topup_requests;
  v_acct public.payment_receiving_accounts;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  IF p_amount_gnf < 1000 THEN RAISE EXCEPTION 'Minimum top-up is 1000 GNF'; END IF;
  IF p_amount_gnf > 50000000 THEN RAISE EXCEPTION 'Maximum top-up is 50,000,000 GNF'; END IF;

  -- Resolve receiving account: explicit pick or single active Orange Money account.
  IF p_receiving_account_id IS NOT NULL THEN
    SELECT * INTO v_acct FROM public.payment_receiving_accounts
      WHERE id = p_receiving_account_id AND is_active = true;
  ELSE
    SELECT * INTO v_acct FROM public.payment_receiving_accounts
      WHERE provider = 'orange_money' AND is_active = true
      ORDER BY updated_at DESC LIMIT 1;
  END IF;
  IF v_acct.id IS NULL THEN
    RAISE EXCEPTION 'No active Orange Money receiving account configured';
  END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'client'
   LIMIT 1;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'Wallet not found'; END IF;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet is not active'; END IF;

  SELECT phone INTO v_phone FROM public.profiles WHERE user_id = v_uid LIMIT 1;

  v_ref := public.gen_topup_reference();

  INSERT INTO public.topup_requests (
    reference, client_user_id, agent_user_id, amount_gnf,
    confirmation_code, provider, user_phone, status, expires_at,
    receiving_account_id
  ) VALUES (
    v_ref, v_uid, NULL, p_amount_gnf,
    '------', 'orange_money', v_phone, 'pending'::topup_status, now() + interval '24 hours',
    v_acct.id
  ) RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.wallet_topup_om_create(bigint, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.wallet_topup_om_create(bigint, uuid) TO authenticated;
