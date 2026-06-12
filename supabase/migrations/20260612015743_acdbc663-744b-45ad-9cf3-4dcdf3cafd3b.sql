
-- Phase 6D: Trusted Repas completion RPC + auto capture/settle

-- Add completed_at column (nullable, set when state becomes 'completed' via trusted path)
ALTER TABLE public.food_orders
  ADD COLUMN IF NOT EXISTS completed_at timestamptz;

-- ----------------------------------------------------------------
-- Trigger: block direct UPDATE to state='completed' for wallet orders
-- unless caller is service_role / supabase_admin / postgres / admin role
-- A SECURITY DEFINER RPC may bypass via session GUC repas.completion_trusted.
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prevent_unsafe_food_order_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller text;
  v_trusted text;
BEGIN
  IF NEW.state IS NOT DISTINCT FROM OLD.state THEN
    RETURN NEW;
  END IF;
  IF NEW.state::text <> 'completed' THEN
    RETURN NEW;
  END IF;
  -- Allow non-wallet orders to use existing path (cash/manual)
  IF COALESCE(NEW.payment_method::text, '') <> 'wallet' THEN
    RETURN NEW;
  END IF;

  v_caller := current_user;
  IF v_caller IN ('service_role', 'postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;

  -- Trusted RPC sets this GUC for the txn
  BEGIN
    v_trusted := current_setting('repas.completion_trusted', true);
  EXCEPTION WHEN OTHERS THEN
    v_trusted := NULL;
  END;
  IF v_trusted = 'on' THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS NOT NULL AND public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'completion_requires_trusted_rpc: use repas_complete_order() for wallet orders'
    USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_unsafe_food_order_completion ON public.food_orders;
CREATE TRIGGER trg_prevent_unsafe_food_order_completion
  BEFORE UPDATE OF state ON public.food_orders
  FOR EACH ROW EXECUTE FUNCTION public.prevent_unsafe_food_order_completion();

-- ----------------------------------------------------------------
-- Trusted completion RPC
-- ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.repas_complete_order(
  p_food_order_id uuid,
  p_reason text DEFAULT 'Repas order completed'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_order public.food_orders%ROWTYPE;
  v_resto public.food_restaurants%ROWTYPE;
  v_caller_uid uuid := auth.uid();
  v_caller text := current_user;
  v_is_admin boolean := false;
  v_is_owner boolean := false;
  v_capture jsonb;
  v_already_completed boolean := false;
BEGIN
  IF p_food_order_id IS NULL THEN
    RAISE EXCEPTION 'food_order_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM public.food_orders WHERE id = p_food_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'food_order_not_found: %', p_food_order_id USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_resto FROM public.food_restaurants WHERE id = v_order.restaurant_id;

  -- Authorization
  IF v_caller IN ('service_role', 'postgres', 'supabase_admin') THEN
    v_is_admin := true;
  ELSIF v_caller_uid IS NOT NULL AND public.has_role(v_caller_uid, 'admin'::app_role) THEN
    v_is_admin := true;
  ELSIF v_caller_uid IS NOT NULL AND v_resto.owner_user_id = v_caller_uid THEN
    v_is_owner := true;
  END IF;

  IF NOT (v_is_admin OR v_is_owner) THEN
    RAISE EXCEPTION 'not_authorized_to_complete_order' USING ERRCODE = '42501';
  END IF;

  IF v_order.state::text = 'cancelled' THEN
    RAISE EXCEPTION 'order_cancelled_cannot_complete' USING ERRCODE = '22023';
  END IF;

  v_already_completed := (v_order.state::text = 'completed');

  -- Mark trusted for the txn so our completion trigger allows the state change
  PERFORM set_config('repas.completion_trusted', 'on', true);

  IF NOT v_already_completed THEN
    UPDATE public.food_orders
       SET state = 'completed',
           completed_at = COALESCE(completed_at, now()),
           updated_at = now()
     WHERE id = p_food_order_id;
  END IF;

  -- Capture + settlement hook
  IF v_order.payment_method::text = 'wallet' THEN
    IF COALESCE(v_order.payment_status::text, '') = 'authorized' THEN
      v_capture := public.repas_capture_and_settle_order(p_food_order_id, p_reason);
    ELSIF COALESCE(v_order.payment_status::text, '') = 'paid' THEN
      v_capture := jsonb_build_object('ok', true, 'captured', false, 'settled', v_order.settlement_state = 'settled', 'reason', 'already_paid');
    ELSE
      v_capture := jsonb_build_object('ok', false, 'captured', false, 'settled', false, 'reason', 'payment_not_authorized:' || COALESCE(v_order.payment_status::text, 'null'));
      -- Mark settlement_state as needs_review when unpaid wallet order is force-completed
      UPDATE public.food_orders
         SET settlement_state = 'needs_review'
       WHERE id = p_food_order_id
         AND COALESCE(settlement_state, 'pending') = 'pending';
    END IF;
  ELSE
    v_capture := jsonb_build_object('ok', true, 'captured', false, 'settled', false, 'reason', 'non_wallet_payment');
  END IF;

  INSERT INTO public.audit_logs(actor_id, action, target_type, target_id, metadata)
  VALUES (
    v_caller_uid,
    'repas_complete_order',
    'food_order',
    p_food_order_id,
    jsonb_build_object(
      'reason', p_reason,
      'idempotent', v_already_completed,
      'payment_method', v_order.payment_method,
      'prior_payment_status', v_order.payment_status,
      'capture_result', v_capture,
      'is_admin', v_is_admin,
      'is_owner', v_is_owner
    )
  );

  RETURN jsonb_build_object(
    'ok', true,
    'food_order_id', p_food_order_id,
    'state', 'completed',
    'idempotent', v_already_completed,
    'capture', v_capture
  );
END;
$$;

REVOKE ALL ON FUNCTION public.repas_complete_order(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_complete_order(uuid, text) TO authenticated, service_role;
