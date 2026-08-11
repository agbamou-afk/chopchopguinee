CREATE OR REPLACE FUNCTION public._qa_s6_setup(p_send uuid, p_drv uuid, p_god uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  VALUES ('00000000-0000-0000-0000-000000000000', p_god, 'authenticated','authenticated',
          'qa-s6-god-'||substr(p_god::text,1,8)||'@qa.invalid','x', now(), now(),
          '{"provider":"email"}'::jsonb, '{}'::jsonb);
  INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (p_god,'god_admin','active');
  INSERT INTO public.user_roles(user_id, role) VALUES (p_god,'god_admin') ON CONFLICT DO NOTHING;
  INSERT INTO public.driver_profiles(user_id, status, vehicle_type, capabilities)
  VALUES (p_drv,'approved','moto',ARRAY['package_delivery']);
  INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf)
  VALUES (p_drv,'driver',5000000),(p_send,'client',5000000);
  UPDATE public.feature_flags SET enabled = true
   WHERE key IN ('envoyer_enabled','envoyer_declared_value_enabled',
                 'chop_pay_checkout_enabled','envoyer_claims_enabled');
END; $$;
REVOKE ALL ON FUNCTION public._qa_s6_setup(uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s6_results(part, report) SELECT 1, public._qa_s6_run1();
INSERT INTO public._qa_s6_results(part, report) SELECT 2, public._qa_s6_run2();