
-- ===== NODE 4 MARCHE R7: SHOPPER-DRIVER FULFILLMENT (schema) =====

CREATE TABLE public.marche_procurement_missions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL UNIQUE REFERENCES public.marche_procurement_requests(id) ON DELETE CASCADE,
  buyer_user_id uuid NOT NULL,
  shopper_user_id uuid,
  state text NOT NULL DEFAULT 'unassigned',
  market_id uuid REFERENCES public.physical_markets(id),
  destination_address text,
  dropoff_lat numeric,
  dropoff_lng numeric,
  mission_id uuid REFERENCES public.missions(id),
  verified_spend_gnf bigint,
  assigned_at timestamptz,
  arrived_market_at timestamptz,
  shopping_started_at timestamptz,
  purchase_submitted_at timestamptz,
  purchase_verified_at timestamptz,
  delivery_started_at timestamptz,
  delivered_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_pm_state_chk CHECK (state IN (
    'unassigned','assigned','at_market','shopping','purchase_verified',
    'delivering','delivered','completed','cancelled')),
  CONSTRAINT marche_pm_spend_chk CHECK (verified_spend_gnf IS NULL OR verified_spend_gnf >= 0)
);
CREATE INDEX idx_marche_pm_shopper ON public.marche_procurement_missions(shopper_user_id, state);
CREATE INDEX idx_marche_pm_state ON public.marche_procurement_missions(state);

CREATE TABLE public.marche_procurement_line_resolutions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.marche_procurement_requests(id) ON DELETE CASCADE,
  line_no int NOT NULL,
  state text NOT NULL DEFAULT 'pending',
  requested_qty numeric NOT NULL,
  actual_qty numeric,
  canonical_base_unit text,
  actual_normalized_quantity numeric,
  actual_unit_price_gnf bigint,
  actual_line_total_gnf bigint,
  substitute_label_fr text,
  note_fr text,
  resolved_by uuid,
  resolved_at timestamptz,
  proposal_version int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, line_no),
  CONSTRAINT marche_plr_state_chk CHECK (state IN (
    'pending','acquired','unavailable','substitution_proposed','quantity_proposed')),
  CONSTRAINT marche_plr_price_chk CHECK (actual_unit_price_gnf IS NULL OR actual_unit_price_gnf > 0),
  CONSTRAINT marche_plr_total_chk CHECK (actual_line_total_gnf IS NULL OR actual_line_total_gnf >= 0)
);

CREATE TABLE public.marche_procurement_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.marche_procurement_requests(id) ON DELETE CASCADE,
  line_no int NOT NULL,
  version int NOT NULL,
  kind text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending',
  proposed_by uuid NOT NULL,
  proposed_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid,
  decided_at timestamptz,
  UNIQUE (request_id, line_no, version),
  CONSTRAINT marche_pp_kind_chk CHECK (kind IN ('substitution','quantity_adjust')),
  CONSTRAINT marche_pp_status_chk CHECK (status IN ('pending','approved','rejected','superseded'))
);
CREATE INDEX idx_marche_pp_pending ON public.marche_procurement_proposals(request_id, status);

CREATE TABLE public.marche_procurement_mission_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.marche_procurement_requests(id) ON DELETE CASCADE,
  event text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_user_id uuid,
  actor_role text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_marche_pme_request ON public.marche_procurement_mission_events(request_id, created_at);

CREATE TABLE public.marche_procurement_purchase_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.marche_procurement_requests(id) ON DELETE CASCADE,
  line_no int,
  bucket_id text NOT NULL DEFAULT 'marche-procurement-evidence',
  storage_path text NOT NULL,
  uploaded_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, storage_path)
);

-- ===== append-only / immutability guards =====
CREATE OR REPLACE FUNCTION public._marche_pm_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF COALESCE(current_setting('marche.procurement_purge', true),'') = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'PROCUREMENT_MISSION_APPEND_ONLY';
END $$;

CREATE TRIGGER trg_marche_pme_append_only
  BEFORE UPDATE OR DELETE ON public.marche_procurement_mission_events
  FOR EACH ROW EXECUTE FUNCTION public._marche_pm_append_only();

CREATE OR REPLACE FUNCTION public._marche_pp_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.procurement_purge', true),'') = 'on' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'PROCUREMENT_MISSION_APPEND_ONLY';
  END IF;
  IF NEW.request_id <> OLD.request_id OR NEW.line_no <> OLD.line_no
     OR NEW.version <> OLD.version OR NEW.kind <> OLD.kind
     OR NEW.payload IS DISTINCT FROM OLD.payload
     OR NEW.proposed_by <> OLD.proposed_by OR NEW.proposed_at <> OLD.proposed_at THEN
    RAISE EXCEPTION 'PROCUREMENT_PROPOSAL_IMMUTABLE';
  END IF;
  IF OLD.status IN ('approved','rejected') AND NEW.status <> OLD.status THEN
    RAISE EXCEPTION 'PROCUREMENT_PROPOSAL_TERMINAL';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_marche_pp_guard
  BEFORE UPDATE OR DELETE ON public.marche_procurement_proposals
  FOR EACH ROW EXECUTE FUNCTION public._marche_pp_guard();

CREATE OR REPLACE FUNCTION public._marche_pm_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

CREATE TRIGGER trg_marche_pm_touch BEFORE UPDATE ON public.marche_procurement_missions
  FOR EACH ROW EXECUTE FUNCTION public._marche_pm_touch();
CREATE TRIGGER trg_marche_plr_touch BEFORE UPDATE ON public.marche_procurement_line_resolutions
  FOR EACH ROW EXECUTE FUNCTION public._marche_pm_touch();

-- ===== grants: RPC-only surface (no direct anon/authenticated table access) =====
ALTER TABLE public.marche_procurement_missions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marche_procurement_line_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marche_procurement_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marche_procurement_mission_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marche_procurement_purchase_evidence ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.marche_procurement_missions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.marche_procurement_line_resolutions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.marche_procurement_proposals FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.marche_procurement_mission_events FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.marche_procurement_purchase_evidence FROM PUBLIC, anon, authenticated;

GRANT ALL ON public.marche_procurement_missions TO service_role;
GRANT ALL ON public.marche_procurement_line_resolutions TO service_role;
GRANT ALL ON public.marche_procurement_proposals TO service_role;
GRANT ALL ON public.marche_procurement_mission_events TO service_role;
GRANT ALL ON public.marche_procurement_purchase_evidence TO service_role;

-- ===== private evidence storage policies =====
CREATE POLICY "marche procurement evidence: shopper writes own mission"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'marche-procurement-evidence'
  AND EXISTS (
    SELECT 1 FROM public.marche_procurement_missions m
    WHERE m.shopper_user_id = auth.uid()
      AND m.state IN ('at_market','shopping')
      AND name LIKE m.request_id::text || '/%'
  )
);

CREATE POLICY "marche procurement evidence: private authenticated reads"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'marche-procurement-evidence'
  AND (
    public._finance_privileged(auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.marche_procurement_missions m
      WHERE name LIKE m.request_id::text || '/%'
        AND (m.shopper_user_id = auth.uid() OR m.buyer_user_id = auth.uid())
    )
  )
);
