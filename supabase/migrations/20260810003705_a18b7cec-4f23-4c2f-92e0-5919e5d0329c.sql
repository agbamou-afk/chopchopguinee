-- DEF-S4-001: driver_funding_allocate is an internal, read-only allocation helper.
-- Its auth.uid() gate blocked legitimate internal callers (a driver accepting their
-- own mission) while providing no real protection. Privilege is enforced by GRANTs.
CREATE OR REPLACE FUNCTION public.driver_funding_allocate(p_driver uuid, p_amount bigint, p_kind text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_w public.wallets;
  v_promo jsonb;
  v_promo_avail bigint;
  v_unrestricted bigint;
  v_amount bigint := GREATEST(COALESCE(p_amount, 0), 0);
  v_p bigint := 0;
  v_u bigint := 0;
BEGIN
  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver';

  v_promo := public.driver_promo_balance(p_driver);
  v_promo_avail := (v_promo->>'promo_available_gnf')::bigint;
  v_unrestricted := GREATEST(COALESCE(v_w.balance_gnf, 0) - COALESCE(v_w.held_gnf, 0) - v_promo_avail, 0);

  IF v_amount = 0 THEN
    RETURN jsonb_build_object('unrestricted_gnf', 0, 'promo_gnf', 0, 'ok', true);
  END IF;

  IF p_kind = 'cash_funding' THEN
    -- Restricted promotional credit may NEVER fund merchandise principal.
    IF v_unrestricted < v_amount THEN
      RETURN jsonb_build_object('unrestricted_gnf', 0, 'promo_gnf', 0, 'ok', false,
                                'reason', 'CASH_FUNDING_REQUIRES_UNRESTRICTED');
    END IF;
    RETURN jsonb_build_object('unrestricted_gnf', v_amount, 'promo_gnf', 0, 'ok', true);

  ELSIF p_kind IN ('commission','platform_fee') THEN
    v_p := LEAST(v_promo_avail, v_amount);
    v_u := v_amount - v_p;

  ELSE -- collateral: proportional, traceable allocation
    IF v_promo_avail + v_unrestricted > 0 THEN
      v_p := LEAST(v_promo_avail, (v_amount * v_promo_avail) / (v_promo_avail + v_unrestricted));
    END IF;
    v_u := v_amount - v_p;
    IF v_u > v_unrestricted THEN
      v_p := LEAST(v_promo_avail, v_amount - v_unrestricted);
      v_u := v_amount - v_p;
    END IF;
  END IF;

  IF v_u > v_unrestricted OR v_p > v_promo_avail THEN
    RETURN jsonb_build_object('unrestricted_gnf', 0, 'promo_gnf', 0, 'ok', false,
                              'reason', 'INSUFFICIENT_DRIVER_BALANCE');
  END IF;

  RETURN jsonb_build_object('unrestricted_gnf', v_u, 'promo_gnf', v_p, 'ok', true);
END; $$;

REVOKE ALL ON FUNCTION public.driver_funding_allocate(uuid,bigint,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.driver_funding_allocate(uuid,bigint,text) TO service_role;