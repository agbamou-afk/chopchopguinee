-- Node 5 · A4 — truthful abandonment terminal states (schema only, no behaviour yet)

ALTER TYPE public.driver_status ADD VALUE IF NOT EXISTS 'withdrawn';
ALTER TYPE public.driver_application_decision ADD VALUE IF NOT EXISTS 'withdrawn';

ALTER TABLE public.merchant_stores DROP CONSTRAINT IF EXISTS merchant_stores_onboarding_status_check;
ALTER TABLE public.merchant_stores ADD CONSTRAINT merchant_stores_onboarding_status_check
  CHECK (onboarding_status = ANY (ARRAY['draft','submitted','in_review','needs_info','approved','rejected','withdrawn']));

-- One ACTIVE store per merchant owner. Archived (abandoned) stores stay as history
-- and no longer consume the ownership slot.
ALTER TABLE public.merchant_stores DROP CONSTRAINT IF EXISTS merchant_stores_owner_user_id_key;
DROP INDEX IF EXISTS public.merchant_stores_owner_user_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS merchant_stores_owner_active_uidx
  ON public.merchant_stores (owner_user_id)
  WHERE status <> 'archived';