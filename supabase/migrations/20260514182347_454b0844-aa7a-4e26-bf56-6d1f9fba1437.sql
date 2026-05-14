REVOKE EXECUTE ON FUNCTION public.demo_reset_driver() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.demo_seed_ride_offer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.demo_reset_driver() TO authenticated;
GRANT EXECUTE ON FUNCTION public.demo_seed_ride_offer() TO authenticated;