
-- ============================================================
-- Phase 1 — Merchant account foundation
-- ============================================================

-- 1. Columns (additive)
ALTER TABLE public.merchant_stores
  ADD COLUMN IF NOT EXISTS merchant_account_number text,
  ADD COLUMN IF NOT EXISTS merchant_qr_payload text,
  ADD COLUMN IF NOT EXISTS commune text,
  ADD COLUMN IF NOT EXISTS market_name text,
  ADD COLUMN IF NOT EXISTS landmark_note text,
  ADD COLUMN IF NOT EXISTS location_capture_method text,
  ADD COLUMN IF NOT EXISTS product_categories text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS wants_marketplace boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS wants_food boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS wants_wallet_agent boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS service_agent_requested boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS service_agent_status text NOT NULL DEFAULT 'not_requested',
  ADD COLUMN IF NOT EXISTS service_agent_notes text,
  ADD COLUMN IF NOT EXISTS service_agent_decided_at timestamptz,
  ADD COLUMN IF NOT EXISTS service_agent_decided_by uuid,
  ADD COLUMN IF NOT EXISTS onboarding_branch text NOT NULL DEFAULT 'merchant',
  ADD COLUMN IF NOT EXISTS merchant_status text NOT NULL DEFAULT 'pending';

-- Validation
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'merchant_stores_service_agent_status_chk') THEN
    ALTER TABLE public.merchant_stores
      ADD CONSTRAINT merchant_stores_service_agent_status_chk
      CHECK (service_agent_status IN ('not_requested','pending','approved','rejected','disabled'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'merchant_stores_merchant_status_chk') THEN
    ALTER TABLE public.merchant_stores
      ADD CONSTRAINT merchant_stores_merchant_status_chk
      CHECK (merchant_status IN ('pending','active','needs_info','suspended','rejected'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'merchant_stores_location_capture_method_chk') THEN
    ALTER TABLE public.merchant_stores
      ADD CONSTRAINT merchant_stores_location_capture_method_chk
      CHECK (location_capture_method IS NULL OR location_capture_method IN ('gps','map_pin','manual'));
  END IF;
END $$;

-- 2. Unique index on account number
CREATE UNIQUE INDEX IF NOT EXISTS merchant_stores_account_number_unique
  ON public.merchant_stores (merchant_account_number)
  WHERE merchant_account_number IS NOT NULL;

-- 3. Sequence + generator
CREATE SEQUENCE IF NOT EXISTS public.merchant_account_seq START 1;

CREATE OR REPLACE FUNCTION public.generate_merchant_account_number(_commune text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  prefix text;
  seq_val bigint;
BEGIN
  prefix := upper(regexp_replace(coalesce(_commune,''), '[^A-Za-z]', '', 'g'));
  IF length(prefix) < 3 THEN
    prefix := rpad(coalesce(nullif(prefix,''), 'GUI'), 3, 'X');
  ELSE
    prefix := substring(prefix from 1 for 3);
  END IF;
  seq_val := nextval('public.merchant_account_seq');
  RETURN 'CHM-' || prefix || '-' || lpad(seq_val::text, 6, '0');
END;
$$;

-- 4. Auto-assign on insert
CREATE OR REPLACE FUNCTION public.merchant_stores_assign_account_number()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.merchant_account_number IS NULL THEN
    NEW.merchant_account_number := public.generate_merchant_account_number(NEW.commune);
  END IF;
  IF NEW.merchant_qr_payload IS NULL THEN
    NEW.merchant_qr_payload := 'chopchop://merchant/' || NEW.merchant_account_number;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_merchant_stores_assign_account_number ON public.merchant_stores;
CREATE TRIGGER trg_merchant_stores_assign_account_number
  BEFORE INSERT ON public.merchant_stores
  FOR EACH ROW EXECUTE FUNCTION public.merchant_stores_assign_account_number();

-- 5. Backfill existing rows
UPDATE public.merchant_stores
   SET merchant_account_number = public.generate_merchant_account_number(commune)
 WHERE merchant_account_number IS NULL;

UPDATE public.merchant_stores
   SET merchant_qr_payload = 'chopchop://merchant/' || merchant_account_number
 WHERE merchant_qr_payload IS NULL AND merchant_account_number IS NOT NULL;

-- 6. Prevent owner self-promotion of service-agent status (admins only via RPC)
CREATE OR REPLACE FUNCTION public.merchant_stores_guard_service_agent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Owner may set service_agent_requested=true and status to 'pending' (opt-in).
  -- Owner may NOT set status to approved/disabled/rejected.
  IF NEW.service_agent_status IS DISTINCT FROM OLD.service_agent_status THEN
    IF NEW.service_agent_status IN ('approved','disabled','rejected')
       AND NOT public.has_role(auth.uid(), 'admin') THEN
      RAISE EXCEPTION 'Only admins can change service_agent_status to %', NEW.service_agent_status;
    END IF;
  END IF;
  -- Owner may NOT change merchant_status to active/suspended/rejected.
  IF NEW.merchant_status IS DISTINCT FROM OLD.merchant_status THEN
    IF NEW.merchant_status IN ('active','suspended','rejected')
       AND NOT public.has_role(auth.uid(), 'admin') THEN
      RAISE EXCEPTION 'Only admins can change merchant_status to %', NEW.merchant_status;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_merchant_stores_guard_service_agent ON public.merchant_stores;
CREATE TRIGGER trg_merchant_stores_guard_service_agent
  BEFORE UPDATE ON public.merchant_stores
  FOR EACH ROW EXECUTE FUNCTION public.merchant_stores_guard_service_agent();

-- 7. Admin RPC — service agent decision
CREATE OR REPLACE FUNCTION public.admin_merchant_service_agent_decision(
  _store_id uuid,
  _decision text,
  _notes text DEFAULT NULL
)
RETURNS public.merchant_stores
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  row public.merchant_stores;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF _decision NOT IN ('approved','rejected','disabled','pending') THEN
    RAISE EXCEPTION 'invalid decision %', _decision;
  END IF;
  UPDATE public.merchant_stores
     SET service_agent_status = _decision,
         service_agent_notes  = COALESCE(_notes, service_agent_notes),
         service_agent_decided_at = now(),
         service_agent_decided_by = auth.uid(),
         updated_at = now()
   WHERE id = _store_id
  RETURNING * INTO row;
  RETURN row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_merchant_service_agent_decision(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_merchant_account_number(text) TO authenticated;
