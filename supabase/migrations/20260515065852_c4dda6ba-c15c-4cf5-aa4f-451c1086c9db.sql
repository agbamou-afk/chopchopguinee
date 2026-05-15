
-- Merchants table
CREATE TABLE IF NOT EXISTS public.merchants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  name text NOT NULL,
  category text,
  address text,
  city text NOT NULL DEFAULT 'Conakry',
  lat double precision,
  lng double precision,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_merchants_owner ON public.merchants(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_merchants_status ON public.merchants(status);

ALTER TABLE public.merchants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can view active merchants" ON public.merchants;
CREATE POLICY "Anyone can view active merchants"
  ON public.merchants FOR SELECT
  USING (status = 'active' OR owner_user_id = auth.uid() OR has_role(auth.uid(),'admin'));

DROP POLICY IF EXISTS "Owner manages own merchant" ON public.merchants;
CREATE POLICY "Owner manages own merchant"
  ON public.merchants FOR ALL
  USING (owner_user_id = auth.uid())
  WITH CHECK (owner_user_id = auth.uid());

DROP POLICY IF EXISTS "Admins manage merchants" ON public.merchants;
CREATE POLICY "Admins manage merchants"
  ON public.merchants FOR ALL
  USING (has_role(auth.uid(),'admin'))
  WITH CHECK (has_role(auth.uid(),'admin'));

-- Updated-at trigger
CREATE OR REPLACE FUNCTION public.merchants_touch_updated()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_merchants_touch_updated ON public.merchants;
CREATE TRIGGER trg_merchants_touch_updated
  BEFORE UPDATE ON public.merchants
  FOR EACH ROW EXECUTE FUNCTION public.merchants_touch_updated();

-- Ensure merchant wallet exists for the merchant's owner
CREATE OR REPLACE FUNCTION public.merchant_ensure_wallet(p_merchant_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner uuid;
  v_wid uuid;
BEGIN
  SELECT owner_user_id INTO v_owner FROM public.merchants WHERE id = p_merchant_id;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'merchant_not_found'; END IF;

  SELECT id INTO v_wid
  FROM public.wallets
  WHERE owner_user_id = v_owner AND party_type = 'merchant'::party_type;

  IF v_wid IS NULL THEN
    INSERT INTO public.wallets(owner_user_id, party_type)
    VALUES (v_owner, 'merchant'::party_type)
    RETURNING id INTO v_wid;
  END IF;

  RETURN v_wid;
END $$;

GRANT EXECUTE ON FUNCTION public.merchant_ensure_wallet(uuid) TO authenticated;

-- Pay a merchant from the caller's CHOPWallet
CREATE OR REPLACE FUNCTION public.wallet_pay_merchant(
  p_merchant_id uuid,
  p_amount_gnf bigint,
  p_description text DEFAULT NULL
) RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_merchant public.merchants;
  v_from public.wallets;
  v_to_wid uuid;
  v_to public.wallets;
  v_tx public.wallet_transactions;
  v_ref text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;

  SELECT * INTO v_merchant FROM public.merchants
    WHERE id = p_merchant_id AND status = 'active';
  IF v_merchant.id IS NULL THEN RAISE EXCEPTION 'merchant_not_found'; END IF;
  IF v_merchant.owner_user_id IS NULL THEN RAISE EXCEPTION 'merchant_misconfigured'; END IF;
  IF v_merchant.owner_user_id = v_uid THEN RAISE EXCEPTION 'cannot_pay_self'; END IF;

  v_to_wid := public.merchant_ensure_wallet(p_merchant_id);

  SELECT * INTO v_from FROM public.wallets
    WHERE owner_user_id = v_uid AND party_type = 'client'::party_type
    FOR UPDATE;
  IF v_from.id IS NULL THEN RAISE EXCEPTION 'wallet_not_found'; END IF;
  IF v_from.balance_gnf - v_from.held_gnf < p_amount_gnf THEN
    RAISE EXCEPTION 'insufficient_funds';
  END IF;

  SELECT * INTO v_to FROM public.wallets WHERE id = v_to_wid FOR UPDATE;

  UPDATE public.wallets
    SET balance_gnf = balance_gnf - p_amount_gnf, updated_at = now()
    WHERE id = v_from.id;
  UPDATE public.wallets
    SET balance_gnf = balance_gnf + p_amount_gnf, updated_at = now()
    WHERE id = v_to.id;

  v_ref := 'CHOPPAY-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));

  INSERT INTO public.wallet_transactions(
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id,
    related_entity, description, completed_at, metadata
  ) VALUES (
    v_ref, 'payment'::txn_type, 'completed'::txn_status, p_amount_gnf,
    v_from.id, v_to.id, v_uid,
    'merchant:' || p_merchant_id,
    coalesce(p_description, 'Paiement CHOPPay · ' || v_merchant.name),
    now(),
    jsonb_build_object(
      'merchant_id', p_merchant_id,
      'merchant_name', v_merchant.name,
      'channel', 'qr'
    )
  ) RETURNING * INTO v_tx;

  RETURN v_tx;
END $$;

GRANT EXECUTE ON FUNCTION public.wallet_pay_merchant(uuid,bigint,text) TO authenticated;

-- Demo merchants (no owner attached yet — admins can claim/edit later)
INSERT INTO public.merchants(name, category, address) VALUES
  ('Le Damier',         'Restaurant', 'Kaloum, Conakry'),
  ('Pharmacie Niger',   'Pharmacie',  'Madina, Conakry'),
  ('Boutique Kaba',     'Boutique',   'Ratoma, Conakry'),
  ('Marché Madina',     'Vendeur',    'Madina, Conakry')
ON CONFLICT DO NOTHING;
