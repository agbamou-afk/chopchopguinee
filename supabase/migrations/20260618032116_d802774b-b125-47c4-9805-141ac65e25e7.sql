
-- Enum for thread participant roles
DO $$ BEGIN
  CREATE TYPE public.food_order_thread_type AS ENUM ('restaurant_client_order','restaurant_courier_order');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE public.food_order_sender_role AS ENUM ('client','restaurant','courier','admin');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- THREADS
CREATE TABLE IF NOT EXISTS public.food_order_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  food_order_id uuid NOT NULL REFERENCES public.food_orders(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES public.food_restaurants(id) ON DELETE CASCADE,
  thread_type public.food_order_thread_type NOT NULL,
  client_user_id uuid NOT NULL,
  restaurant_owner_user_id uuid NOT NULL,
  courier_user_id uuid NULL,
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (food_order_id, thread_type)
);

GRANT SELECT, INSERT, UPDATE ON public.food_order_threads TO authenticated;
GRANT ALL ON public.food_order_threads TO service_role;

ALTER TABLE public.food_order_threads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "thread participants can read"
  ON public.food_order_threads FOR SELECT
  TO authenticated
  USING (
    auth.uid() = client_user_id
    OR auth.uid() = restaurant_owner_user_id
    OR auth.uid() = courier_user_id
    OR public.has_role(auth.uid(), 'admin'::app_role)
  );

-- Inserts are gated to the order's client or the restaurant owner.
CREATE POLICY "client or restaurant owner can open thread"
  ON public.food_order_threads FOR INSERT
  TO authenticated
  WITH CHECK (
    (auth.uid() = client_user_id OR auth.uid() = restaurant_owner_user_id)
    AND EXISTS (
      SELECT 1 FROM public.food_orders fo
      JOIN public.food_restaurants fr ON fr.id = fo.restaurant_id
      WHERE fo.id = food_order_id
        AND fo.restaurant_id = restaurant_id
        AND fo.user_id = client_user_id
        AND fr.owner_user_id = restaurant_owner_user_id
    )
  );

-- Restaurant owner can attach a courier_user_id later, or update last_message_at.
CREATE POLICY "participants can update thread bookkeeping"
  ON public.food_order_threads FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = client_user_id
    OR auth.uid() = restaurant_owner_user_id
    OR auth.uid() = courier_user_id
  )
  WITH CHECK (
    auth.uid() = client_user_id
    OR auth.uid() = restaurant_owner_user_id
    OR auth.uid() = courier_user_id
  );

CREATE INDEX IF NOT EXISTS food_order_threads_order_idx ON public.food_order_threads(food_order_id);
CREATE INDEX IF NOT EXISTS food_order_threads_owner_idx ON public.food_order_threads(restaurant_owner_user_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS food_order_threads_client_idx ON public.food_order_threads(client_user_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS food_order_threads_courier_idx ON public.food_order_threads(courier_user_id, last_message_at DESC);

-- MESSAGES
CREATE TABLE IF NOT EXISTS public.food_order_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES public.food_order_threads(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL,
  sender_role public.food_order_sender_role NOT NULL,
  body text NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 2000),
  read_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.food_order_messages TO authenticated;
GRANT ALL ON public.food_order_messages TO service_role;

ALTER TABLE public.food_order_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "thread participants can read messages"
  ON public.food_order_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.food_order_threads t
      WHERE t.id = thread_id
        AND (
          auth.uid() = t.client_user_id
          OR auth.uid() = t.restaurant_owner_user_id
          OR auth.uid() = t.courier_user_id
          OR public.has_role(auth.uid(), 'admin'::app_role)
        )
    )
  );

CREATE POLICY "thread participants can post messages"
  ON public.food_order_messages FOR INSERT
  TO authenticated
  WITH CHECK (
    sender_user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.food_order_threads t
      WHERE t.id = thread_id
        AND (
          auth.uid() = t.client_user_id
          OR auth.uid() = t.restaurant_owner_user_id
          OR auth.uid() = t.courier_user_id
        )
    )
  );

