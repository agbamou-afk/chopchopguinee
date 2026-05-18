
DO $$ BEGIN
  CREATE TYPE public.listing_interest_kind AS ENUM ('availability','delivery','reservation','offer');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.listing_interest_state AS ENUM ('pending','available','reserved','sold','responded','declined');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.listing_interests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL,
  buyer_id uuid NOT NULL,
  seller_id uuid NOT NULL,
  kind public.listing_interest_kind NOT NULL DEFAULT 'availability',
  state public.listing_interest_state NOT NULL DEFAULT 'pending',
  note text,
  response text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_listing_interests_listing ON public.listing_interests(listing_id);
CREATE INDEX IF NOT EXISTS idx_listing_interests_seller_state ON public.listing_interests(seller_id, state);
CREATE INDEX IF NOT EXISTS idx_listing_interests_buyer ON public.listing_interests(buyer_id);

ALTER TABLE public.listing_interests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Buyer creates own interest"
  ON public.listing_interests FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = buyer_id);

CREATE POLICY "Parties view own interests"
  ON public.listing_interests FOR SELECT TO authenticated
  USING (auth.uid() = buyer_id OR auth.uid() = seller_id OR has_role(auth.uid(),'admin'::app_role));

CREATE POLICY "Seller updates interest"
  ON public.listing_interests FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id OR has_role(auth.uid(),'admin'::app_role))
  WITH CHECK (auth.uid() = seller_id OR has_role(auth.uid(),'admin'::app_role));

CREATE POLICY "Buyer cancels own pending"
  ON public.listing_interests FOR DELETE TO authenticated
  USING (auth.uid() = buyer_id AND state = 'pending');

CREATE TRIGGER trg_listing_interests_updated_at
  BEFORE UPDATE ON public.listing_interests
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
