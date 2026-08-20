-- =====================================================================
-- NODE 5 · A2 — CANONICAL PROFESSIONAL IDENTITY FOUNDATION
-- Surrogate PK + partial unique index => at most ONE active claim/user.
-- Released rows are preserved as history (professional_type immutable).
-- No lifecycle/approval truth is stored here.
-- =====================================================================

CREATE TABLE public.professional_identities (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  professional_type text NOT NULL,
  claim_state      text NOT NULL DEFAULT 'active',
  claimed_at       timestamptz NOT NULL DEFAULT now(),
  released_at      timestamptz,
  claim_source     text,
  release_reason   text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT professional_identities_type_ck
    CHECK (professional_type IN ('driver','merchant')),
  CONSTRAINT professional_identities_state_ck
    CHECK (claim_state IN ('active','released')),
  CONSTRAINT professional_identities_released_at_ck
    CHECK (
      (claim_state = 'active'   AND released_at IS NULL) OR
      (claim_state = 'released' AND released_at IS NOT NULL)
    ),
  CONSTRAINT professional_identities_released_after_claim_ck
    CHECK (released_at IS NULL OR released_at >= claimed_at)
);

-- THE exclusivity primitive. SECURITY DEFINER cannot bypass a unique index.
CREATE UNIQUE INDEX professional_identities_one_active_uidx
  ON public.professional_identities (user_id)
  WHERE claim_state = 'active';

CREATE INDEX professional_identities_user_idx
  ON public.professional_identities (user_id, claimed_at DESC);

-- Grants: read-own only for authenticated; all mutation is server-owned.
GRANT SELECT ON public.professional_identities TO authenticated;
GRANT ALL    ON public.professional_identities TO service_role;

ALTER TABLE public.professional_identities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "professional_identities_select_own"
  ON public.professional_identities
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Immutability / transition guard
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._professional_identity_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_USER_IMMUTABLE';
    END IF;
    IF NEW.professional_type <> OLD.professional_type THEN
      RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_TYPE_IMMUTABLE';
    END IF;
    IF NEW.claimed_at <> OLD.claimed_at THEN
      RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CLAIMED_AT_IMMUTABLE';
    END IF;
    IF OLD.claim_state = 'released' AND NEW.claim_state = 'active' THEN
      RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_RELEASE_IS_TERMINAL';
    END IF;
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER professional_identities_guard
  BEFORE UPDATE ON public.professional_identities
  FOR EACH ROW EXECUTE FUNCTION public._professional_identity_guard();

-- ---------------------------------------------------------------------
-- Internal claim primitive (A3 will compose the caller-facing surface)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._professional_identity_claim(
  p_user_id uuid,
  p_type    text,
  p_source  text DEFAULT NULL
)
RETURNS public.professional_identities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_row public.professional_identities;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_USER_REQUIRED';
  END IF;
  IF p_type IS NULL OR p_type NOT IN ('driver','merchant') THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_TYPE_INVALID';
  END IF;

  SELECT * INTO v_row
    FROM public.professional_identities
   WHERE user_id = p_user_id AND claim_state = 'active'
   FOR UPDATE;

  IF FOUND THEN
    IF v_row.professional_type = p_type THEN
      RETURN v_row; -- idempotent
    END IF;
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CONFLICT';
  END IF;

  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type, claim_source)
    VALUES (p_user_id, p_type, p_source)
    RETURNING * INTO v_row;
  EXCEPTION WHEN unique_violation THEN
    SELECT * INTO v_row FROM public.professional_identities
     WHERE user_id = p_user_id AND claim_state = 'active';
    IF FOUND AND v_row.professional_type = p_type THEN
      RETURN v_row;
    END IF;
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CONFLICT';
  END;

  RETURN v_row;
END $$;

-- Internal release primitive (A4 owns policy/UX; foundation only here)
CREATE OR REPLACE FUNCTION public._professional_identity_release(
  p_user_id uuid,
  p_reason  text DEFAULT NULL
)
RETURNS public.professional_identities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_row public.professional_identities;
BEGIN
  UPDATE public.professional_identities
     SET claim_state = 'released',
         released_at = now(),
         release_reason = p_reason
   WHERE user_id = p_user_id AND claim_state = 'active'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_NOT_ACTIVE';
  END IF;
  RETURN v_row;
