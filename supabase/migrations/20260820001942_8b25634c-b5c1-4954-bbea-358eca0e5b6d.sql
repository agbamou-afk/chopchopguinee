-- R8 provenance micro-closeout: merchant-ask event identity + trigger discipline

CREATE OR REPLACE FUNCTION public.marche_price_ingest_merchant_ask(p_listing_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  l public.marketplace_listings;
  s public.merchant_stores;
  v_price bigint;
  v_id uuid;
  v_ref text;
  v_last_price bigint;
  v_seq bigint;
BEGIN
  SELECT * INTO l FROM public.marketplace_listings WHERE id = p_listing_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ingested', false, 'reason', 'LISTING_NOT_FOUND'); END IF;
  IF l.kind <> 'merchant'::listing_kind OR l.store_id IS NULL THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_STORE_REQUIRED');
  END IF;
  IF l.visibility <> 'public' OR l.status <> 'active'::listing_status THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_ASK_NOT_PUBLISHED');
  END IF;
  SELECT * INTO s FROM public.merchant_stores WHERE id = l.store_id;
  IF s.onboarding_status IS DISTINCT FROM 'approved' OR COALESCE(s.status,'') <> 'active' THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'STORE_NOT_APPROVED');
  END IF;
  IF l.staple_purchase_option_id IS NULL THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_ASK_NOT_CANONICAL');
  END IF;
  v_price := COALESCE(l.asking_price_gnf, l.price_gnf);
  IF COALESCE(v_price, 0) <= 0 THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_ASK_NO_PRICE');
  END IF;

  -- Effective-event identity: the CURRENT effective ask of this listing is the
  -- latest recorded merchant_ask observation. A retry / idle re-save observes the
  -- same effective event (idempotent). A change of the effective ask -- including a
  -- change BACK to a previously observed numeric value -- is a NEW event.
  SELECT o.raw_amount_gnf INTO v_last_price
    FROM public.marche_procurement_price_observations o
   WHERE o.listing_id = l.id AND o.source_kind = 'merchant_ask'
   ORDER BY o.observed_at DESC, o.ingested_at DESC
   LIMIT 1;

  IF v_last_price IS NOT NULL AND v_last_price = v_price THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'ALREADY_OBSERVED');
  END IF;

  -- Monotonic per-listing event sequence; never reuses a retired identity.
  SELECT COALESCE(MAX(NULLIF(split_part(o.source_ref, ':', 3), '')::bigint), 0)
    INTO v_seq
    FROM public.marche_procurement_price_observations o
   WHERE o.listing_id = l.id AND o.source_kind = 'merchant_ask'
     AND o.source_ref LIKE 'listing:' || l.id::text || ':%'
     AND split_part(o.source_ref, ':', 3) ~ '^[0-9]+$';
  v_seq := COALESCE(v_seq, 0) + 1;

  v_ref := 'listing:' || l.id::text || ':' || v_seq::text;
  v_id := public._marche_price_record(
    l.staple_purchase_option_id, 'merchant_ask', 'merchant_ask', v_ref,
    v_price, 1, clock_timestamp(), NULL, l.store_id, l.id,
    COALESCE(s.commune, l.commune), COALESCE(s.market_name, s.district), NULL);

  RETURN jsonb_build_object('ingested', v_id IS NOT NULL, 'observation_id', v_id,
                            'event_seq', v_seq,
                            'reason', CASE WHEN v_id IS NULL THEN 'ALREADY_OBSERVED' ELSE NULL END);
END $function$;

-- Trigger discipline: only fire when merchant-ask observation truth can change.
DROP TRIGGER IF EXISTS trg_marche_price_merchant_ask ON public.marketplace_listings;

CREATE TRIGGER trg_marche_price_merchant_ask_ins
AFTER INSERT ON public.marketplace_listings
FOR EACH ROW EXECUTE FUNCTION public._marche_price_listing_ask_trg();

CREATE TRIGGER trg_marche_price_merchant_ask_upd
AFTER UPDATE ON public.marketplace_listings
FOR EACH ROW
WHEN (
  OLD.asking_price_gnf IS DISTINCT FROM NEW.asking_price_gnf
  OR OLD.price_gnf IS DISTINCT FROM NEW.price_gnf
  OR OLD.status IS DISTINCT FROM NEW.status
  OR OLD.visibility IS DISTINCT FROM NEW.visibility
  OR OLD.store_id IS DISTINCT FROM NEW.store_id
  OR OLD.kind IS DISTINCT FROM NEW.kind
  OR OLD.staple_purchase_option_id IS DISTINCT FROM NEW.staple_purchase_option_id
)
EXECUTE FUNCTION public._marche_price_listing_ask_trg();