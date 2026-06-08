
-- =====================================================================
-- Driver Groups / Syndicates v1: payouts, leader portal, analytics, zones
-- =====================================================================

-- --- 1) Controlled zone columns (forwards-compatible) ----------------
ALTER TABLE public.driver_groups
  ADD COLUMN IF NOT EXISTS assigned_zone_ids uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE public.driver_group_memberships
  ADD COLUMN IF NOT EXISTS assigned_zone_id uuid REFERENCES public.zones(id) ON DELETE SET NULL;

-- Sync trigger: when assigned_zone_ids changes, mirror their display names into the legacy text[] column.
CREATE OR REPLACE FUNCTION public._driver_groups_sync_zone_names()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.assigned_zone_ids IS DISTINCT FROM COALESCE(OLD.assigned_zone_ids, '{}'::uuid[]) THEN
    SELECT COALESCE(array_agg(COALESCE(z.neighborhood, z.commune, z.city, z.kind) ORDER BY z.created_at), '{}')
      INTO NEW.assigned_zones
      FROM public.zones z
     WHERE z.id = ANY(NEW.assigned_zone_ids);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_driver_groups_sync_zones ON public.driver_groups;
CREATE TRIGGER trg_driver_groups_sync_zones
  BEFORE INSERT OR UPDATE OF assigned_zone_ids ON public.driver_groups
  FOR EACH ROW EXECUTE FUNCTION public._driver_groups_sync_zone_names();

CREATE OR REPLACE FUNCTION public._dgm_sync_zone_name()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.assigned_zone_id IS DISTINCT FROM OLD.assigned_zone_id THEN
    SELECT COALESCE(z.neighborhood, z.commune, z.city, z.kind)
      INTO NEW.assigned_zone
      FROM public.zones z WHERE z.id = NEW.assigned_zone_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_dgm_sync_zone ON public.driver_group_memberships;
CREATE TRIGGER trg_dgm_sync_zone
  BEFORE INSERT OR UPDATE OF assigned_zone_id ON public.driver_group_memberships
  FOR EACH ROW EXECUTE FUNCTION public._dgm_sync_zone_name();


-- --- 2) wallet_pay_driver_commission ---------------------------------
CREATE OR REPLACE FUNCTION public.wallet_pay_driver_commission(p_commission_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_c public.driver_group_commissions;
  v_leader_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
  v_ref text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT (public.has_app_role(v_caller, 'god_admin') OR public.has_app_role(v_caller, 'finance_admin')) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_c FROM public.driver_group_commissions
    WHERE id = p_commission_id FOR UPDATE;
  IF v_c.id IS NULL THEN RAISE EXCEPTION 'commission_not_found'; END IF;
  IF v_c.status <> 'approved' THEN RAISE EXCEPTION 'commission_not_approved'; END IF;
  IF v_c.wallet_transaction_id IS NOT NULL THEN RAISE EXCEPTION 'commission_already_paid'; END IF;
  IF v_c.leader_user_id IS NULL THEN RAISE EXCEPTION 'commission_missing_leader'; END IF;
  IF v_c.commission_amount_gnf <= 0 THEN RAISE EXCEPTION 'commission_amount_zero'; END IF;

  v_ref := 'CC-COMM-' || replace(v_c.id::text, '-', '');
  IF EXISTS (SELECT 1 FROM public.wallet_transactions WHERE reference = v_ref) THEN
    RAISE EXCEPTION 'commission_already_credited';
  END IF;

  -- Ensure leader has a driver wallet (leaders are drivers in this model)
  SELECT * INTO v_leader_wallet FROM public.wallets
    WHERE owner_user_id = v_c.leader_user_id AND party_type IN ('driver','client')
    ORDER BY (party_type = 'driver') DESC
    FOR UPDATE LIMIT 1;
  IF v_leader_wallet.id IS NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type)
      VALUES (v_c.leader_user_id, 'driver')
      RETURNING * INTO v_leader_wallet;
  END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN RAISE EXCEPTION 'master_wallet_missing'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf + v_c.commission_amount_gnf WHERE id = v_leader_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf - v_c.commission_amount_gnf WHERE id = v_master.id;

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'commission', 'completed', v_c.commission_amount_gnf,
    v_master.id, v_leader_wallet.id, v_c.leader_user_id, 'driver_group_commission',
    'Commission groupe chauffeurs', now(),
    jsonb_build_object(
      'commission_id', v_c.id,
      'group_id', v_c.group_id,
      'driver_user_id', v_c.driver_user_id,
      'source_type', v_c.source_type,
      'source_id', v_c.source_id,
      'admin_user_id', v_caller
    )
  ) RETURNING * INTO v_tx;

  UPDATE public.driver_group_commissions
     SET status = 'paid', wallet_transaction_id = v_tx.id, paid_at = now()
   WHERE id = v_c.id;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (v_caller, public.current_admin_role(v_caller),
          'driver_groups', 'commission.pay', 'driver_group_commission', v_c.id::text,
          jsonb_build_object('amount_gnf', v_c.commission_amount_gnf, 'leader_user_id', v_c.leader_user_id, 'wallet_tx_id', v_tx.id),
          'Commission payée via ChopWallet');

  RETURN v_tx.id;
