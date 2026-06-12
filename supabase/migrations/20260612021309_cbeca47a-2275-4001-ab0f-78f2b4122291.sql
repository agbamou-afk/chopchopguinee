
-- =========================================================
-- Phase 7A — Marché Accepted-Offer CHOPPay Authorization
-- =========================================================

-- 1) Payment columns on marketplace_offers
ALTER TABLE public.marketplace_offers
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'unpaid',
  ADD COLUMN IF NOT EXISTS payment_intent_id uuid NULL,
  ADD COLUMN IF NOT EXISTS authorized_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS captured_tx_id uuid NULL,
  ADD COLUMN IF NOT EXISTS settlement_tx_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'marketplace_offers_payment_status_chk'
  ) THEN
    ALTER TABLE public.marketplace_offers
      ADD CONSTRAINT marketplace_offers_payment_status_chk
      CHECK (payment_status IN ('unpaid','pending','authorized','paid','failed','refunded','cancelled'));
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS marketplace_offers_payment_status_idx
  ON public.marketplace_offers(payment_status, created_at DESC);

-- 2) Trigger: protect payment_status writes from client
CREATE OR REPLACE FUNCTION public.prevent_unsafe_marketplace_offer_payment_status_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_new text;
  v_old text;
  v_caller text;
BEGIN
  v_new := NEW.payment_status;
  v_old := COALESCE(OLD.payment_status, '');

  IF v_new IS NOT DISTINCT FROM v_old THEN
    RETURN NEW;
  END IF;

  v_caller := current_user;
  IF v_caller IN ('service_role', 'postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS NOT NULL AND public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN NEW;
  END IF;

  IF v_new IN ('paid','refunded','captured','confirmed') THEN
    RAISE EXCEPTION 'payment_status_backend_only: cannot set payment_status=% from client', v_new
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_marketplace_offers_protect_payment_status ON public.marketplace_offers;
CREATE TRIGGER trg_marketplace_offers_protect_payment_status
BEFORE UPDATE OF payment_status ON public.marketplace_offers
FOR EACH ROW EXECUTE FUNCTION public.prevent_unsafe_marketplace_offer_payment_status_update();

-- 3) Buyer authorization RPC
CREATE OR REPLACE FUNCTION public.marche_create_offer_payment_intent(p_offer_id uuid)
RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_offer  public.marketplace_offers;
  v_listing public.marketplace_listings;
  v_amount bigint;
  v_store_id uuid;
  v_intent public.payment_intents;
  v_new_pay text;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_offer FROM public.marketplace_offers WHERE id = p_offer_id;
  IF v_offer.id IS NULL THEN
    RAISE EXCEPTION 'offer_not_found';
  END IF;

  IF v_offer.buyer_user_id <> v_caller THEN
    RAISE EXCEPTION 'forbidden_not_buyer' USING ERRCODE = '42501';
  END IF;

  IF v_offer.status NOT IN ('accepted') THEN
    RAISE EXCEPTION 'offer_not_accepted';
  END IF;

  IF v_offer.payment_status IN ('authorized','paid') THEN
    -- Idempotent: return existing intent if present
    IF v_offer.payment_intent_id IS NOT NULL THEN
      SELECT * INTO v_intent FROM public.payment_intents WHERE id = v_offer.payment_intent_id;
      IF v_intent.id IS NOT NULL THEN RETURN v_intent; END IF;
    END IF;
    RAISE EXCEPTION 'offer_already_paid';
  END IF;

  -- Accepted amount = counter if present, else the buyer's offer amount.
  v_amount := COALESCE(v_offer.counter_amount_gnf, v_offer.offer_amount_gnf);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'invalid_amount';
  END IF;

  SELECT * INTO v_listing FROM public.marketplace_listings WHERE id = v_offer.listing_id;
  IF v_listing.id IS NULL THEN
    RAISE EXCEPTION 'listing_not_found';
  END IF;
  IF v_listing.status::text IN ('sold','cancelled','removed') THEN
    RAISE EXCEPTION 'listing_unavailable';
  END IF;

  v_store_id := COALESCE(v_offer.merchant_store_id, v_listing.store_id);

  -- Create / reuse intent via the shared CHOPPay rail.
  v_intent := public.choppay_create_payment_intent(
    p_source_module     := 'marketplace',
    p_source_id         := v_offer.id,
    p_amount_gnf        := v_amount,
    p_purpose           := 'marche_payment'::payment_purpose,
    p_merchant_store_id := v_store_id,
    p_payee_user_id     := v_offer.merchant_user_id,
    p_description       := 'Paiement Marché',
    p_metadata          := jsonb_build_object(
      'offer_id',         v_offer.id,
      'listing_id',       v_listing.id,
      'listing_title',    v_listing.title,
      'merchant_store_id', v_store_id,
      'seller_user_id',   v_offer.merchant_user_id,
      'buyer_user_id',    v_offer.buyer_user_id,
      'amount_gnf',       v_amount
    ),
    p_use_wallet        := true
  );

  v_new_pay := CASE v_intent.state::text
    WHEN 'processing' THEN 'authorized'
    WHEN 'confirmed'  THEN 'authorized'  -- never let client see 'paid' from this path
    WHEN 'failed'     THEN 'failed'
    WHEN 'pending'    THEN 'pending'
    ELSE v_offer.payment_status
  END;

  UPDATE public.marketplace_offers
     SET payment_intent_id = v_intent.id,
         payment_status    = v_new_pay,
         authorized_at     = CASE WHEN v_new_pay = 'authorized' THEN now() ELSE authorized_at END,
         updated_at        = now()
   WHERE id = v_offer.id;

  RETURN v_intent;
END;
$function$;

REVOKE ALL ON FUNCTION public.marche_create_offer_payment_intent(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marche_create_offer_payment_intent(uuid) TO authenticated;

-- 4) Admin preview of Marché payment intents
CREATE OR REPLACE FUNCTION public.admin_preview_marche_payment_intents(p_limit integer DEFAULT 100)
RETURNS TABLE(
  offer_id uuid,
  listing_id uuid,
  listing_title text,
  buyer_user_id uuid,
  merchant_user_id uuid,
  merchant_store_id uuid,
  amount_gnf bigint,
  offer_status text,
  payment_status text,
  payment_intent_id uuid,
  payment_intent_state payment_state,
  wallet_hold_tx_id uuid,
  captured_tx_id uuid,
  settlement_tx_id uuid,
  created_at timestamptz,
  authorized_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.is_any_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden: admin required' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT o.id, o.listing_id, l.title, o.buyer_user_id, o.merchant_user_id,
         COALESCE(o.merchant_store_id, l.store_id), 
         COALESCE(o.counter_amount_gnf, o.offer_amount_gnf),
         o.status, o.payment_status, o.payment_intent_id,
         pi.state, pi.wallet_hold_tx_id, pi.captured_tx_id, pi.settlement_tx_id,
         o.created_at, o.authorized_at
    FROM public.marketplace_offers o
    LEFT JOIN public.marketplace_listings l ON l.id = o.listing_id
    LEFT JOIN public.payment_intents pi ON pi.id = o.payment_intent_id
   WHERE o.status = 'accepted'
      OR o.payment_status <> 'unpaid'
   ORDER BY o.created_at DESC
   LIMIT COALESCE(p_limit, 100);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_preview_marche_payment_intents(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_preview_marche_payment_intents(integer) TO authenticated;
