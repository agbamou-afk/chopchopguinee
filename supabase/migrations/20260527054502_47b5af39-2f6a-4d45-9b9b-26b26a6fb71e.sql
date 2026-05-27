
-- 1. app_settings: remove public/anon read, restrict to authenticated
DROP POLICY IF EXISTS "Anyone read app_settings" ON public.app_settings;
CREATE POLICY "Authenticated read app_settings"
  ON public.app_settings
  FOR SELECT
  TO authenticated
  USING (true);
REVOKE SELECT ON public.app_settings FROM anon;

-- 2. Function search_path: fix the four queue helpers that had NULL search_path
ALTER FUNCTION public.enqueue_email(text, jsonb) SET search_path = public, pgmq, extensions;
ALTER FUNCTION public.delete_email(text, bigint) SET search_path = public, pgmq, extensions;
ALTER FUNCTION public.read_email_batch(text, integer, integer) SET search_path = public, pgmq, extensions;
ALTER FUNCTION public.move_to_dlq(text, text, bigint, jsonb) SET search_path = public, pgmq, extensions;

-- 3. Revoke EXECUTE from anon on privileged / non-public SECURITY DEFINER functions
REVOKE EXECUTE ON FUNCTION public.cancel_payment_intent(uuid, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.confirm_payment_intent(uuid, text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fail_payment_intent(uuid, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.demo_link_ride(uuid) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.demo_reset_driver() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.demo_seed_ride_offer() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.debug_create_offer_for_current_driver() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_demo_driver() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.gen_topup_reference() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.log_admin_action(text, text, text, text, jsonb, jsonb, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.analytics_summary(integer) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.claim_first_admin() FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enqueue_email(text, jsonb) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.delete_email(text, bigint) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.read_email_batch(text, integer, integer) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.move_to_dlq(text, text, bigint, jsonb) FROM anon, PUBLIC;