END $$;
REVOKE EXECUTE ON FUNCTION public.wallet_pay_driver_commission(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.wallet_pay_driver_commission(uuid) TO authenticated;


-- --- 3) wallet_reverse_driver_commission -----------------------------
CREATE OR REPLACE FUNCTION public.wallet_reverse_driver_commission(p_commission_id uuid, p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_c public.driver_group_commissions;
  v_orig public.wallet_transactions;
  v_leader_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
  v_ref text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF NOT (public.has_app_role(v_caller, 'god_admin') OR public.has_app_role(v_caller, 'finance_admin')) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF coalesce(trim(p_reason),'') = '' THEN RAISE EXCEPTION 'reason_required'; END IF;

  SELECT * INTO v_c FROM public.driver_group_commissions WHERE id = p_commission_id FOR UPDATE;
  IF v_c.id IS NULL THEN RAISE EXCEPTION 'commission_not_found'; END IF;
  IF v_c.status <> 'paid' OR v_c.wallet_transaction_id IS NULL THEN
    RAISE EXCEPTION 'commission_not_paid';
  END IF;

  SELECT * INTO v_orig FROM public.wallet_transactions WHERE id = v_c.wallet_transaction_id;
  IF v_orig.id IS NULL THEN RAISE EXCEPTION 'wallet_tx_missing'; END IF;

  v_ref := 'CC-COMM-REV-' || replace(v_c.id::text, '-', '');
  IF EXISTS (SELECT 1 FROM public.wallet_transactions WHERE reference = v_ref) THEN
    RAISE EXCEPTION 'commission_already_reversed';
  END IF;

  SELECT * INTO v_leader_wallet FROM public.wallets WHERE id = v_orig.to_wallet_id FOR UPDATE;
  SELECT * INTO v_master       FROM public.wallets WHERE id = v_orig.from_wallet_id FOR UPDATE;
  IF v_leader_wallet.id IS NULL OR v_master.id IS NULL THEN RAISE EXCEPTION 'wallet_missing'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - v_orig.amount_gnf WHERE id = v_leader_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_orig.amount_gnf WHERE id = v_master.id;

  INSERT INTO public.wallet_transactions (
    reference, type, status, amount_gnf,
    from_wallet_id, to_wallet_id, related_user_id, related_entity,
    description, completed_at, metadata
  ) VALUES (
    v_ref, 'commission', 'reversed', v_orig.amount_gnf,
    v_leader_wallet.id, v_master.id, v_c.leader_user_id, 'driver_group_commission_reversal',
    p_reason, now(),
    jsonb_build_object('commission_id', v_c.id, 'original_tx_id', v_orig.id, 'admin_user_id', v_caller)
  ) RETURNING * INTO v_tx;

  UPDATE public.driver_group_commissions
     SET status = 'reversed', notes = COALESCE(notes || E'\n','') || 'Reversal: ' || p_reason
   WHERE id = v_c.id;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (v_caller, public.current_admin_role(v_caller),
          'driver_groups', 'commission.reverse', 'driver_group_commission', v_c.id::text,
          jsonb_build_object('amount_gnf', v_orig.amount_gnf, 'wallet_tx_id', v_tx.id),
          p_reason);

  RETURN v_tx.id;
END $$;
REVOKE EXECUTE ON FUNCTION public.wallet_reverse_driver_commission(uuid, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.wallet_reverse_driver_commission(uuid, text) TO authenticated;


-- --- 4) Leader self-service RPCs -------------------------------------
CREATE OR REPLACE FUNCTION public._leader_group_id(_uid uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM public.driver_groups WHERE leader_user_id = _uid LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.leader_get_my_group()
RETURNS public.driver_groups LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_row public.driver_groups;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_row FROM public.driver_groups WHERE leader_user_id = v_uid LIMIT 1;
  RETURN v_row;
END $$;
REVOKE EXECUTE ON FUNCTION public.leader_get_my_group() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.leader_get_my_group() TO authenticated;

CREATE OR REPLACE FUNCTION public.leader_list_my_members()
RETURNS TABLE (
  id uuid, driver_user_id uuid, status text,
  assigned_zone text, joined_at timestamptz,
  driver_display text, driver_phone_last4 text
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_group uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  v_group := public._leader_group_id(v_uid);
  IF v_group IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT m.id, m.driver_user_id, m.status, m.assigned_zone, m.joined_at,
           COALESCE(p.full_name, 'Chauffeur ' || substring(m.driver_user_id::text,1,8)) AS driver_display,
           CASE WHEN p.phone IS NOT NULL AND length(p.phone) >= 4
                THEN right(p.phone, 4) ELSE NULL END AS driver_phone_last4
      FROM public.driver_group_memberships m
      LEFT JOIN public.profiles p ON p.id = m.driver_user_id
     WHERE m.group_id = v_group
     ORDER BY m.joined_at DESC;
END $$;
REVOKE EXECUTE ON FUNCTION public.leader_list_my_members() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.leader_list_my_members() TO authenticated;

CREATE OR REPLACE FUNCTION public.leader_list_my_commissions(p_status text DEFAULT NULL)
RETURNS SETOF public.driver_group_commissions
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_group uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  v_group := public._leader_group_id(v_uid);
  IF v_group IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT * FROM public.driver_group_commissions
     WHERE group_id = v_group
       AND (p_status IS NULL OR status = p_status)
     ORDER BY created_at DESC
     LIMIT 500;
END $$;
REVOKE EXECUTE ON FUNCTION public.leader_list_my_commissions(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.leader_list_my_commissions(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.leader_list_my_referrals(p_status text DEFAULT NULL)
RETURNS SETOF public.driver_referrals
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_group uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  v_group := public._leader_group_id(v_uid);
  IF v_group IS NULL THEN RETURN; END IF;
  RETURN QUERY
    SELECT * FROM public.driver_referrals
     WHERE group_id = v_group
       AND (p_status IS NULL OR status = p_status)
     ORDER BY created_at DESC
     LIMIT 500;
END $$;
REVOKE EXECUTE ON FUNCTION public.leader_list_my_referrals(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.leader_list_my_referrals(text) TO authenticated;


-- --- 5) Shared stats helper + admin & leader entry points ------------
CREATE OR REPLACE FUNCTION public._driver_group_stats(p_group uuid, p_from timestamptz, p_to timestamptz)
RETURNS TABLE (
  group_id uuid,
  active_drivers bigint,
  rides_completed bigint,
  gross_driver_earnings_gnf bigint,
  commissions_pending_gnf bigint,
  commissions_paid_gnf bigint,
  signup_bonus_eligible_count bigint,
  signup_bonus_paid_gnf bigint
) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH g AS (
    SELECT id FROM public.driver_groups
     WHERE (p_group IS NULL OR id = p_group)
  )
  SELECT
    g.id AS group_id,
    (SELECT count(*) FROM public.driver_group_memberships m
      WHERE m.group_id = g.id AND m.status = 'active') AS active_drivers,
    (SELECT count(*) FROM public.rides r
       JOIN public.driver_group_memberships m
         ON m.driver_user_id = r.driver_id AND m.group_id = g.id AND m.status = 'active'
      WHERE r.status = 'completed' AND r.completed_at >= p_from AND r.completed_at < p_to) AS rides_completed,
    COALESCE((SELECT sum(r.driver_earning_gnf) FROM public.rides r
       JOIN public.driver_group_memberships m
         ON m.driver_user_id = r.driver_id AND m.group_id = g.id AND m.status = 'active'
      WHERE r.status = 'completed' AND r.completed_at >= p_from AND r.completed_at < p_to), 0)::bigint AS gross_driver_earnings_gnf,
    COALESCE((SELECT sum(c.commission_amount_gnf) FROM public.driver_group_commissions c
      WHERE c.group_id = g.id AND c.status IN ('pending','approved') AND c.created_at >= p_from AND c.created_at < p_to), 0)::bigint AS commissions_pending_gnf,
    COALESCE((SELECT sum(c.commission_amount_gnf) FROM public.driver_group_commissions c
      WHERE c.group_id = g.id AND c.status = 'paid' AND c.paid_at >= p_from AND c.paid_at < p_to), 0)::bigint AS commissions_paid_gnf,
    (SELECT count(*) FROM public.driver_referrals dr
      WHERE dr.group_id = g.id AND dr.status = 'bonus_eligible'
        AND dr.updated_at >= p_from AND dr.updated_at < p_to) AS signup_bonus_eligible_count,
    COALESCE((SELECT sum(dr.bonus_amount_gnf) FROM public.driver_referrals dr
      WHERE dr.group_id = g.id AND dr.status = 'paid'
        AND dr.paid_at >= p_from AND dr.paid_at < p_to), 0)::bigint AS signup_bonus_paid_gnf
  FROM g;
$$;

CREATE OR REPLACE FUNCTION public.admin_driver_group_stats(p_group uuid DEFAULT NULL, p_from timestamptz DEFAULT (now() - interval '30 days'), p_to timestamptz DEFAULT now())
RETURNS SETOF record LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid())
     AND NOT public.has_app_role(auth.uid(), 'finance_admin') THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT * FROM public._driver_group_stats(p_group, p_from, p_to);
END $$;
-- Use the typed wrapper instead for client typing simplicity:
DROP FUNCTION public.admin_driver_group_stats(uuid, timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION public.admin_driver_group_stats(p_group uuid DEFAULT NULL, p_from timestamptz DEFAULT (now() - interval '30 days'), p_to timestamptz DEFAULT now())
RETURNS TABLE (
  group_id uuid,
  active_drivers bigint,
  rides_completed bigint,
  gross_driver_earnings_gnf bigint,
  commissions_pending_gnf bigint,
  commissions_paid_gnf bigint,
  signup_bonus_eligible_count bigint,
  signup_bonus_paid_gnf bigint
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid())
     AND NOT public.has_app_role(auth.uid(), 'finance_admin') THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT * FROM public._driver_group_stats(p_group, p_from, p_to);
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_driver_group_stats(uuid, timestamptz, timestamptz) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_driver_group_stats(uuid, timestamptz, timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.leader_get_my_stats(p_from timestamptz DEFAULT (now() - interval '30 days'), p_to timestamptz DEFAULT now())
RETURNS TABLE (
  group_id uuid,
  active_drivers bigint,
  rides_completed bigint,
  gross_driver_earnings_gnf bigint,
  commissions_pending_gnf bigint,
  commissions_paid_gnf bigint,
  signup_bonus_eligible_count bigint,
  signup_bonus_paid_gnf bigint
) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_group uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  v_group := public._leader_group_id(v_uid);
  IF v_group IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT * FROM public._driver_group_stats(v_group, p_from, p_to);
END $$;
REVOKE EXECUTE ON FUNCTION public.leader_get_my_stats(timestamptz, timestamptz) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.leader_get_my_stats(timestamptz, timestamptz) TO authenticated;
