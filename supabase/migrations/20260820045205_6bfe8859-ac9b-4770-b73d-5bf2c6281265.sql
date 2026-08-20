CREATE OR REPLACE FUNCTION public._marche_merchant_allowed_actions(p_order public.marche_orders)
RETURNS text[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE a text[] := ARRAY[]::text[]; st text := p_order.fulfillment_state;
BEGIN
  IF p_order.status <> 'committed' THEN RETURN a; END IF;

  IF st = 'committed' THEN a := a || 'accept'::text;
  ELSIF st = 'accepted' THEN a := a || 'prepare'::text;
  ELSIF st = 'preparing' THEN a := a || 'ready'::text;
  END IF;

  IF st IN ('committed','accepted','preparing','ready') AND p_order.mission_id IS NULL THEN
    a := a || 'reject'::text;
  END IF;

  IF st = 'ready' AND p_order.mission_id IS NULL
     AND NULLIF(btrim(COALESCE(p_order.delivery_address,'')),'') IS NOT NULL THEN
    a := a || 'request_dispatch'::text;
  END IF;

  RETURN a;
END $$;

REVOKE ALL ON FUNCTION public._marche_merchant_allowed_actions(public.marche_orders) FROM PUBLIC, anon, authenticated;
