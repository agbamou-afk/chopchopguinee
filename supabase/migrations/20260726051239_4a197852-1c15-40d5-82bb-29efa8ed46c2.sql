
ALTER TABLE public.marketplace_offers DROP CONSTRAINT IF EXISTS marketplace_offers_settlement_state_chk;
ALTER TABLE public.marketplace_offers ADD CONSTRAINT marketplace_offers_settlement_state_chk
  CHECK (settlement_state = ANY (ARRAY['pending','settled','needs_review','failed','sandbox']));
