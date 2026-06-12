
-- Phase 6A.1: Protect food_orders.payment_status from client tampering.
-- Backend-only states: paid, refunded, captured, confirmed.
-- Client-safe states: unpaid, pending, authorized, failed, cancelled.

CREATE OR REPLACE FUNCTION public.prevent_unsafe_food_order_payment_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new text;
  v_old text;
  v_caller text;
BEGIN
  v_new := NEW.payment_status::text;
  v_old := COALESCE(OLD.payment_status::text, '');

  -- No change to payment_status -> always allow.
  IF v_new IS NOT DISTINCT FROM v_old THEN
    RETURN NEW;
  END IF;

  v_caller := current_user;

  -- service_role and elevated DEFINER contexts (postgres/supabase_admin) may set any value.
  IF v_caller IN ('service_role', 'postgres', 'supabase_admin') THEN
    RETURN NEW;
  END IF;

  -- Admin users may also adjust (e.g. manual reconciliation through admin UI).
  IF auth.uid() IS NOT NULL AND public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN NEW;
  END IF;

  -- Hard-block protected states from any authenticated/anon client.
  IF v_new IN ('paid', 'refunded', 'captured', 'confirmed') THEN
    RAISE EXCEPTION 'payment_status_backend_only: cannot set payment_status=% from client', v_new
      USING ERRCODE = '42501';
  END IF;

  -- Allow client-safe transitions (unpaid, pending, authorized, failed, cancelled).
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_unsafe_food_order_payment_status_update ON public.food_orders;
CREATE TRIGGER trg_prevent_unsafe_food_order_payment_status_update
BEFORE UPDATE OF payment_status ON public.food_orders
FOR EACH ROW
EXECUTE FUNCTION public.prevent_unsafe_food_order_payment_status_update();

COMMENT ON FUNCTION public.prevent_unsafe_food_order_payment_status_update() IS
  'Phase 6A.1: blocks clients from setting food_orders.payment_status to paid/refunded/captured/confirmed. Only service_role, SECURITY DEFINER backend RPCs, and admins may set those states. Capture-only paid rule is enforced here.';
