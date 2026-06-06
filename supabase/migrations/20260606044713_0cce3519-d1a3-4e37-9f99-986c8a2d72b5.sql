
-- merchant_stores: relax status check, add onboarding columns
ALTER TABLE public.merchant_stores DROP CONSTRAINT IF EXISTS merchant_stores_status_check;
ALTER TABLE public.merchant_stores
  ADD COLUMN IF NOT EXISTS business_name text,
  ADD COLUMN IF NOT EXISTS owner_name text,
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS business_type text,
  ADD COLUMN IF NOT EXISTS stall_number text,
  ADD COLUMN IF NOT EXISTS operating_hours text,
  ADD COLUMN IF NOT EXISTS whatsapp text,
  ADD COLUMN IF NOT EXISTS market_id uuid,
  ADD COLUMN IF NOT EXISTS onboarding_status text NOT NULL DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS created_by uuid,
  ADD COLUMN IF NOT EXISTS submitted_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by uuid,
  ADD COLUMN IF NOT EXISTS rejection_reason text;

ALTER TABLE public.merchant_stores
  ADD CONSTRAINT merchant_stores_status_check
  CHECK (status IN ('draft','pending','active','paused','suspended','rejected','archived'));
ALTER TABLE public.merchant_stores
  ADD CONSTRAINT merchant_stores_onboarding_status_check
  CHECK (onboarding_status IN ('draft','submitted','in_review','needs_info','approved','rejected'));

UPDATE public.merchant_stores
   SET approved_at = COALESCE(approved_at, member_since, now())
 WHERE onboarding_status = 'approved';

-- marketplace_listings: inventory + visibility
ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS quantity_in_stock integer,
  ADD COLUMN IF NOT EXISTS barcode text,
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'public';
ALTER TABLE public.marketplace_listings DROP CONSTRAINT IF EXISTS marketplace_listings_visibility_check;
ALTER TABLE public.marketplace_listings
  ADD CONSTRAINT marketplace_listings_visibility_check
  CHECK (visibility IN ('private','public'));

-- physical_markets
CREATE TABLE IF NOT EXISTS public.physical_markets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  commune text,
  district text,
  address text,
  landmark text,
  latitude double precision,
  longitude double precision,
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','active','archived')),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.physical_markets TO authenticated, anon;
GRANT INSERT, UPDATE, DELETE ON public.physical_markets TO authenticated;
GRANT ALL ON public.physical_markets TO service_role;
ALTER TABLE public.physical_markets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "physical_markets_public_read" ON public.physical_markets
  FOR SELECT TO anon, authenticated
  USING (status = 'active' OR public.has_role(auth.uid(),'admin') OR public.has_role(auth.uid(),'onboarding_specialist'));
CREATE POLICY "physical_markets_admin_write" ON public.physical_markets
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

-- market_onboarding_campaigns
CREATE TABLE IF NOT EXISTS public.market_onboarding_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  market_id uuid NOT NULL REFERENCES public.physical_markets(id) ON DELETE CASCADE,
  name text NOT NULL,
  start_date date,
  end_date date,
  target_merchants integer,
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','active','completed','cancelled')),
  team_lead uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.market_onboarding_campaigns TO authenticated;
GRANT ALL ON public.market_onboarding_campaigns TO service_role;
ALTER TABLE public.market_onboarding_campaigns ENABLE ROW LEVEL SECURITY;
CREATE POLICY "campaigns_admin_full" ON public.market_onboarding_campaigns
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));
CREATE POLICY "campaigns_specialist_read" ON public.market_onboarding_campaigns
  FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'onboarding_specialist'));

-- market_onboarding_assignments
CREATE TABLE IF NOT EXISTS public.market_onboarding_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.market_onboarding_campaigns(id) ON DELETE CASCADE,
  specialist_user_id uuid NOT NULL,
  assigned_zone text,
  merchants_targeted integer NOT NULL DEFAULT 0,
  merchants_completed integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.market_onboarding_assignments TO authenticated;
