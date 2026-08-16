
ALTER TABLE public.marketplace_offers
  ADD COLUMN IF NOT EXISTS agreed_amount_gnf bigint,
  ADD COLUMN IF NOT EXISTS agreed_by_user_id uuid,
  ADD COLUMN IF NOT EXISTS agreed_at timestamptz,
  ADD COLUMN IF NOT EXISTS current_proposer_role text NOT NULL DEFAULT 'buyer',
  ADD COLUMN IF NOT EXISTS expired_at timestamptz;

ALTER TABLE public.marketplace_offers
  DROP CONSTRAINT IF EXISTS marketplace_offers_status_chk;
ALTER TABLE public.marketplace_offers
  ADD CONSTRAINT marketplace_offers_status_chk
  CHECK (status IN ('pending','countered','accepted','rejected','withdrawn','expired'));

ALTER TABLE public.marketplace_offers
  DROP CONSTRAINT IF EXISTS marketplace_offers_proposer_chk;
ALTER TABLE public.marketplace_offers
  ADD CONSTRAINT marketplace_offers_proposer_chk
  CHECK (current_proposer_role IN ('buyer','merchant'));

CREATE OR REPLACE FUNCTION public.marche_offer_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  -- Core identity is immutable.
  IF NEW.listing_id       IS DISTINCT FROM OLD.listing_id
  OR NEW.buyer_user_id    IS DISTINCT FROM OLD.buyer_user_id
  OR NEW.merchant_user_id IS DISTINCT FROM OLD.merchant_user_id
  OR NEW.offer_amount_gnf IS DISTINCT FROM OLD.offer_amount_gnf THEN
    RAISE EXCEPTION 'OFFER_CORE_IMMUTABLE';
  END IF;

  -- A frozen agreement can never be rewritten.
  IF (OLD.agreed_amount_gnf IS NOT NULL AND NEW.agreed_amount_gnf IS DISTINCT FROM OLD.agreed_amount_gnf)
  OR (OLD.agreed_by_user_id IS NOT NULL AND NEW.agreed_by_user_id IS DISTINCT FROM OLD.agreed_by_user_id)
  OR (OLD.agreed_at         IS NOT NULL AND NEW.agreed_at         IS DISTINCT FROM OLD.agreed_at) THEN
    RAISE EXCEPTION 'AGREEMENT_IMMUTABLE';
  END IF;

  -- Agreement fields exist only for accepted offers.
  IF NEW.status <> 'accepted'
     AND (NEW.agreed_amount_gnf IS NOT NULL OR NEW.agreed_by_user_id IS NOT NULL OR NEW.agreed_at IS NOT NULL) THEN
    RAISE EXCEPTION 'AGREEMENT_REQUIRES_ACCEPTED';
  END IF;

  -- A merchant counter, once awaiting the buyer, cannot be rewritten.
  IF OLD.status = 'countered' AND NEW.counter_amount_gnf IS DISTINCT FROM OLD.counter_amount_gnf THEN
    RAISE EXCEPTION 'COUNTER_IMMUTABLE';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status IN ('accepted','rejected','withdrawn','expired') THEN
      RAISE EXCEPTION 'OFFER_TERMINAL';
    END IF;
    IF NOT (
      (OLD.status = 'pending'   AND NEW.status IN ('countered','accepted','rejected','withdrawn','expired'))
      OR (OLD.status = 'countered' AND NEW.status IN ('accepted','rejected','withdrawn','expired'))
    ) THEN
      RAISE EXCEPTION 'ILLEGAL_OFFER_TRANSITION';
    END IF;

    IF NEW.status = 'accepted' THEN
      IF NEW.agreed_amount_gnf IS NULL OR NEW.agreed_amount_gnf <= 0
         OR NEW.agreed_by_user_id IS NULL OR NEW.agreed_at IS NULL THEN
        RAISE EXCEPTION 'AGREEMENT_REQUIRED';
      END IF;
      -- Consent law: the accepting party is never the proposer of the current price.
      IF OLD.current_proposer_role = 'buyer' AND NEW.agreed_by_user_id <> OLD.merchant_user_id THEN
        RAISE EXCEPTION 'CONSENT_REQUIRED';
      END IF;
      IF OLD.current_proposer_role = 'merchant' AND NEW.agreed_by_user_id <> OLD.buyer_user_id THEN
        RAISE EXCEPTION 'CONSENT_REQUIRED';
      END IF;
      IF OLD.current_proposer_role = 'buyer'    AND NEW.agreed_amount_gnf <> OLD.offer_amount_gnf THEN
        RAISE EXCEPTION 'AGREEMENT_AMOUNT_MISMATCH';
      END IF;
      IF OLD.current_proposer_role = 'merchant' AND NEW.agreed_amount_gnf IS DISTINCT FROM OLD.counter_amount_gnf THEN
        RAISE EXCEPTION 'AGREEMENT_AMOUNT_MISMATCH';
      END IF;
    END IF;

    IF NEW.status = 'expired' AND NEW.expired_at IS NULL THEN
      NEW.expired_at := now();
    END IF;
  END IF;

  RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_marche_offer_transition_guard ON public.marketplace_offers;
CREATE TRIGGER trg_marche_offer_transition_guard
BEFORE UPDATE ON public.marketplace_offers
FOR EACH ROW EXECUTE FUNCTION public.marche_offer_transition_guard();
