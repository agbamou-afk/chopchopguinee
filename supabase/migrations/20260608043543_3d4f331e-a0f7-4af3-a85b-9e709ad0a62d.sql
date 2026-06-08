
-- ============================================================
-- Marché bargaining v0
-- ============================================================

-- 1. New pricing fields on marketplace_listings
ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS pricing_mode text NOT NULL DEFAULT 'fixed',
  ADD COLUMN IF NOT EXISTS asking_price_gnf bigint,
  ADD COLUMN IF NOT EXISTS minimum_price_gnf bigint,
  ADD COLUMN IF NOT EXISTS allow_offers boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS offer_increment_gnf bigint;

DO $$ BEGIN
  ALTER TABLE public.marketplace_listings
    ADD CONSTRAINT marketplace_listings_pricing_mode_chk
    CHECK (pricing_mode IN ('fixed','negotiable','quote'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Backfill asking_price_gnf from existing price_gnf for clarity
UPDATE public.marketplace_listings
SET asking_price_gnf = price_gnf
WHERE asking_price_gnf IS NULL AND price_gnf IS NOT NULL;

-- 2. Column-level privacy: hide minimum_price_gnf from anon + authenticated
REVOKE SELECT (minimum_price_gnf) ON public.marketplace_listings FROM anon, authenticated;
-- service_role and table owner retain full access automatically

-- 3. Helper: get_listing_minimum_price — owner/admin only
CREATE OR REPLACE FUNCTION public.get_listing_minimum_price(p_listing_id uuid)
RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  v_seller uuid;
  v_min bigint;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT seller_id, minimum_price_gnf INTO v_seller, v_min
  FROM public.marketplace_listings WHERE id = p_listing_id;
  IF v_seller IS NULL THEN RETURN NULL; END IF;
  IF v_seller = caller OR public.is_any_admin(caller) THEN
    RETURN v_min;
  END IF;
  RAISE EXCEPTION 'forbidden';
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_listing_minimum_price(uuid) TO authenticated;

-- 4. Helper: get_merchant_listing_full — owner/admin row incl. private fields
CREATE OR REPLACE FUNCTION public.get_merchant_listing_full(p_listing_id uuid)
RETURNS public.marketplace_listings
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  r public.marketplace_listings;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO r FROM public.marketplace_listings WHERE id = p_listing_id;
  IF r.id IS NULL THEN RETURN NULL; END IF;
  IF r.seller_id = caller OR public.is_any_admin(caller) THEN
    RETURN r;
  END IF;
  RAISE EXCEPTION 'forbidden';
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_merchant_listing_full(uuid) TO authenticated;

-- ============================================================
-- 5. marketplace_offers table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.marketplace_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
  merchant_store_id uuid,
  buyer_user_id uuid NOT NULL,
  merchant_user_id uuid NOT NULL,
  offer_amount_gnf bigint NOT NULL CHECK (offer_amount_gnf > 0),
  counter_amount_gnf bigint CHECK (counter_amount_gnf IS NULL OR counter_amount_gnf > 0),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','rejected','countered','withdrawn','expired')),
  buyer_message text,
  merchant_message text,
  expires_at timestamptz,
  responded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

GRANT SELECT ON public.marketplace_offers TO authenticated;
GRANT ALL ON public.marketplace_offers TO service_role;

ALTER TABLE public.marketplace_offers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Buyers read own offers" ON public.marketplace_offers
  FOR SELECT TO authenticated
  USING (buyer_user_id = auth.uid());

CREATE POLICY "Merchants read offers on own listings" ON public.marketplace_offers
  FOR SELECT TO authenticated
  USING (merchant_user_id = auth.uid());

CREATE POLICY "Admins read all offers" ON public.marketplace_offers
  FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));

-- No INSERT/UPDATE/DELETE policies: writes go through SECURITY DEFINER RPCs only.

CREATE INDEX IF NOT EXISTS marketplace_offers_listing_idx ON public.marketplace_offers(listing_id);
CREATE INDEX IF NOT EXISTS marketplace_offers_buyer_idx ON public.marketplace_offers(buyer_user_id);
CREATE INDEX IF NOT EXISTS marketplace_offers_merchant_idx ON public.marketplace_offers(merchant_user_id);

CREATE OR REPLACE FUNCTION public.tg_marketplace_offers_updated()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS marketplace_offers_updated ON public.marketplace_offers;
CREATE TRIGGER marketplace_offers_updated
  BEFORE UPDATE ON public.marketplace_offers
  FOR EACH ROW EXECUTE FUNCTION public.tg_marketplace_offers_updated();