GRANT ALL ON public.market_onboarding_assignments TO service_role;
ALTER TABLE public.market_onboarding_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "assignments_admin_full" ON public.market_onboarding_assignments
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));
CREATE POLICY "assignments_specialist_own_read" ON public.market_onboarding_assignments
  FOR SELECT TO authenticated
  USING (specialist_user_id = auth.uid());

-- Tighten merchant_stores public-read
DROP POLICY IF EXISTS "Anyone read active stores" ON public.merchant_stores;
CREATE POLICY "Public read approved stores" ON public.merchant_stores
  FOR SELECT TO anon, authenticated
  USING (
    (status = 'active' AND onboarding_status = 'approved')
    OR owner_user_id = auth.uid()
    OR public.has_role(auth.uid(),'admin')
    OR public.has_role(auth.uid(),'onboarding_specialist')
  );

DROP POLICY IF EXISTS "Specialist creates stores" ON public.merchant_stores;
CREATE POLICY "Specialist creates stores" ON public.merchant_stores
  FOR INSERT TO authenticated
  WITH CHECK (public.has_role(auth.uid(),'onboarding_specialist'));
DROP POLICY IF EXISTS "Specialist updates pending stores" ON public.merchant_stores;
CREATE POLICY "Specialist updates pending stores" ON public.merchant_stores
  FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'onboarding_specialist') AND onboarding_status IN ('draft','submitted','in_review','needs_info'))
  WITH CHECK (public.has_role(auth.uid(),'onboarding_specialist'));

-- Tighten marketplace_listings public-read
DROP POLICY IF EXISTS "Anyone can view active listings" ON public.marketplace_listings;
CREATE POLICY "Public read approved listings" ON public.marketplace_listings
  FOR SELECT TO anon, authenticated
  USING (
    (
      status = 'active'
      AND visibility = 'public'
      AND (
        store_id IS NULL
        OR EXISTS (
          SELECT 1 FROM public.merchant_stores s
          WHERE s.id = marketplace_listings.store_id
            AND s.status = 'active'
            AND s.onboarding_status = 'approved'
        )
      )
    )
    OR seller_id = auth.uid()
    OR public.has_role(auth.uid(),'admin')
  );

-- admin_merchant_decision RPC
CREATE OR REPLACE FUNCTION public.admin_merchant_decision(
  _store_id uuid,
  _decision text,
  _reason text DEFAULT NULL
) RETURNS public.merchant_stores
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _admin uuid := auth.uid();
  _row public.merchant_stores;
BEGIN
  IF _admin IS NULL OR NOT public.has_role(_admin, 'admin') THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  IF _decision NOT IN ('approve','reject','request_info','suspend','reactivate') THEN
    RAISE EXCEPTION 'invalid_decision';
  END IF;

  SELECT * INTO _row FROM public.merchant_stores WHERE id = _store_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'store_not_found'; END IF;
  IF _row.owner_user_id = _admin THEN
    RAISE EXCEPTION 'self_approval_forbidden';
  END IF;

  IF _decision = 'approve' THEN
    UPDATE public.merchant_stores
       SET status='active', onboarding_status='approved',
           approved_at=now(), approved_by=_admin,
           rejection_reason=NULL, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'reject' THEN
    UPDATE public.merchant_stores
       SET status='rejected', onboarding_status='rejected',
           rejection_reason=_reason, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'request_info' THEN
    UPDATE public.merchant_stores
       SET onboarding_status='needs_info',
           rejection_reason=_reason, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'suspend' THEN
    UPDATE public.merchant_stores
       SET status='suspended',
           rejection_reason=_reason, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'reactivate' THEN
    UPDATE public.merchant_stores
       SET status='active', updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  END IF;

  BEGIN
    PERFORM public.log_admin_action(
      'merchants','merchant_decision','merchant_store', _store_id::text,
      NULL, jsonb_build_object('decision',_decision,'reason',_reason), _reason
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN _row;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_merchant_decision(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_merchant_decision(uuid, text, text) TO authenticated;
