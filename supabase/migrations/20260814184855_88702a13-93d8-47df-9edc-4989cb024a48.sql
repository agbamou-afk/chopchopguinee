-- ============================================================
-- NODE 3 / REPAS R8 — DISCOVERY & PUBLICATION TRUTH
-- ============================================================

-- ---------- A. privileged-column guard ----------
CREATE OR REPLACE FUNCTION public._repas_caller_is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
     AND (public.has_role(auth.uid(), 'admin'::public.app_role)
          OR public._is_ops_or_god_admin(auth.uid()))
$$;

CREATE OR REPLACE FUNCTION public._food_restaurant_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_staff boolean := public._repas_caller_is_staff();
  v_bypass boolean := coalesce(current_setting('app.repas_publication_ctx', true), '') = '1';
BEGIN
  IF v_staff OR v_bypass THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    -- A merchant may only ever create a DRAFT restaurant it owns.
    NEW.owner_user_id      := auth.uid();
    NEW.verification_state := 'none';
    NEW.choppay_enabled    := false;
    NEW.merchant_store_id  := NULL;
    NEW.status             := 'active';
    RETURN NEW;
  END IF;

  IF NEW.verification_state IS DISTINCT FROM OLD.verification_state THEN
    RAISE EXCEPTION 'RESTAURANT_PUBLICATION_IS_STAFF_ONLY';
  END IF;
  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
    RAISE EXCEPTION 'RESTAURANT_OWNER_IS_IMMUTABLE';
  END IF;
  IF NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id THEN
    RAISE EXCEPTION 'RESTAURANT_STORE_LINK_IS_STAFF_ONLY';
  END IF;
  IF NEW.choppay_enabled IS DISTINCT FROM OLD.choppay_enabled THEN
    RAISE EXCEPTION 'RESTAURANT_CHOPPAY_IS_STAFF_ONLY';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'RESTAURANT_STATUS_IS_STAFF_ONLY';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_food_restaurant_guard ON public.food_restaurants;
CREATE TRIGGER trg_food_restaurant_guard
BEFORE INSERT OR UPDATE ON public.food_restaurants
FOR EACH ROW EXECUTE FUNCTION public._food_restaurant_guard();

-- ---------- B. RLS: published-only public reads ----------
DROP POLICY IF EXISTS "Anyone read active restaurants" ON public.food_restaurants;
CREATE POLICY "Published restaurants are publicly readable"
ON public.food_restaurants FOR SELECT
USING (
  (status = 'active' AND verification_state = 'verified')
  OR owner_user_id = auth.uid()
  OR public.has_role(auth.uid(), 'admin'::public.app_role)
);

DROP POLICY IF EXISTS "Anyone read menu items" ON public.food_menu_items;
CREATE POLICY "Published restaurant menus are publicly readable"
ON public.food_menu_items FOR SELECT
USING (EXISTS (
  SELECT 1 FROM public.food_restaurants r
   WHERE r.id = food_menu_items.restaurant_id
     AND ((r.status = 'active' AND r.verification_state = 'verified')
          OR r.owner_user_id = auth.uid()
          OR public.has_role(auth.uid(), 'admin'::public.app_role))
));

