-- =====================================================================
-- G6 — FINAL ADMIN ARCHITECTURE LOCK: privilege reduction only.
-- No authority is expanded. No economics, ledger law, Node 5 identity
-- law or capability semantics are changed.
-- =====================================================================

-- ---------------------------------------------------------------------
-- V3 — anon holds full DML grants on finance tables (blocked today only
-- by RLS). Remove the grants; anon has no policy on any of them.
-- ---------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.payment_receiving_accounts FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.payment_intents FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.payment_refund_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.topup_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.app_settings FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.driver_cashout_requests FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.driver_payout_policies FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.merchant_settlement_policies FROM anon;
REVOKE SELECT ON public.payment_receiving_accounts FROM anon;
REVOKE SELECT ON public.payment_intents FROM anon;
REVOKE SELECT ON public.payment_refund_requests FROM anon;
REVOKE SELECT ON public.driver_cashout_requests FROM anon;

-- ---------------------------------------------------------------------
-- V5/V6/V7 — no raw human mutation of governed finance rows.
-- Governed RPCs (SECURITY DEFINER, owned by postgres) are unaffected.
-- ---------------------------------------------------------------------
REVOKE INSERT, UPDATE, DELETE ON public.payment_intents FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.payment_refund_requests FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.topup_requests FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.app_settings FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.driver_cashout_requests FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.driver_payout_policies FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.merchant_settlement_policies FROM authenticated;

DROP POLICY IF EXISTS "Finance/super admins manage intents" ON public.payment_intents;
DROP POLICY IF EXISTS "Finance/god admins write app_settings" ON public.app_settings;
DROP POLICY IF EXISTS "Finance admins insert topups" ON public.topup_requests;
DROP POLICY IF EXISTS "Finance admins update topups" ON public.topup_requests;
DROP POLICY IF EXISTS "Finance admins delete topups" ON public.topup_requests;

-- ---------------------------------------------------------------------
-- V1 — approval law: no raw creation or decision of approval requests
-- from a browser session. admin_request_approval / admin_review_approval
-- are the only lawful paths (requester != approver, intent hash, expiry,
-- single consumption).
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Super admins review approvals" ON public.approval_requests;
DROP POLICY IF EXISTS "Admins create approval requests" ON public.approval_requests;
REVOKE INSERT, UPDATE, DELETE ON public.approval_requests FROM authenticated;

-- ---------------------------------------------------------------------
-- V4 — staff governance: no raw admin_users / user_roles mutation.
-- The G3 staff lifecycle is the only lawful path.
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS "Super admins manage admin_users" ON public.admin_users;
DROP POLICY IF EXISTS "Super admins manage roles" ON public.user_roles;
REVOKE INSERT, UPDATE, DELETE ON public.admin_users FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.user_roles FROM authenticated;

-- =====================================================================
-- V2 / PHASE H — Orange Money receiving-account seam
-- =====================================================================

ALTER TABLE public.payment_receiving_accounts
  ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS effective_from timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS retired_at timestamptz,
  ADD COLUMN IF NOT EXISTS superseded_by uuid REFERENCES public.payment_receiving_accounts(id);

REVOKE INSERT, UPDATE, DELETE ON public.payment_receiving_accounts FROM authenticated;
DROP POLICY IF EXISTS "Finance admins manage receiving accounts" ON public.payment_receiving_accounts;
CREATE POLICY "Finance/god read receiving accounts"
  ON public.payment_receiving_accounts FOR SELECT TO authenticated
  USING (public.can_manage_wallet(auth.uid()));

-- Defense in depth: even a future accidental grant cannot mutate a
-- receiving account from a browser session outside the governed RPCs.
CREATE OR REPLACE FUNCTION public._pra_governed_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF coalesce(current_setting('chopchop.pra_governed', true), '') <> '1'
     AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'receiving_account_governed_rpc_required' USING ERRCODE='42501';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_pra_governed_write_guard ON public.payment_receiving_accounts;
CREATE TRIGGER trg_pra_governed_write_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.payment_receiving_accounts
  FOR EACH ROW EXECUTE FUNCTION public._pra_governed_write_guard();

-- Narrow capabilities. No new authority for Operations (absence = denial).
INSERT INTO public.admin_capability_grants (capability, admin_role, mode)
VALUES
  ('finance.receiving_account.manage', 'finance_admin', 'allow'),
  ('finance.receiving_account.manage', 'god_admin', 'allow'),
  ('finance.receiving_account.route',  'finance_admin', 'approval_required'),
  ('finance.receiving_account.route',  'god_admin', 'approval_required')