-- ============================================================
-- 6. create_marketplace_offer
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_marketplace_offer(
  p_listing_id uuid,
  p_amount_gnf bigint,
  p_message text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  v public.marketplace_listings;
  v_store_status text;
  v_store_onb text;
  v_offer_id uuid;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF public.is_user_banned(caller) THEN
    RAISE EXCEPTION 'account blocked';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_freezes
    WHERE user_id = caller AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  ) THEN
    RAISE EXCEPTION 'account frozen';
  END IF;

  SELECT * INTO v FROM public.marketplace_listings WHERE id = p_listing_id;
  IF v.id IS NULL THEN RAISE EXCEPTION 'listing not found'; END IF;
  IF v.seller_id = caller THEN RAISE EXCEPTION 'cannot offer on own listing'; END IF;
  IF v.status <> 'active' OR v.visibility <> 'public' THEN
    RAISE EXCEPTION 'listing not available';
  END IF;
  IF NOT v.allow_offers OR v.pricing_mode NOT IN ('negotiable','quote') THEN
    RAISE EXCEPTION 'offers not allowed';
  END IF;
  IF coalesce(v.quantity_in_stock, 0) <= 0 THEN
    RAISE EXCEPTION 'out of stock';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN
    RAISE EXCEPTION 'invalid amount';
  END IF;

  IF v.store_id IS NOT NULL THEN
    SELECT status, onboarding_status INTO v_store_status, v_store_onb
    FROM public.merchant_stores WHERE id = v.store_id;
    IF v_store_onb <> 'approved' OR v_store_status NOT IN ('active','paused') THEN
      RAISE EXCEPTION 'store not active';
    END IF;
  END IF;

  -- Prevent duplicate pending offers from same buyer
  IF EXISTS (
    SELECT 1 FROM public.marketplace_offers
    WHERE listing_id = p_listing_id
      AND buyer_user_id = caller
      AND status IN ('pending','countered')
  ) THEN
    RAISE EXCEPTION 'pending offer already exists';
  END IF;

  INSERT INTO public.marketplace_offers (
    listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
    offer_amount_gnf, buyer_message, expires_at
  ) VALUES (
    p_listing_id, v.store_id, caller, v.seller_id,
    p_amount_gnf, nullif(trim(p_message), ''), now() + interval '7 days'
  ) RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_marketplace_offer(uuid, bigint, text) TO authenticated;

-- ============================================================
-- 7. merchant_respond_marketplace_offer
-- ============================================================
CREATE OR REPLACE FUNCTION public.merchant_respond_marketplace_offer(
  p_offer_id uuid,
  p_action text,
  p_counter_amount_gnf bigint DEFAULT NULL,
  p_message text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marketplace_offers;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF public.is_user_banned(caller) THEN RAISE EXCEPTION 'account blocked'; END IF;
  IF EXISTS (
    SELECT 1 FROM public.account_freezes
    WHERE user_id = caller AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  ) THEN RAISE EXCEPTION 'account frozen'; END IF;

  SELECT * INTO o FROM public.marketplace_offers WHERE id = p_offer_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'offer not found'; END IF;
  IF o.merchant_user_id <> caller AND NOT public.is_any_admin(caller) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF o.status NOT IN ('pending','countered') THEN
    RAISE EXCEPTION 'offer closed';
  END IF;

  IF p_action = 'accept' THEN
    UPDATE public.marketplace_offers
      SET status = 'accepted', merchant_message = nullif(trim(p_message), ''),
          responded_at = now()
      WHERE id = p_offer_id;
  ELSIF p_action = 'reject' THEN
    UPDATE public.marketplace_offers
      SET status = 'rejected', merchant_message = nullif(trim(p_message), ''),
          responded_at = now()
      WHERE id = p_offer_id;
  ELSIF p_action = 'counter' THEN
    IF p_counter_amount_gnf IS NULL OR p_counter_amount_gnf <= 0 THEN
      RAISE EXCEPTION 'invalid counter amount';
    END IF;
    UPDATE public.marketplace_offers
      SET status = 'countered',
          counter_amount_gnf = p_counter_amount_gnf,
          merchant_message = nullif(trim(p_message), ''),
          responded_at = now()
      WHERE id = p_offer_id;
  ELSE
    RAISE EXCEPTION 'invalid action';
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.merchant_respond_marketplace_offer(uuid, text, bigint, text) TO authenticated;

-- ============================================================
-- 8. withdraw_marketplace_offer
-- ============================================================
CREATE OR REPLACE FUNCTION public.withdraw_marketplace_offer(p_offer_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marketplace_offers;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO o FROM public.marketplace_offers WHERE id = p_offer_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'offer not found'; END IF;
  IF o.buyer_user_id <> caller THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF o.status NOT IN ('pending','countered') THEN
    RAISE EXCEPTION 'offer closed';
  END IF;
  UPDATE public.marketplace_offers
    SET status = 'withdrawn', responded_at = now()
    WHERE id = p_offer_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.withdraw_marketplace_offer(uuid) TO authenticated;
