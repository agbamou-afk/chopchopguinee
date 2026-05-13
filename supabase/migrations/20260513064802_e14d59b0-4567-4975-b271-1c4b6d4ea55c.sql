
-- ENUMS
CREATE TYPE public.listing_kind AS ENUM ('merchant', 'community', 'service');
CREATE TYPE public.listing_status AS ENUM ('active', 'sold', 'paused', 'removed');
CREATE TYPE public.report_status AS ENUM ('open', 'reviewed', 'actioned', 'dismissed');
CREATE TYPE public.message_kind AS ENUM ('text', 'image', 'location', 'quick_reply');

-- LISTINGS
CREATE TABLE public.marketplace_listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL,
  kind listing_kind NOT NULL DEFAULT 'community',
  category text NOT NULL,
  title text NOT NULL,
  description text,
  price_gnf bigint,
  is_negotiable boolean NOT NULL DEFAULT false,
  is_urgent boolean NOT NULL DEFAULT false,
  delivery_available boolean NOT NULL DEFAULT false,
  condition text,
  neighborhood text,
  commune text,
  landmark text,
  status listing_status NOT NULL DEFAULT 'active',
  view_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_listings_status_created ON public.marketplace_listings (status, created_at DESC);
CREATE INDEX idx_listings_category ON public.marketplace_listings (category);
CREATE INDEX idx_listings_seller ON public.marketplace_listings (seller_id);
ALTER TABLE public.marketplace_listings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view active listings"
  ON public.marketplace_listings FOR SELECT
  USING (status = 'active' OR seller_id = auth.uid() OR has_role(auth.uid(), 'admin'));
CREATE POLICY "Sellers create own listings"
  ON public.marketplace_listings FOR INSERT
  WITH CHECK (auth.uid() = seller_id);
CREATE POLICY "Sellers update own listings"
  ON public.marketplace_listings FOR UPDATE
  USING (auth.uid() = seller_id) WITH CHECK (auth.uid() = seller_id);
CREATE POLICY "Sellers delete own listings"
  ON public.marketplace_listings FOR DELETE
  USING (auth.uid() = seller_id);
CREATE POLICY "Admins manage listings"
  ON public.marketplace_listings FOR ALL
  USING (has_role(auth.uid(), 'admin')) WITH CHECK (has_role(auth.uid(), 'admin'));

CREATE TRIGGER trg_listings_updated
  BEFORE UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- IMAGES
CREATE TABLE public.listing_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
  url text NOT NULL,
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_listing_images_listing ON public.listing_images (listing_id, position);
ALTER TABLE public.listing_images ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can view listing images"
  ON public.listing_images FOR SELECT USING (true);
CREATE POLICY "Sellers manage own listing images"
  ON public.listing_images FOR ALL
  USING (EXISTS (SELECT 1 FROM public.marketplace_listings l WHERE l.id = listing_id AND l.seller_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.marketplace_listings l WHERE l.id = listing_id AND l.seller_id = auth.uid()));
CREATE POLICY "Admins manage listing images"
  ON public.listing_images FOR ALL
  USING (has_role(auth.uid(), 'admin')) WITH CHECK (has_role(auth.uid(), 'admin'));

-- CONVERSATIONS
CREATE TABLE public.conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
  buyer_id uuid NOT NULL,
  seller_id uuid NOT NULL,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (listing_id, buyer_id)
);
CREATE INDEX idx_conv_buyer ON public.conversations (buyer_id, last_message_at DESC);
CREATE INDEX idx_conv_seller ON public.conversations (seller_id, last_message_at DESC);
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Participants view conversations"
  ON public.conversations FOR SELECT
  USING (auth.uid() IN (buyer_id, seller_id) OR has_role(auth.uid(), 'admin'));
CREATE POLICY "Buyers create conversations"
  ON public.conversations FOR INSERT
  WITH CHECK (auth.uid() = buyer_id);
CREATE POLICY "Admins manage conversations"
  ON public.conversations FOR ALL
  USING (has_role(auth.uid(), 'admin')) WITH CHECK (has_role(auth.uid(), 'admin'));

-- MESSAGES
CREATE TABLE public.messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  kind message_kind NOT NULL DEFAULT 'text',
  body text,
  attachment_url text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_conv ON public.messages (conversation_id, created_at);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Participants view messages"
  ON public.messages FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = conversation_id AND (auth.uid() IN (c.buyer_id, c.seller_id) OR has_role(auth.uid(), 'admin'))));
CREATE POLICY "Participants send messages"
  ON public.messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id AND EXISTS (SELECT 1 FROM public.conversations c WHERE c.id = conversation_id AND auth.uid() IN (c.buyer_id, c.seller_id)));
CREATE POLICY "Admins manage messages"
  ON public.messages FOR ALL
  USING (has_role(auth.uid(), 'admin')) WITH CHECK (has_role(auth.uid(), 'admin'));

-- Bump conversation last_message_at on new message
CREATE OR REPLACE FUNCTION public.touch_conversation_on_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.conversations SET last_message_at = NEW.created_at WHERE id = NEW.conversation_id;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_messages_touch_conv
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.touch_conversation_on_message();

-- SAVED LISTINGS
CREATE TABLE public.saved_listings (
  user_id uuid NOT NULL,
  listing_id uuid NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, listing_id)
);
ALTER TABLE public.saved_listings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users view own saved" ON public.saved_listings FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own saved" ON public.saved_listings FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users delete own saved" ON public.saved_listings FOR DELETE USING (auth.uid() = user_id);

-- REPORTS
CREATE TABLE public.listing_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES public.marketplace_listings(id) ON DELETE CASCADE,
  reporter_id uuid,
  reason text NOT NULL,
  details text,
  status report_status NOT NULL DEFAULT 'open',
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.listing_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated can report"
  ON public.listing_reports FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = reporter_id);
CREATE POLICY "Reporters view own reports"
  ON public.listing_reports FOR SELECT
  USING (auth.uid() = reporter_id OR has_role(auth.uid(), 'admin'));
CREATE POLICY "Admins manage reports"
  ON public.listing_reports FOR ALL
  USING (has_role(auth.uid(), 'admin')) WITH CHECK (has_role(auth.uid(), 'admin'));

-- SERVICE PROFILES
CREATE TABLE public.service_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  profession text NOT NULL,
  bio text,
  service_areas text[] NOT NULL DEFAULT '{}',
  pricing_range text,
  portfolio_urls text[] NOT NULL DEFAULT '{}',
  availability text,
  rating numeric NOT NULL DEFAULT 0,
  response_rate numeric NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.service_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone view services" ON public.service_profiles FOR SELECT USING (true);
CREATE POLICY "Users manage own service" ON public.service_profiles FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Admins manage services" ON public.service_profiles FOR ALL
  USING (has_role(auth.uid(), 'admin')) WITH CHECK (has_role(auth.uid(), 'admin'));
CREATE TRIGGER trg_service_profiles_updated
  BEFORE UPDATE ON public.service_profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- STORAGE BUCKET for listing photos
INSERT INTO storage.buckets (id, name, public) VALUES ('marche-listings', 'marche-listings', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Listing images public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'marche-listings');
CREATE POLICY "Users upload own listing images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'marche-listings' AND auth.uid()::text = (storage.foldername(name))[1]);
CREATE POLICY "Users update own listing images"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'marche-listings' AND auth.uid()::text = (storage.foldername(name))[1]);
CREATE POLICY "Users delete own listing images"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'marche-listings' AND auth.uid()::text = (storage.foldername(name))[1]);