-- Allow marking own messages as read (read_at only). We keep it loose for participants.
CREATE POLICY "participants can mark messages read"
  ON public.food_order_messages FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.food_order_threads t
      WHERE t.id = thread_id
        AND (
          auth.uid() = t.client_user_id
          OR auth.uid() = t.restaurant_owner_user_id
          OR auth.uid() = t.courier_user_id
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.food_order_threads t
      WHERE t.id = thread_id
        AND (
          auth.uid() = t.client_user_id
          OR auth.uid() = t.restaurant_owner_user_id
          OR auth.uid() = t.courier_user_id
        )
    )
  );

CREATE INDEX IF NOT EXISTS food_order_messages_thread_idx ON public.food_order_messages(thread_id, created_at DESC);

-- updated_at trigger for threads
CREATE OR REPLACE FUNCTION public.touch_food_order_thread()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS food_order_threads_touch ON public.food_order_threads;
CREATE TRIGGER food_order_threads_touch
  BEFORE UPDATE ON public.food_order_threads
  FOR EACH ROW EXECUTE FUNCTION public.touch_food_order_thread();

-- Bump thread.last_message_at when a message is inserted.
CREATE OR REPLACE FUNCTION public.bump_food_order_thread_last_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.food_order_threads
     SET last_message_at = now(), updated_at = now()
   WHERE id = NEW.thread_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS food_order_messages_bump ON public.food_order_messages;
CREATE TRIGGER food_order_messages_bump
  AFTER INSERT ON public.food_order_messages
  FOR EACH ROW EXECUTE FUNCTION public.bump_food_order_thread_last_message();

-- Helper RPC: open or fetch a thread for an order, validating that the caller
-- is either the order's client or the restaurant owner. Courier_user_id is
-- attached when a mission with an assigned driver exists for the order.
CREATE OR REPLACE FUNCTION public.open_food_order_thread(
  _food_order_id uuid,
  _thread_type public.food_order_thread_type
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_rest RECORD;
  v_courier uuid;
  v_thread_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;

  SELECT id, user_id, restaurant_id INTO v_order FROM public.food_orders WHERE id = _food_order_id;
  IF v_order.id IS NULL THEN RAISE EXCEPTION 'order not found'; END IF;

  SELECT id, owner_user_id INTO v_rest FROM public.food_restaurants WHERE id = v_order.restaurant_id;
  IF v_rest.id IS NULL THEN RAISE EXCEPTION 'restaurant not found'; END IF;

  IF auth.uid() <> v_order.user_id
     AND auth.uid() <> v_rest.owner_user_id
     AND NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'not a participant';
  END IF;

  -- Best-effort courier resolution from mission link, if any column exists.
  BEGIN
    EXECUTE 'SELECT driver_id FROM public.missions WHERE food_order_id = $1 AND driver_id IS NOT NULL ORDER BY created_at DESC LIMIT 1'
      INTO v_courier USING _food_order_id;
  EXCEPTION WHEN undefined_column THEN
    v_courier := NULL;
  END;

  SELECT id INTO v_thread_id
    FROM public.food_order_threads
   WHERE food_order_id = _food_order_id AND thread_type = _thread_type;

  IF v_thread_id IS NULL THEN
    INSERT INTO public.food_order_threads (
      food_order_id, restaurant_id, thread_type,
      client_user_id, restaurant_owner_user_id, courier_user_id
    ) VALUES (
      _food_order_id, v_order.restaurant_id, _thread_type,
      v_order.user_id, v_rest.owner_user_id, v_courier
    )
    RETURNING id INTO v_thread_id;
  ELSIF v_courier IS NOT NULL THEN
    UPDATE public.food_order_threads
       SET courier_user_id = v_courier
     WHERE id = v_thread_id AND courier_user_id IS DISTINCT FROM v_courier;
  END IF;

  RETURN v_thread_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.open_food_order_thread(uuid, public.food_order_thread_type) TO authenticated;
