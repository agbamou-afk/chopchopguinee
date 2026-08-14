CREATE OR REPLACE FUNCTION public.repas_admin_restaurant_overview()
RETURNS TABLE(
  id uuid, name text, district text, cuisine text,
  owner_user_id uuid, owner_label text,
  merchant_store_id uuid, merchant_store_name text, merchant_store_status text,
  verification_state text, status text, is_open boolean,
  menu_items_total int, menu_items_available int,
  delivery_available boolean, pickup_available boolean, choppay_enabled boolean,
  has_coordinates boolean, delivery_ready boolean, pickup_ready boolean,
  discoverable boolean, orderable_now boolean, blocked_reason text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public._repas_caller_is_staff() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT r.*,
           (SELECT count(*) FROM public.food_menu_items m WHERE m.restaurant_id = r.id) AS tot,
           (SELECT count(*) FROM public.food_menu_items m WHERE m.restaurant_id = r.id AND m.is_available) AS av
      FROM public.food_restaurants r
  ), shaped AS (
    SELECT b.id, b.name, b.district, b.cuisine,
           b.owner_user_id,
           coalesce(nullif(btrim(p.full_name), ''), left(b.owner_user_id::text, 8)) AS owner_label,
           b.merchant_store_id, ms.store_name AS merchant_store_name, ms.status::text AS merchant_store_status,
           coalesce(b.verification_state,'none') AS verification_state,
           b.status, coalesce(b.is_open,false) AS is_open,
           b.tot::int AS menu_items_total, b.av::int AS menu_items_available,
           coalesce(b.delivery_available,false) AS delivery_available,
           coalesce(b.pickup_available,false) AS pickup_available,
           coalesce(b.choppay_enabled,false) AS choppay_enabled,
           (b.latitude IS NOT NULL AND b.longitude IS NOT NULL) AS has_coordinates,
           (coalesce(b.delivery_available,false) AND b.latitude IS NOT NULL AND b.longitude IS NOT NULL) AS delivery_ready,
           coalesce(b.pickup_available,false) AS pickup_ready,
           b.created_at
      FROM base b
      LEFT JOIN public.profiles p ON p.id = b.owner_user_id
      LEFT JOIN public.merchant_stores ms ON ms.id = b.merchant_store_id
  ), truth AS (
    SELECT s.*,
           (s.status = 'active' AND s.verification_state = 'verified' AND s.menu_items_total > 0) AS discoverable
      FROM shaped s
  )
  SELECT t.id, t.name, t.district, t.cuisine,
         t.owner_user_id, t.owner_label,
         t.merchant_store_id, t.merchant_store_name, t.merchant_store_status,
         t.verification_state, t.status, t.is_open,
         t.menu_items_total, t.menu_items_available,
         t.delivery_available, t.pickup_available, t.choppay_enabled,
         t.has_coordinates, t.delivery_ready, t.pickup_ready,
         t.discoverable,
         (t.discoverable AND t.is_open AND t.menu_items_available > 0
          AND (t.pickup_ready OR t.delivery_ready)) AS orderable_now,
         CASE
           WHEN t.status <> 'active' OR t.verification_state <> 'verified' THEN 'not_published'
           WHEN t.menu_items_total = 0 THEN 'no_menu'
           WHEN NOT t.is_open THEN 'closed'
           WHEN t.menu_items_available = 0 THEN 'no_available_items'
           WHEN NOT (t.pickup_ready OR t.delivery_ready) THEN 'no_fulfillment'
           ELSE NULL
         END AS blocked_reason,
         t.created_at
    FROM truth t
   ORDER BY t.created_at DESC
   LIMIT 500;
END;
$function$;

REVOKE ALL ON FUNCTION public.repas_admin_restaurant_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_admin_restaurant_overview() TO authenticated, service_role;
