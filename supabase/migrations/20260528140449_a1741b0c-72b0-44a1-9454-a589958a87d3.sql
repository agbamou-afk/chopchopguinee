
-- 1) Protect sensitive columns on marketplace_listings from seller self-edits
CREATE OR REPLACE FUNCTION public.prevent_seller_protected_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Admins bypass
  IF public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN NEW;
  END IF;

  IF NEW.promoted     IS DISTINCT FROM OLD.promoted     THEN RAISE EXCEPTION 'Not allowed to modify promoted'; END IF;
  IF NEW.status       IS DISTINCT FROM OLD.status       THEN RAISE EXCEPTION 'Not allowed to modify status'; END IF;
  IF NEW.sold_count   IS DISTINCT FROM OLD.sold_count   THEN RAISE EXCEPTION 'Not allowed to modify sold_count'; END IF;
  IF NEW.view_count   IS DISTINCT FROM OLD.view_count   THEN RAISE EXCEPTION 'Not allowed to modify view_count'; END IF;
  IF NEW.photo_count  IS DISTINCT FROM OLD.photo_count  THEN RAISE EXCEPTION 'Not allowed to modify photo_count'; END IF;
  IF NEW.seller_id    IS DISTINCT FROM OLD.seller_id    THEN RAISE EXCEPTION 'Not allowed to modify seller_id'; END IF;
  IF NEW.store_id     IS DISTINCT FROM OLD.store_id     THEN RAISE EXCEPTION 'Not allowed to modify store_id'; END IF;
  IF NEW.kind         IS DISTINCT FROM OLD.kind         THEN RAISE EXCEPTION 'Not allowed to modify kind'; END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_marketplace_listings_protect_cols ON public.marketplace_listings;
CREATE TRIGGER trg_marketplace_listings_protect_cols
BEFORE UPDATE ON public.marketplace_listings
FOR EACH ROW EXECUTE FUNCTION public.prevent_seller_protected_columns();

-- 2) Restrict realtime.messages INSERT to user-scoped channels
DROP POLICY IF EXISTS "Allow authenticated to write public channels" ON realtime.messages;
DROP POLICY IF EXISTS "authenticated can write public channels" ON realtime.messages;
DROP POLICY IF EXISTS "Public channel write" ON realtime.messages;

CREATE POLICY "Authenticated write to own user channel"
ON realtime.messages
FOR INSERT
TO authenticated
WITH CHECK (
  realtime.topic() = ('user:' || auth.uid()::text)
);
