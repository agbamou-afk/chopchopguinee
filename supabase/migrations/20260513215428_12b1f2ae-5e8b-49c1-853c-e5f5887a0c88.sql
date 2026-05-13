
-- Seed demo client and demo driver accounts (idempotent)
DO $$
DECLARE
  v_client_id uuid;
  v_driver_id uuid;
  v_client_email text := 'demo.client@chopchop.gn';
  v_driver_email text := 'demo.driver@chopchop.gn';
  v_password text := 'demo1234';
BEGIN
  -- CLIENT
  SELECT id INTO v_client_id FROM auth.users WHERE email = v_client_email;
  IF v_client_id IS NULL THEN
    v_client_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change,
      email_change_token_new, recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_client_id, 'authenticated', 'authenticated',
      v_client_email, crypt(v_password, gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('first_name','Demo','last_name','Client','full_name','Demo Client'),
      now(), now(), '', '', '', ''
    );
    INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
    VALUES (gen_random_uuid(), v_client_id,
            jsonb_build_object('sub', v_client_id::text, 'email', v_client_email),
            'email', v_client_id::text, now(), now(), now());
  END IF;

  INSERT INTO public.profiles (user_id, first_name, last_name, full_name, display_name, phone, email, account_status)
  VALUES (v_client_id, 'Demo', 'Client', 'Demo Client', 'Demo Client', '+224620000001', v_client_email, 'active')
  ON CONFLICT (user_id) DO UPDATE SET
    first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name,
    full_name = EXCLUDED.full_name, display_name = EXCLUDED.display_name,
    phone = COALESCE(public.profiles.phone, EXCLUDED.phone),
    email = EXCLUDED.email;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_client_id, 'client'::app_role)
  ON CONFLICT (user_id, role) DO NOTHING;

  -- DRIVER
  SELECT id INTO v_driver_id FROM auth.users WHERE email = v_driver_email;
  IF v_driver_id IS NULL THEN
    v_driver_id := gen_random_uuid();
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, email_change,
      email_change_token_new, recovery_token
    ) VALUES (
      '00000000-0000-0000-0000-000000000000', v_driver_id, 'authenticated', 'authenticated',
      v_driver_email, crypt(v_password, gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('first_name','Demo','last_name','Driver','full_name','Demo Driver'),
      now(), now(), '', '', '', ''
    );
    INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
    VALUES (gen_random_uuid(), v_driver_id,
            jsonb_build_object('sub', v_driver_id::text, 'email', v_driver_email),
            'email', v_driver_id::text, now(), now(), now());
  END IF;

  INSERT INTO public.profiles (user_id, first_name, last_name, full_name, display_name, phone, email, account_status)
  VALUES (v_driver_id, 'Demo', 'Driver', 'Demo Driver', 'Demo Driver', '+224620000002', v_driver_email, 'active')
  ON CONFLICT (user_id) DO UPDATE SET
    first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name,
    full_name = EXCLUDED.full_name, display_name = EXCLUDED.display_name,
    phone = COALESCE(public.profiles.phone, EXCLUDED.phone),
    email = EXCLUDED.email;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (v_driver_id, 'driver'::app_role)
  ON CONFLICT (user_id, role) DO NOTHING;

  INSERT INTO public.driver_profiles (
    user_id, status, presence, vehicle_type, plate_number, zones, rating, accept_rate, approved_at
  ) VALUES (
    v_driver_id, 'approved'::driver_status, 'offline'::driver_presence,
    'moto'::driver_vehicle_type, 'DEMO-001', ARRAY['conakry'], 4.9, 0.95, now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    status = 'approved'::driver_status,
    approved_at = COALESCE(public.driver_profiles.approved_at, now());
END $$;
