-- Welcome email: server-side dispatch, exactly-once.
-- The Repas settlement preview fix (COALESCE(fr.merchant_store_id,
-- li.related_store_id)) is already live and is intentionally untouched here.

-- 1. Dispatch ledger. The unique key IS the idempotency guarantee: the row is
--    claimed before the HTTP call, so concurrent attempts can never both send.
CREATE TABLE IF NOT EXISTS public.welcome_email_dispatches (
  user_id           uuid PRIMARY KEY,
  recipient_email   text NOT NULL,
  template_version  text NOT NULL DEFAULT 'v1',
  message_key       text NOT NULL UNIQUE,
  http_request_id   bigint,
  error_message     text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.welcome_email_dispatches TO authenticated;
GRANT ALL    ON public.welcome_email_dispatches TO service_role;

ALTER TABLE public.welcome_email_dispatches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read welcome dispatches" ON public.welcome_email_dispatches;
CREATE POLICY "Admins read welcome dispatches"
  ON public.welcome_email_dispatches
  FOR SELECT
  TO authenticated
  USING (public.is_any_admin(auth.uid()));

-- 2. Dispatcher. Runs after the profile row exists so the mail can safely
--    reference the account. Never raises: a mail failure must never roll back
--    or block account creation.
CREATE OR REPLACE FUNCTION public._dispatch_welcome_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_key        text;
  v_service    text;
  v_url        text := 'https://azbhteplbdwuqdlzadjx.supabase.co/functions/v1/send-transactional-email';
  v_first      text;
  v_request_id bigint;
  v_claimed    boolean := false;
BEGIN
  IF NEW.email IS NULL OR btrim(NEW.email) = '' THEN
    RETURN NEW;
  END IF;
  IF NEW.deleted_at IS NOT NULL OR NEW.account_status <> 'active' THEN
    RETURN NEW;
  END IF;

  v_key := 'welcome-v1-' || NEW.user_id::text;

  INSERT INTO public.welcome_email_dispatches (user_id, recipient_email, template_version, message_key)
  VALUES (NEW.user_id, btrim(NEW.email), 'v1', v_key)
  ON CONFLICT (user_id) DO NOTHING;

  GET DIAGNOSTICS v_claimed = ROW_COUNT;
  IF NOT v_claimed THEN
    RETURN NEW; -- already dispatched for this account
  END IF;

  BEGIN
    SELECT decrypted_secret INTO v_service
    FROM vault.decrypted_secrets
    WHERE name = 'email_queue_service_role_key'
    LIMIT 1;

    IF v_service IS NULL THEN
      UPDATE public.welcome_email_dispatches
      SET error_message = 'missing_service_role_secret'
      WHERE user_id = NEW.user_id;
      RETURN NEW;
    END IF;

    v_first := NULLIF(btrim(COALESCE(NEW.first_name, '')), '');

    SELECT net.http_post(
      url     := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_service
      ),
      body    := jsonb_build_object(
        'templateName',   'welcome',
        'recipientEmail', btrim(NEW.email),
        'idempotencyKey', v_key,
        'templateData',   CASE WHEN v_first IS NULL
                               THEN '{}'::jsonb
                               ELSE jsonb_build_object('firstName', v_first) END
      )
    ) INTO v_request_id;

    UPDATE public.welcome_email_dispatches
    SET http_request_id = v_request_id
    WHERE user_id = NEW.user_id;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      UPDATE public.welcome_email_dispatches
      SET error_message = left(SQLERRM, 500)
      WHERE user_id = NEW.user_id;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public._dispatch_welcome_email() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_profiles_welcome_email ON public.profiles;
CREATE TRIGGER trg_profiles_welcome_email
AFTER INSERT ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public._dispatch_welcome_email();

-- 3. Backfill guard: existing accounts must never receive a retroactive blast.
INSERT INTO public.welcome_email_dispatches (user_id, recipient_email, template_version, message_key, error_message)
SELECT p.user_id,
       COALESCE(NULLIF(btrim(p.email), ''), 'unknown'),
       'v1',
       'welcome-v1-' || p.user_id::text,
       'pre-existing account: suppressed, never dispatched'
FROM public.profiles p
ON CONFLICT (user_id) DO NOTHING;