-- ---------- C. canonical discovery read model ----------
CREATE OR REPLACE FUNCTION public.repas_restaurants_discover(
  p_search text DEFAULT NULL,
  p_limit  int  DEFAULT 40
)
RETURNS TABLE (
  id uuid,
  name text,
  cuisine text,
  district text,
  cover_url text,
  avatar_url text,
  is_open boolean,
  prep_time_min int,
  delivery_available boolean,
  pickup_available boolean,
  choppay_enabled boolean,
  verified boolean,
  has_coordinates boolean,
  delivery_ready boolean,
  pickup_ready boolean,
  menu_items_total int,
  menu_items_available int,
  orderable_now boolean,
  blocked_reason text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT r.*,
           (SELECT count(*) FROM public.food_menu_items m WHERE m.restaurant_id = r.id) AS tot,
           (SELECT count(*) FROM public.food_menu_items m WHERE m.restaurant_id = r.id AND m.is_available) AS av
      FROM public.food_restaurants r
     WHERE r.status = 'active'
       AND r.verification_state = 'verified'
  ), shaped AS (
    SELECT b.id, b.name, b.cuisine, b.district, b.cover_url, b.avatar_url,
           b.is_open, b.prep_time_min,
           b.delivery_available, b.pickup_available, b.choppay_enabled,
           true AS verified,
           (b.latitude IS NOT NULL AND b.longitude IS NOT NULL) AS has_coordinates,
           (b.delivery_available AND b.latitude IS NOT NULL AND b.longitude IS NOT NULL) AS delivery_ready,
           b.pickup_available AS pickup_ready,
           b.tot::int AS menu_items_total,
           b.av::int  AS menu_items_available
      FROM base b
     -- zero-menu supply is never marketed as usable
     WHERE b.tot > 0
  )
  SELECT s.*,
         (s.is_open
          AND s.menu_items_available > 0
          AND (s.pickup_ready OR s.delivery_ready)) AS orderable_now,
         CASE
           WHEN NOT s.is_open THEN 'closed'
           WHEN s.menu_items_available = 0 THEN 'no_available_items'
           WHEN NOT (s.pickup_ready OR s.delivery_ready) THEN 'no_fulfillment'
           ELSE NULL
         END AS blocked_reason
    FROM shaped s
   WHERE p_search IS NULL
      OR btrim(p_search) = ''
      OR s.name     ILIKE '%' || btrim(p_search) || '%'
      OR coalesce(s.cuisine, '')  ILIKE '%' || btrim(p_search) || '%'
      OR coalesce(s.district, '') ILIKE '%' || btrim(p_search) || '%'
   ORDER BY (s.is_open AND s.menu_items_available > 0) DESC, s.is_open DESC, s.name ASC
   LIMIT greatest(1, least(coalesce(p_limit, 40), 100));
$$;

