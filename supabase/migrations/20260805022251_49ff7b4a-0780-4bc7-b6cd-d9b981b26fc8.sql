REVOKE ALL ON FUNCTION public._package_notify(uuid, text, jsonb, public.notification_priority) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._package_notify(uuid, text, jsonb, public.notification_priority) TO service_role;

REVOKE ALL ON FUNCTION public.admin_set_driver_capability(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_driver_capability(uuid, text, boolean) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.package_delivery_cancel_preview(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_delivery_cancel_preview(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.package_verify_pickup(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_verify_pickup(uuid, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.package_verify_delivery(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_verify_delivery(uuid, text, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.package_delivery_finalize_from_intent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.package_delivery_finalize_from_intent(uuid) TO service_role;