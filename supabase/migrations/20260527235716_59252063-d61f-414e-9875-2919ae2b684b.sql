
-- =========================================================
-- 1. MISSIONS: drop broad UPDATE policies, replace with RPCs
-- =========================================================
DROP POLICY IF EXISTS "Courier updates own mission" ON public.missions;
DROP POLICY IF EXISTS "Customer updates own mission" ON public.missions;
DROP POLICY IF EXISTS "Merchant updates own mission" ON public.missions;
DROP POLICY IF EXISTS "Eligible couriers claim missions" ON public.missions;

-- Claim an unassigned mission (courier-only, capability-checked).
CREATE OR REPLACE FUNCTION public.mission_claim(_mission_id uuid)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _m   public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS NOT NULL THEN RAISE EXCEPTION 'mission_already_claimed'; END IF;
  IF NOT public.driver_has_capability(_uid, public.mission_required_capability(_m.type)) THEN
    RAISE EXCEPTION 'capability_missing';
  END IF;
  UPDATE public.missions
     SET courier_id = _uid,
         state = 'heading_to_pickup'
   WHERE id = _mission_id
   RETURNING * INTO _m;
  RETURN _m;
END;
$$;
REVOKE ALL ON FUNCTION public.mission_claim(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mission_claim(uuid) TO authenticated;

-- Advance/set mission state with strict transition + actor checks.
CREATE OR REPLACE FUNCTION public.mission_set_state(_mission_id uuid, _state mission_state)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid uuid := auth.uid();
  _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  -- Only assigned courier (or admin) can move state forward.
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  -- Allowed states for courier flow.
  IF _state NOT IN ('heading_to_pickup','arrived_pickup','picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
    RAISE EXCEPTION 'state_not_allowed';
  END IF;
  UPDATE public.missions SET state = _state WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END;
$$;
REVOKE ALL ON FUNCTION public.mission_set_state(uuid, mission_state) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mission_set_state(uuid, mission_state) TO authenticated;

CREATE OR REPLACE FUNCTION public.mission_confirm_pickup(_mission_id uuid)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  UPDATE public.missions
     SET state='picked_up', pickup_confirmed_at=now(), pickup_confirmed_by=_uid
   WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END;
$$;
REVOKE ALL ON FUNCTION public.mission_confirm_pickup(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mission_confirm_pickup(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff(_mission_id uuid)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  UPDATE public.missions
     SET state='delivered', dropoff_confirmed_at=now(), dropoff_confirmed_by=_uid
   WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END;
$$;
REVOKE ALL ON FUNCTION public.mission_confirm_dropoff(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mission_confirm_dropoff(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.mission_report_issue(_mission_id uuid, _reason text, _district text DEFAULT NULL, _hub_id uuid DEFAULT NULL)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid
     AND _m.customer_id IS DISTINCT FROM _uid
     AND _m.merchant_id IS DISTINCT FROM _uid
     AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  UPDATE public.missions
     SET state='failed',
         issue_reason=_reason,
         issue_district = COALESCE(_district, issue_district),
         issue_hub_id   = COALESCE(_hub_id, issue_hub_id)
   WHERE id=_mission_id
   RETURNING * INTO _m;
  RETURN _m;
END;
$$;
REVOKE ALL ON FUNCTION public.mission_report_issue(uuid, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mission_report_issue(uuid, text, text, uuid) TO authenticated;

-- =========================================================
-- 2. MESSAGE_LOG: revoke broad user read
-- =========================================================
DROP POLICY IF EXISTS "Users read own messages" ON public.message_log;

-- =========================================================
-- 3. DRIVER_APPLICATIONS: drop direct user read, expose sanitized RPC
-- =========================================================
DROP POLICY IF EXISTS "Users read own applications" ON public.driver_applications;

CREATE OR REPLACE FUNCTION public.get_my_driver_application_status()
RETURNS TABLE(
  id uuid,
  decision driver_application_decision,
  decision_reason text,
  decided_at timestamptz,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, decision,
         CASE WHEN decision='rejected' THEN decision_reason ELSE NULL END,
         decided_at, created_at
    FROM public.driver_applications
   WHERE user_id = auth.uid()
   ORDER BY created_at DESC
   LIMIT 5;
$$;
REVOKE ALL ON FUNCTION public.get_my_driver_application_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_driver_application_status() TO authenticated;

-- =========================================================
-- 4. USER_ROLES: break the admin-writes-roles cycle
-- =========================================================
DROP POLICY IF EXISTS "Admins can manage roles" ON public.user_roles;

CREATE POLICY "Super admins manage roles" ON public.user_roles
  FOR ALL TO authenticated
  USING (public.has_admin_role(auth.uid(), 'super_admin'::admin_role))
  WITH CHECK (public.has_admin_role(auth.uid(), 'super_admin'::admin_role));

-- =========================================================
-- 5. is_admin: only trust admin_users
-- =========================================================
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
     WHERE user_id = _user_id AND status = 'active'
  );
$$;

-- =========================================================
-- 6. REALTIME: drop financial tables from publication
-- =========================================================
ALTER PUBLICATION supabase_realtime DROP TABLE public.wallets;
ALTER PUBLICATION supabase_realtime DROP TABLE public.wallet_transactions;
ALTER PUBLICATION supabase_realtime DROP TABLE public.topup_requests;
