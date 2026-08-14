DROP FUNCTION IF EXISTS public.repas_restaurants_discover(text,integer);
CREATE FUNCTION public.repas_restaurants_discover(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS TABLE(id uuid, name text, cuisine text, district text, cover_url text, avatar_url text, is_open boolean, prep_time_min integer, delivery_available boolean, pickup_available boolean, choppay_enabled boolean, verified boolean, has_coordinates boolean, delivery_ready boolean, pickup_ready boolean, menu_items_total integer, menu_items_available integer, orderable_now boolean, blocked_reason text, orderable_pickup boolean, orderable_delivery boolean, pickup_blocked_reason text, delivery_blocked_reason text, delivery_destination_check_required boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH pol AS (
    SELECT NULLIF(public.repas_pricing_effective('delivery')->>'delivery_max_distance_km','')::numeric AS max_km
  ), base AS (
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
           (b.delivery_available AND (p.max_km IS NULL OR (b.latitude IS NOT NULL AND b.longitude IS NOT NULL))) AS delivery_ready,
           b.pickup_available AS pickup_ready,
           b.tot::int AS menu_items_total,
           b.av::int  AS menu_items_available,
           p.max_km
      FROM base b CROSS JOIN pol p
     -- zero-menu supply is never marketed as usable
     WHERE b.tot > 0
  ), derived AS (
    SELECT s.*,
           (s.is_open AND s.menu_items_available > 0 AND s.pickup_ready)  AS ord_pickup,
           (s.is_open AND s.menu_items_available > 0 AND s.delivery_ready) AS ord_delivery
      FROM shaped s
  )
  SELECT d.id, d.name, d.cuisine, d.district, d.cover_url, d.avatar_url,
         d.is_open, d.prep_time_min, d.delivery_available, d.pickup_available,
         d.choppay_enabled, d.verified, d.has_coordinates, d.delivery_ready, d.pickup_ready,
         d.menu_items_total, d.menu_items_available,
         (d.ord_pickup OR d.ord_delivery) AS orderable_now,
         CASE
           WHEN NOT d.is_open THEN 'closed'
           WHEN d.menu_items_available = 0 THEN 'no_available_items'
           WHEN NOT (d.ord_pickup OR d.ord_delivery) THEN 'no_fulfillment'
           ELSE NULL
         END AS blocked_reason,
         d.ord_pickup AS orderable_pickup,
         d.ord_delivery AS orderable_delivery,
         CASE
           WHEN d.ord_pickup THEN NULL
           WHEN NOT d.pickup_available THEN 'PICKUP_NOT_OFFERED'
           WHEN NOT d.is_open THEN 'RESTAURANT_CLOSED'
           WHEN d.menu_items_available = 0 THEN 'NO_AVAILABLE_ITEMS'
           ELSE 'PICKUP_UNAVAILABLE'
         END AS pickup_blocked_reason,
         CASE
           WHEN d.ord_delivery THEN NULL
           WHEN NOT d.delivery_available THEN 'DELIVERY_NOT_OFFERED'
           WHEN NOT d.delivery_ready THEN 'DELIVERY_DISTANCE_UNVERIFIABLE'
           WHEN NOT d.is_open THEN 'RESTAURANT_CLOSED'
           WHEN d.menu_items_available = 0 THEN 'NO_AVAILABLE_ITEMS'
           ELSE 'DELIVERY_UNAVAILABLE'
         END AS delivery_blocked_reason,
         (d.ord_delivery AND d.max_km IS NOT NULL) AS delivery_destination_check_required
    FROM derived d
   WHERE p_search IS NULL
      OR btrim(p_search) = ''
      OR d.name     ILIKE '%' || btrim(p_search) || '%'
      OR coalesce(d.cuisine, '')  ILIKE '%' || btrim(p_search) || '%'
      OR coalesce(d.district, '') ILIKE '%' || btrim(p_search) || '%'
   ORDER BY (d.ord_pickup OR d.ord_delivery) DESC, d.is_open DESC, d.name ASC
   LIMIT greatest(1, least(coalesce(p_limit, 40), 100));
$function$;

CREATE OR REPLACE FUNCTION public.repas_restaurant_public(p_restaurant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r public.food_restaurants;
  v_tot int; v_av int; v_published boolean; v_priv boolean;
  v_max numeric; v_geo boolean;
  v_delivery_ready boolean; v_pickup_ready boolean;
  v_ord_pickup boolean; v_ord_delivery boolean;
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

  v_max := NULLIF(public.repas_pricing_effective('delivery')->>'delivery_max_distance_km','')::numeric;
  v_geo := (r.latitude IS NOT NULL AND r.longitude IS NOT NULL);
  v_delivery_ready := (r.delivery_available AND (v_max IS NULL OR v_geo));
  v_pickup_ready := r.pickup_available;
  v_ord_pickup := (v_published AND r.is_open AND v_av > 0 AND v_pickup_ready);
  v_ord_delivery := (v_published AND r.is_open AND v_av > 0 AND v_delivery_ready);

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
    'has_coordinates', v_geo,
    'delivery_ready', v_delivery_ready,
    'pickup_ready', v_pickup_ready,
    'menu_items_total', v_tot,
    'menu_items_available', v_av,
    'orderable_now', (v_ord_pickup OR v_ord_delivery),
    'orderable_pickup', v_ord_pickup,
    'orderable_delivery', v_ord_delivery,
    'pickup_blocked_reason', CASE
        WHEN v_ord_pickup THEN NULL
        WHEN NOT v_published THEN 'RESTAURANT_NOT_PUBLISHED'
        WHEN NOT r.pickup_available THEN 'PICKUP_NOT_OFFERED'
        WHEN NOT r.is_open THEN 'RESTAURANT_CLOSED'
        WHEN v_av = 0 THEN 'NO_AVAILABLE_ITEMS'
        ELSE 'PICKUP_UNAVAILABLE' END,
    'delivery_blocked_reason', CASE
        WHEN v_ord_delivery THEN NULL
        WHEN NOT v_published THEN 'RESTAURANT_NOT_PUBLISHED'
        WHEN NOT r.delivery_available THEN 'DELIVERY_NOT_OFFERED'
        WHEN NOT v_delivery_ready THEN 'DELIVERY_DISTANCE_UNVERIFIABLE'
        WHEN NOT r.is_open THEN 'RESTAURANT_CLOSED'
        WHEN v_av = 0 THEN 'NO_AVAILABLE_ITEMS'
        ELSE 'DELIVERY_UNAVAILABLE' END,
    'delivery_destination_check_required', (v_ord_delivery AND v_max IS NOT NULL),
    'blocked_reason', CASE
        WHEN NOT v_published THEN 'not_published'
        WHEN NOT r.is_open THEN 'closed'
        WHEN v_tot = 0 THEN 'no_menu'
        WHEN v_av = 0 THEN 'no_available_items'
        WHEN NOT (v_pickup_ready OR v_delivery_ready) THEN 'no_fulfillment'
        ELSE NULL END,
    'viewer_is_owner', (auth.uid() IS NOT NULL AND auth.uid() = r.owner_user_id)
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.repas_restaurants_discover(text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_restaurants_discover(text,integer) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.repas_restaurant_public(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_restaurant_public(uuid) TO anon, authenticated, service_role;
