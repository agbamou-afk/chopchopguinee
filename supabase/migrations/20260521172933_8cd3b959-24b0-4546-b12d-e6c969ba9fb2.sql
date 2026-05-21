
-- =====================================================================
-- WONGO Payments Foundation — internal ledger + payment-rail readiness
-- Purely additive: new enums, tables, functions, RLS. No data backfill.
-- =====================================================================

-- ----- Enums --------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.payment_state AS ENUM (
    'pending','processing','confirmed','failed','cancelled','refunded','reversed','expired'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.payment_provider AS ENUM (
    'orange_money','mtn_money','cash','manual','internal','agent'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.payment_purpose AS ENUM (
    'wallet_topup','repas_payment','marche_payment','courier_payout','merchant_settlement','refund'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.payment_recon_event AS ENUM (
    'intent_created','provider_pending','provider_confirmed','provider_failed',
    'wallet_credited','payout_queued','payout_paid','refund_created','refund_completed'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ----- Reference sequence + helper ---------------------------------
CREATE SEQUENCE IF NOT EXISTS public.payment_intent_ref_seq
  AS bigint START 1 INCREMENT 1 NO CYCLE;

CREATE OR REPLACE FUNCTION public.next_wongo_reference()
RETURNS text
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  yr int := EXTRACT(YEAR FROM now() AT TIME ZONE 'UTC')::int;
  n  bigint := nextval('public.payment_intent_ref_seq');
BEGIN
  RETURN format('WNG-%s-%s', yr::text, lpad(n::text, 6, '0'));
END $$;

-- ----- payment_intents ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_intents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL,
  amount_gnf          bigint NOT NULL CHECK (amount_gnf > 0),
  currency            text   NOT NULL DEFAULT 'GNF',
  purpose             public.payment_purpose  NOT NULL,
  state               public.payment_state    NOT NULL DEFAULT 'pending',
  provider            public.payment_provider NOT NULL DEFAULT 'internal',
  provider_reference  text,
  internal_reference  text NOT NULL UNIQUE,
  related_order_id    uuid,
  related_mission_id  uuid,
  related_listing_id  uuid,
  related_store_id    uuid,
  metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_intents_user    ON public.payment_intents (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_intents_state   ON public.payment_intents (state, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_intents_purpose ON public.payment_intents (purpose, created_at DESC);

ALTER TABLE public.payment_intents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own payment intents" ON public.payment_intents;
CREATE POLICY "Users read own payment intents"
  ON public.payment_intents FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins read all payment intents" ON public.payment_intents;
CREATE POLICY "Admins read all payment intents"
  ON public.payment_intents FOR SELECT
  TO authenticated
  USING (is_any_admin(auth.uid()));

DROP POLICY IF EXISTS "Finance/super admins manage intents" ON public.payment_intents;
CREATE POLICY "Finance/super admins manage intents"
  ON public.payment_intents FOR ALL
  TO authenticated
  USING (
    has_admin_role(auth.uid(), 'super_admin'::admin_role)
    OR has_admin_role(auth.uid(), 'finance_admin'::admin_role)
  )
  WITH CHECK (
    has_admin_role(auth.uid(), 'super_admin'::admin_role)
    OR has_admin_role(auth.uid(), 'finance_admin'::admin_role)
  );

-- Auto-fill internal_reference + updated_at
CREATE OR REPLACE FUNCTION public.payment_intents_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.internal_reference IS NULL OR NEW.internal_reference = '' THEN
    NEW.internal_reference := public.next_wongo_reference();
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_payment_intents_before_insert ON public.payment_intents;
CREATE TRIGGER trg_payment_intents_before_insert
  BEFORE INSERT ON public.payment_intents
  FOR EACH ROW EXECUTE FUNCTION public.payment_intents_before_insert();

DROP TRIGGER IF EXISTS trg_payment_intents_updated_at ON public.payment_intents;
CREATE TRIGGER trg_payment_intents_updated_at
  BEFORE UPDATE ON public.payment_intents
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ----- payment_reconciliation_events -------------------------------
CREATE TABLE IF NOT EXISTS public.payment_reconciliation_events (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intent_id           uuid NOT NULL REFERENCES public.payment_intents(id) ON DELETE CASCADE,
  event_type          public.payment_recon_event NOT NULL,
  provider            public.payment_provider,
  provider_reference  text,
  payload             jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_user_id       uuid,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recon_intent ON public.payment_reconciliation_events (intent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recon_type   ON public.payment_reconciliation_events (event_type, created_at DESC);

ALTER TABLE public.payment_reconciliation_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read recon events" ON public.payment_reconciliation_events;
CREATE POLICY "Admins read recon events"
  ON public.payment_reconciliation_events FOR SELECT
  TO authenticated
  USING (is_any_admin(auth.uid()));

-- No INSERT/UPDATE/DELETE policies → only SECURITY DEFINER helpers can write.

-- Auto-emit intent_created on insert
CREATE OR REPLACE FUNCTION public.payment_intents_after_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
  VALUES (NEW.id, 'intent_created', NEW.provider, NEW.provider_reference,
          jsonb_build_object('purpose', NEW.purpose, 'amount_gnf', NEW.amount_gnf, 'internal_reference', NEW.internal_reference),
          auth.uid());
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_payment_intents_after_insert ON public.payment_intents;
CREATE TRIGGER trg_payment_intents_after_insert
  AFTER INSERT ON public.payment_intents
  FOR EACH ROW EXECUTE FUNCTION public.payment_intents_after_insert();

-- ----- State-transition helpers (admin only) -----------------------
CREATE OR REPLACE FUNCTION public.confirm_payment_intent(
  p_intent_id uuid,
  p_provider_reference text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_intents;
BEGIN
  IF NOT (has_admin_role(auth.uid(), 'super_admin'::admin_role)
          OR has_admin_role(auth.uid(), 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden: admin required';
  END IF;

  UPDATE public.payment_intents
     SET state = 'confirmed',
         provider_reference = COALESCE(p_provider_reference, provider_reference),
         metadata = metadata || jsonb_build_object('confirmed_at', now(), 'note', p_note)
   WHERE id = p_intent_id
     AND state IN ('pending','processing')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'intent not found or not in pending/processing state';
  END IF;

  INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
  VALUES (v_row.id, 'provider_confirmed', v_row.provider, v_row.provider_reference,
          jsonb_build_object('note', p_note), auth.uid());

  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.fail_payment_intent(
  p_intent_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_intents;
BEGIN
  IF NOT (has_admin_role(auth.uid(), 'super_admin'::admin_role)
          OR has_admin_role(auth.uid(), 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden: admin required';
  END IF;

  UPDATE public.payment_intents
     SET state = 'failed',
         metadata = metadata || jsonb_build_object('failed_at', now(), 'reason', p_reason)
   WHERE id = p_intent_id
     AND state IN ('pending','processing')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'intent not found or not in pending/processing state';
  END IF;

  INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
  VALUES (v_row.id, 'provider_failed', v_row.provider, v_row.provider_reference,
          jsonb_build_object('reason', p_reason), auth.uid());

  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.cancel_payment_intent(
  p_intent_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS public.payment_intents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.payment_intents;
BEGIN
  IF NOT (has_admin_role(auth.uid(), 'super_admin'::admin_role)
          OR has_admin_role(auth.uid(), 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden: admin required';
  END IF;

  UPDATE public.payment_intents
     SET state = 'cancelled',
         metadata = metadata || jsonb_build_object('cancelled_at', now(), 'reason', p_reason)
   WHERE id = p_intent_id
     AND state IN ('pending','processing')
   RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'intent not found or not in pending/processing state';
  END IF;

  INSERT INTO public.payment_reconciliation_events (intent_id, event_type, provider, provider_reference, payload, actor_user_id)
  VALUES (v_row.id, 'provider_failed', v_row.provider, v_row.provider_reference,
          jsonb_build_object('reason', p_reason, 'cancelled', true), auth.uid());

  RETURN v_row;
END $$;

-- ----- Widen topup_requests.provider CHECK for future providers ----
ALTER TABLE public.topup_requests DROP CONSTRAINT IF EXISTS topup_requests_provider_chk;
ALTER TABLE public.topup_requests
  ADD CONSTRAINT topup_requests_provider_chk
  CHECK (provider IN ('agent','orange_money','mtn_money','cash','manual','internal'));
