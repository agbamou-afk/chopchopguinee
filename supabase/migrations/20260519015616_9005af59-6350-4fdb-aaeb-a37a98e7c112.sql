-- Repas (food) foundation

-- Enums
DO $$ BEGIN
  CREATE TYPE public.food_fulfillment AS ENUM ('pickup', 'delivery');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.food_order_state AS ENUM ('placed','confirmed','preparing','ready','out_for_delivery','completed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.food_payment_method AS ENUM ('wallet','choppay','cash');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Restaurants
CREATE TABLE IF NOT EXISTS public.food_restaurants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid,
  slug text NOT NULL UNIQUE,
  name text NOT NULL,
  avatar_url text,
  cover_url text,
  district text,
  cuisine text,
  is_open boolean NOT NULL DEFAULT true,
  choppay_enabled boolean NOT NULL DEFAULT false,
  delivery_available boolean NOT NULL DEFAULT false,
  pickup_available boolean NOT NULL DEFAULT true,
  verification_state text NOT NULL DEFAULT 'none',
  prep_time_min integer NOT NULL DEFAULT 20,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.food_restaurants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone read active restaurants" ON public.food_restaurants
  FOR SELECT USING (status = 'active' OR owner_user_id = auth.uid() OR has_role(auth.uid(), 'admin'::app_role));

CREATE POLICY "Owners insert own restaurant" ON public.food_restaurants
  FOR INSERT WITH CHECK (auth.uid() = owner_user_id);

CREATE POLICY "Owners update own restaurant" ON public.food_restaurants
  FOR UPDATE USING (auth.uid() = owner_user_id) WITH CHECK (auth.uid() = owner_user_id);

CREATE POLICY "Admins manage restaurants" ON public.food_restaurants
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Menu items
CREATE TABLE IF NOT EXISTS public.food_menu_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.food_restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  photo_url text,
  price_gnf bigint NOT NULL DEFAULT 0,
  category text,
  is_available boolean NOT NULL DEFAULT true,
  prep_time_min integer,
  position integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_food_menu_items_restaurant ON public.food_menu_items(restaurant_id);

ALTER TABLE public.food_menu_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone read menu items" ON public.food_menu_items
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.food_restaurants r
            WHERE r.id = food_menu_items.restaurant_id
              AND (r.status = 'active' OR r.owner_user_id = auth.uid() OR has_role(auth.uid(), 'admin'::app_role)))
  );

CREATE POLICY "Owners manage own menu items" ON public.food_menu_items
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.food_restaurants r
            WHERE r.id = food_menu_items.restaurant_id AND r.owner_user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.food_restaurants r
            WHERE r.id = food_menu_items.restaurant_id AND r.owner_user_id = auth.uid())
  );

CREATE POLICY "Admins manage menu items" ON public.food_menu_items
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Orders
CREATE TABLE IF NOT EXISTS public.food_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  restaurant_id uuid NOT NULL REFERENCES public.food_restaurants(id) ON DELETE RESTRICT,
  fulfillment public.food_fulfillment NOT NULL DEFAULT 'pickup',
  state public.food_order_state NOT NULL DEFAULT 'placed',
  payment_method public.food_payment_method NOT NULL DEFAULT 'cash',
  subtotal_gnf bigint NOT NULL DEFAULT 0,
  notes text,
  delivery_address text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_food_orders_user ON public.food_orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_food_orders_restaurant ON public.food_orders(restaurant_id, created_at DESC);

ALTER TABLE public.food_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own orders" ON public.food_orders
  FOR SELECT USING (
    auth.uid() = user_id
    OR EXISTS (SELECT 1 FROM public.food_restaurants r WHERE r.id = food_orders.restaurant_id AND r.owner_user_id = auth.uid())
    OR has_role(auth.uid(), 'admin'::app_role)
  );

CREATE POLICY "Users create own orders" ON public.food_orders
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users cancel own pending orders" ON public.food_orders
  FOR UPDATE USING (auth.uid() = user_id AND state IN ('placed','confirmed'))
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Restaurant owners update orders" ON public.food_orders
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.food_restaurants r WHERE r.id = food_orders.restaurant_id AND r.owner_user_id = auth.uid())
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.food_restaurants r WHERE r.id = food_orders.restaurant_id AND r.owner_user_id = auth.uid())
  );

CREATE POLICY "Admins manage orders" ON public.food_orders
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- Order items
CREATE TABLE IF NOT EXISTS public.food_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.food_orders(id) ON DELETE CASCADE,
  menu_item_id uuid REFERENCES public.food_menu_items(id) ON DELETE SET NULL,
  name_snapshot text NOT NULL,
  unit_price_gnf bigint NOT NULL DEFAULT 0,
  qty integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_food_order_items_order ON public.food_order_items(order_id);

ALTER TABLE public.food_order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read own order items" ON public.food_order_items
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.food_orders o
            WHERE o.id = food_order_items.order_id
              AND (o.user_id = auth.uid()
                   OR EXISTS (SELECT 1 FROM public.food_restaurants r WHERE r.id = o.restaurant_id AND r.owner_user_id = auth.uid())
                   OR has_role(auth.uid(), 'admin'::app_role)))
  );

CREATE POLICY "Insert items for own orders" ON public.food_order_items
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.food_orders o WHERE o.id = food_order_items.order_id AND o.user_id = auth.uid())
  );

CREATE POLICY "Admins manage order items" ON public.food_order_items
  FOR ALL USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

-- updated_at triggers
DROP TRIGGER IF EXISTS trg_food_restaurants_updated ON public.food_restaurants;
CREATE TRIGGER trg_food_restaurants_updated BEFORE UPDATE ON public.food_restaurants
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_food_menu_items_updated ON public.food_menu_items;
CREATE TRIGGER trg_food_menu_items_updated BEFORE UPDATE ON public.food_menu_items
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_food_orders_updated ON public.food_orders;
CREATE TRIGGER trg_food_orders_updated BEFORE UPDATE ON public.food_orders
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