ON CONFLICT (capability, admin_role) DO NOTHING;

CREATE OR REPLACE FUNCTION public._pra_in_financial_use(_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.topup_requests t WHERE t.receiving_account_id = _id)
      OR EXISTS (SELECT 1 FROM public.payment_provider_events e WHERE e.receiving_account_id = _id);
$$;
REVOKE EXECUTE ON FUNCTION public._pra_in_financial_use(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._pra_valid_phone(_provider text, _phone text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN _provider IN ('orange_money','mtn_money') THEN _phone ~ '^\+224[0-9]{9}$'
    ELSE coalesce(btrim(_phone),'') <> ''
  END;
$$;

-- Create: always inactive. Activation is an explicit separate act.
CREATE OR REPLACE FUNCTION public.admin_receiving_account_create(
  p_provider text,
  p_label text,
  p_phone_e164 text,
  p_public_instructions text DEFAULT NULL,
  p_admin_notes text DEFAULT NULL,
  _g2_approval uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  IF coalesce(btrim(p_label),'') = '' THEN
    RAISE EXCEPTION 'label_required' USING ERRCODE='22023';
  END IF;
  IF NOT public._pra_valid_phone(p_provider, p_phone_e164) THEN
    RAISE EXCEPTION 'invalid_receiving_phone' USING ERRCODE='22023';
  END IF;
  PERFORM public.admin_enforce(
    'finance.receiving_account.manage','payment_receiving_account','new',
    jsonb_build_object('provider',p_provider,'phone_e164',p_phone_e164),
    _g2_approval,'payments');

  PERFORM set_config('chopchop.pra_governed','1',true);
  INSERT INTO public.payment_receiving_accounts
    (provider,label,phone_e164,is_active,public_instructions,admin_notes,created_by,updated_by)
  VALUES (p_provider,btrim(p_label),btrim(p_phone_e164),false,
          nullif(btrim(coalesce(p_public_instructions,'')),''),
          nullif(btrim(coalesce(p_admin_notes,'')),''),
          auth.uid(), auth.uid())
  RETURNING id INTO v_id;
  PERFORM set_config('chopchop.pra_governed','0',true);

  PERFORM public.admin_audit_write('payments','receiving_account.create',
    'finance.receiving_account.manage','payment_receiving_account',v_id::text,
    NULL::jsonb,
    jsonb_build_object('provider',p_provider,'label',btrim(p_label),'phone_e164',btrim(p_phone_e164),'is_active',false),
    _g2_approval,'success');
  RETURN v_id;
END;
$$;

-- Metadata only: never touches provider, phone or activation state.
CREATE OR REPLACE FUNCTION public.admin_receiving_account_update_metadata(
  p_id uuid,
  p_label text,
  p_public_instructions text DEFAULT NULL,
  p_admin_notes text DEFAULT NULL,
  _g2_approval uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_before jsonb;
BEGIN
  SELECT to_jsonb(t) - 'admin_notes' INTO v_before
    FROM public.payment_receiving_accounts t WHERE t.id = p_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'receiving_account_not_found' USING ERRCODE='P0002'; END IF;
  IF coalesce(btrim(p_label),'') = '' THEN RAISE EXCEPTION 'label_required' USING ERRCODE='22023'; END IF;

  PERFORM public.admin_enforce(
    'finance.receiving_account.manage','payment_receiving_account',p_id::text,
    jsonb_build_object('action','metadata'), _g2_approval,'payments');

  PERFORM set_config('chopchop.pra_governed','1',true);
  UPDATE public.payment_receiving_accounts
     SET label = btrim(p_label),
         public_instructions = nullif(btrim(coalesce(p_public_instructions,'')),''),
         admin_notes = nullif(btrim(coalesce(p_admin_notes,'')),''),
         updated_by = auth.uid()
   WHERE id = p_id;
  PERFORM set_config('chopchop.pra_governed','0',true);

  PERFORM public.admin_audit_write('payments','receiving_account.metadata',
    'finance.receiving_account.manage','payment_receiving_account',p_id::text,
    v_before, jsonb_build_object('label',btrim(p_label)), _g2_approval,'success');
END;
$$;

-- Explicit activation / deactivation with a mandatory reason.
CREATE OR REPLACE FUNCTION public.admin_receiving_account_set_active(
  p_id uuid,
  p_active boolean,
  p_reason text,
  _g2_approval uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_active boolean; v_retired timestamptz;
BEGIN
  IF coalesce(btrim(p_reason),'') = '' THEN RAISE EXCEPTION 'reason_required' USING ERRCODE='22023'; END IF;
  SELECT is_active, retired_at INTO v_active, v_retired
    FROM public.payment_receiving_accounts WHERE id = p_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'receiving_account_not_found' USING ERRCODE='P0002'; END IF;
  IF p_active AND v_retired IS NOT NULL THEN
    RAISE EXCEPTION 'receiving_account_retired' USING ERRCODE='22023';
  END IF;

  PERFORM public.admin_enforce(
    'finance.receiving_account.manage','payment_receiving_account',p_id::text,
    jsonb_build_object('action','set_active','active',p_active), _g2_approval,'payments');

  PERFORM set_config('chopchop.pra_governed','1',true);
  UPDATE public.payment_receiving_accounts
     SET is_active = p_active, updated_by = auth.uid()
   WHERE id = p_id;
  PERFORM set_config('chopchop.pra_governed','0',true);

  PERFORM public.admin_audit_write('payments','receiving_account.set_active',
    'finance.receiving_account.manage','payment_receiving_account',p_id::text,
    jsonb_build_object('is_active',v_active),
    jsonb_build_object('is_active',p_active,'reason',btrim(p_reason)),
    _g2_approval,'success');
END;
$$;

-- Routing change: four-eyes. Never rewrites financial history — an
-- account already referenced by a top-up or provider event is retired
-- and superseded by a new versioned row.
CREATE OR REPLACE FUNCTION public.admin_receiving_account_replace_routing(
  p_id uuid,
  p_new_phone_e164 text,
  p_reason text,
  _g2_approval uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r public.payment_receiving_accounts%ROWTYPE; v_new uuid; v_used boolean;
BEGIN
  IF coalesce(btrim(p_reason),'') = '' THEN RAISE EXCEPTION 'reason_required' USING ERRCODE='22023'; END IF;
  SELECT * INTO r FROM public.payment_receiving_accounts WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'receiving_account_not_found' USING ERRCODE='P0002'; END IF;
  IF r.retired_at IS NOT NULL THEN RAISE EXCEPTION 'receiving_account_retired' USING ERRCODE='22023'; END IF;
  IF NOT public._pra_valid_phone(r.provider, p_new_phone_e164) THEN
    RAISE EXCEPTION 'invalid_receiving_phone' USING ERRCODE='22023';
  END IF;
  IF btrim(p_new_phone_e164) = r.phone_e164 THEN
    RAISE EXCEPTION 'routing_unchanged' USING ERRCODE='22023';
  END IF;

  PERFORM public.admin_enforce(
    'finance.receiving_account.route','payment_receiving_account',p_id::text,
    jsonb_build_object('phone_e164',btrim(p_new_phone_e164)), _g2_approval,'payments');

  v_used := public._pra_in_financial_use(p_id);
  PERFORM set_config('chopchop.pra_governed','1',true);

  IF v_used THEN
    INSERT INTO public.payment_receiving_accounts
      (provider,label,phone_e164,is_active,public_instructions,admin_notes,
       created_by,updated_by,version,effective_from)
    VALUES (r.provider,r.label,btrim(p_new_phone_e164),r.is_active,
            r.public_instructions,r.admin_notes,auth.uid(),auth.uid(),r.version+1,now())
    RETURNING id INTO v_new;
    UPDATE public.payment_receiving_accounts
       SET is_active = false, retired_at = now(), superseded_by = v_new, updated_by = auth.uid()
     WHERE id = p_id;
  ELSE
    UPDATE public.payment_receiving_accounts
       SET phone_e164 = btrim(p_new_phone_e164), version = version + 1,
           effective_from = now(), updated_by = auth.uid()
     WHERE id = p_id;
    v_new := p_id;
  END IF;

  PERFORM set_config('chopchop.pra_governed','0',true);

  PERFORM public.admin_audit_write('payments','receiving_account.route',
    'finance.receiving_account.route','payment_receiving_account',p_id::text,
    jsonb_build_object('phone_e164',r.phone_e164,'version',r.version),
    jsonb_build_object('phone_e164',btrim(p_new_phone_e164),'successor',v_new,
                       'superseded',v_used,'reason',btrim(p_reason)),
    _g2_approval,'success');
  RETURN v_new;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_receiving_account_create(text,text,text,text,text,uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_receiving_account_update_metadata(uuid,text,text,text,uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_receiving_account_set_active(uuid,boolean,text,uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_receiving_account_replace_routing(uuid,text,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_receiving_account_create(text,text,text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_receiving_account_update_metadata(uuid,text,text,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_receiving_account_set_active(uuid,boolean,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_receiving_account_replace_routing(uuid,text,text,uuid) TO authenticated;