CREATE OR REPLACE FUNCTION public.repas_restaurant_public(p_restaurant_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.food_restaurants;
  v_tot int; v_av int; v_published boolean; v_priv boolean;
BEGIN
  SELECT * INTO r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF r.id IS NULL THEN RETURN NULL; END IF;

  v_published := (r.status = 'active' AND r.verification_state = 'verified');
  v_priv := (auth.uid() IS NOT NULL AND auth.uid() = r.owner_user_id)
            OR public._repas_caller_is_staff();
  IF NOT v_published AND NOT v_priv THEN
    RETURN NULL;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE is_available) INTO v_tot, v_av
    FROM public.food_menu_items WHERE restaurant_id = r.id;

  RETURN jsonb_build_object(
    'id', r.id,
    'name', r.name,
    'cuisine', r.cuisine,
    'district', r.district,
    'cover_url', r.cover_url,
    'avatar_url', r.avatar_url,
    'is_open', r.is_open,
    'prep_time_min', r.prep_time_min,
    'delivery_available', r.delivery_available,
    'pickup_available', r.pickup_available,
    'choppay_enabled', r.choppay_enabled,
    'verified', v_published,
    'published', v_published,
    'publication_state', CASE WHEN v_published THEN 'published'
                              WHEN r.verification_state = 'suspended' THEN 'suspended'
                              ELSE 'draft' END,
    'has_coordinates', (r.latitude IS NOT NULL AND r.longitude IS NOT NULL),
    'delivery_ready', (r.delivery_available AND r.latitude IS NOT NULL AND r.longitude IS NOT NULL),
    'pickup_ready', r.pickup_available,
    'menu_items_total', v_tot,
    'menu_items_available', v_av,
    'orderable_now', (v_published AND r.is_open AND v_av > 0
                      AND (r.pickup_available
                           OR (r.delivery_available AND r.latitude IS NOT NULL AND r.longitude IS NOT NULL))),
    'blocked_reason', CASE
        WHEN NOT v_published THEN 'not_published'
        WHEN NOT r.is_open THEN 'closed'
        WHEN v_tot = 0 THEN 'no_menu'
        WHEN v_av = 0 THEN 'no_available_items'
        WHEN NOT (r.pickup_available
                  OR (r.delivery_available AND r.latitude IS NOT NULL AND r.longitude IS NOT NULL))
             THEN 'no_fulfillment'
        ELSE NULL END,
    'viewer_is_owner', (auth.uid() IS NOT NULL AND auth.uid() = r.owner_user_id)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.repas_restaurant_menu_public(p_restaurant_id uuid)
RETURNS TABLE (
  id uuid,
  restaurant_id uuid,
  name text,
  description text,
  photo_url text,
  price_gnf bigint,
  category text,
  is_available boolean,
  prep_time_min int,
  sort_position int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.food_restaurants;
BEGIN
  SELECT * INTO r FROM public.food_restaurants WHERE food_restaurants.id = p_restaurant_id;
  IF r.id IS NULL THEN RETURN; END IF;
  IF NOT (r.status = 'active' AND r.verification_state = 'verified')
     AND NOT ((auth.uid() IS NOT NULL AND auth.uid() = r.owner_user_id)
              OR public._repas_caller_is_staff()) THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT m.id, m.restaurant_id, m.name, m.description, m.photo_url,
           m.price_gnf, m.category, m.is_available, m.prep_time_min, m."position"
      FROM public.food_menu_items m
     WHERE m.restaurant_id = p_restaurant_id
     ORDER BY m."position" ASC, m.name ASC;
END;
$$;

-- ---------- D. staff publication decision ----------
CREATE OR REPLACE FUNCTION public.repas_admin_set_publication(
  p_restaurant_id uuid,
  p_action text,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.food_restaurants;
  v_before jsonb; v_new_state text; v_new_status text;
BEGIN
  IF NOT public._repas_caller_is_staff() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF p_action NOT IN ('publish','unpublish','suspend','reject') THEN
    RAISE EXCEPTION 'INVALID_ACTION';
  END IF;

  SELECT * INTO r FROM public.food_restaurants WHERE id = p_restaurant_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;

  v_before := jsonb_build_object('verification_state', r.verification_state, 'status', r.status);

  v_new_state := CASE p_action
    WHEN 'publish'   THEN 'verified'
    WHEN 'unpublish' THEN 'none'
    WHEN 'suspend'   THEN 'suspended'
    WHEN 'reject'    THEN 'rejected'
  END;
  v_new_status := CASE WHEN p_action IN ('suspend','reject') THEN 'inactive' ELSE 'active' END;

  PERFORM set_config('app.repas_publication_ctx', '1', true);
  UPDATE public.food_restaurants
     SET verification_state = v_new_state,
         status = v_new_status,
         updated_at = now()
   WHERE id = p_restaurant_id;
  PERFORM set_config('app.repas_publication_ctx', '', true);

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, before, after, note)
  VALUES (auth.uid(), 'admin', 'repas', 'restaurant_' || p_action, 'food_restaurant', p_restaurant_id,
          v_before,
          jsonb_build_object('verification_state', v_new_state, 'status', v_new_status),
          nullif(btrim(coalesce(p_reason, '')), ''));

  RETURN jsonb_build_object('id', p_restaurant_id, 'verification_state', v_new_state, 'status', v_new_status);
END;
$$;

-- ---------- E. privileges ----------
REVOKE ALL ON FUNCTION public._repas_caller_is_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._repas_caller_is_staff() TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.repas_restaurants_discover(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_restaurants_discover(text, int) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.repas_restaurant_public(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_restaurant_public(uuid) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.repas_restaurant_menu_public(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_restaurant_menu_public(uuid) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.repas_admin_set_publication(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_admin_set_publication(uuid, text, text) TO authenticated, service_role;