END $$;

REVOKE ALL ON FUNCTION public._professional_identity_claim(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._professional_identity_release(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._professional_identity_claim(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public._professional_identity_release(uuid, text) TO service_role;

-- ---------------------------------------------------------------------
-- Canonical read surface: "what is MY current professional lane?"
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.professional_identity_current()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_row public.professional_identities;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_row FROM public.professional_identities
   WHERE user_id = v_uid AND claim_state = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('professional_type','none','claim_state',NULL,'identity_id',NULL,'claimed_at',NULL);
  END IF;

  RETURN jsonb_build_object(
    'professional_type', v_row.professional_type,
    'claim_state',       v_row.claim_state,
    'identity_id',       v_row.id,
    'claimed_at',        v_row.claimed_at
  );
END $$;

REVOKE ALL ON FUNCTION public.professional_identity_current() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.professional_identity_current() TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- BACKFILL — fail-closed conflict guard, then identity normalization only
-- ---------------------------------------------------------------------
DO $backfill$
DECLARE
  v_conflicts text;
  v_missing   text;
  v_drv int; v_mer int;
BEGIN
  CREATE TEMP TABLE _a2_driver_set ON COMMIT DROP AS
    SELECT user_id, min(c) AS claimed_at FROM (
      SELECT user_id, min(created_at) AS c FROM public.driver_profiles     GROUP BY 1
      UNION ALL
      SELECT user_id, min(created_at) AS c FROM public.driver_applications GROUP BY 1
    ) s WHERE user_id IS NOT NULL GROUP BY user_id;

  CREATE TEMP TABLE _a2_merchant_set ON COMMIT DROP AS
    SELECT user_id, min(c) AS claimed_at FROM (
      SELECT owner_user_id AS user_id, min(created_at) AS c FROM public.merchant_stores  WHERE owner_user_id IS NOT NULL GROUP BY 1
      UNION ALL
      SELECT owner_user_id, min(created_at) FROM public.food_restaurants WHERE owner_user_id IS NOT NULL GROUP BY 1
      UNION ALL
      SELECT owner_user_id, min(created_at) FROM public.merchants        WHERE owner_user_id IS NOT NULL GROUP BY 1
    ) s GROUP BY user_id;

  SELECT string_agg(user_id::text, ', ') INTO v_conflicts
    FROM (SELECT user_id FROM _a2_driver_set INTERSECT SELECT user_id FROM _a2_merchant_set) x;

  IF v_conflicts IS NOT NULL THEN
    RAISE EXCEPTION 'A2_BACKFILL_ABORTED_PROFESSIONAL_IDENTITY_CONFLICT: %', v_conflicts;
  END IF;

  SELECT string_agg(user_id::text, ', ') INTO v_missing FROM (
    SELECT user_id FROM _a2_driver_set UNION SELECT user_id FROM _a2_merchant_set
  ) s WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = s.user_id);

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'A2_BACKFILL_ABORTED_ORPHAN_ACCOUNT: %', v_missing;
  END IF;

  INSERT INTO public.professional_identities(user_id, professional_type, claim_state, claimed_at, claim_source)
  SELECT user_id, 'driver', 'active', COALESCE(claimed_at, now()), 'a2_backfill' FROM _a2_driver_set;
  GET DIAGNOSTICS v_drv = ROW_COUNT;

  INSERT INTO public.professional_identities(user_id, professional_type, claim_state, claimed_at, claim_source)
  SELECT user_id, 'merchant', 'active', COALESCE(claimed_at, now()), 'a2_backfill' FROM _a2_merchant_set;
  GET DIAGNOSTICS v_mer = ROW_COUNT;

  RAISE NOTICE 'A2 backfill: driver=% merchant=%', v_drv, v_mer;
END $backfill$;

COMMENT ON TABLE public.professional_identities IS
  'Node 5 A2: canonical professional lane ownership (driver|merchant). At most one active claim per user (partial unique index). Contains NO approval/suspension lifecycle truth: driver status stays in driver_profiles, merchant approval stays in store/restaurant truth.';
