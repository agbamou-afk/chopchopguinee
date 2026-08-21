
CREATE OR REPLACE FUNCTION public._qa_node5_fr_fixtures(
  p_ids uuid[], p_d uuid, p_m uuid, p_x uuid, p_fin uuid, p_liv uuid,
  p_god uuid, p_store uuid, p_ride uuid, p_phone text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $function$
BEGIN
  PERFORM public._qa_node5_fr_seed(p_ids);
  PERFORM public._qa_node5_fr_profiles(p_ids);
  UPDATE public.profiles SET phone = p_phone WHERE user_id = p_d;

  -- lanes first: driver rows are gated on an active professional identity
  INSERT INTO public.professional_identities(user_id,professional_type,claim_state,claimed_at)
  VALUES (p_d,'driver','active',now()), (p_x,'driver','active',now()),
         (p_m,'merchant','active',now()), (p_fin,'driver','active',now());

  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence)
  VALUES (p_d,'approved','moto','on_trip'), (p_x,'approved','moto','online'),
         (p_fin,'approved','moto','online');

  INSERT INTO public.merchant_stores(id,owner_user_id,name,status,is_active)
  VALUES (p_store,p_m,'QA N5FR Store','active',true);

  INSERT INTO public.user_roles(user_id,role) VALUES
    (p_d,'driver'),(p_d,'user'),(p_m,'merchant'),(p_x,'driver'),
    (p_fin,'driver'),(p_liv,'user');

  INSERT INTO public.admin_users(user_id,admin_role,status)
  VALUES (p_x,'support_admin','active'), (p_god,'god_admin','active');

  INSERT INTO public.account_recovery_profiles(user_id,recovery_key_hash)
  VALUES (p_d,'h'), (p_m,'h');

  PERFORM public._qa_s13_wallet(p_d,'driver',0,0);
  PERFORM public._qa_s13_wallet(p_fin,'driver',29448,0);
  PERFORM public._qa_s13_wallet(p_liv,'client',5000,0);

  INSERT INTO public.rides(id,client_id,mode,pickup_lat,pickup_lng,dest_lat,dest_lng,
                           fare_gnf,status)
  VALUES (p_ride,p_liv,'moto',9.5,-13.7,9.6,-13.6,10000,'cancelled');
  INSERT INTO public.ride_offers(ride_id,driver_id,status,estimated_fare_gnf,
                                 estimated_earning_gnf,expires_at)
  VALUES (p_ride,p_d,'pending',10000,8000, now() - interval '5 days');

  UPDATE public.profiles SET account_status='deleted', deleted_at=now(),
         full_name='Utilisateur supprimé', phone=NULL, email=NULL
   WHERE user_id IN (p_d,p_m,p_x,p_fin);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_fr_fixtures(uuid[],uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_fr_fixtures(uuid[],uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,text)
  TO service_role;

CREATE OR REPLACE FUNCTION public._qa_node5_fr_cleanup(p_ids uuid[], p_ride uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $function$
BEGIN
  DELETE FROM public.account_access_terminations WHERE user_id = ANY(p_ids);
  DELETE FROM public.audit_logs WHERE target_id = ANY(SELECT x::text FROM unnest(p_ids) x);
  DELETE FROM public.audit_logs WHERE actor_id = ANY(p_ids);
  DELETE FROM public.ride_offers WHERE driver_id = ANY(p_ids);
  DELETE FROM public.rides WHERE id = p_ride;
  DELETE FROM public.account_recovery_profiles WHERE user_id = ANY(p_ids);
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(p_ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(p_ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(p_ids);
  DELETE FROM public.wallet_transactions WHERE wallet_id IN
    (SELECT id FROM public.wallets WHERE owner_user_id = ANY(p_ids));
  DELETE FROM public.wallets WHERE owner_user_id = ANY(p_ids);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(p_ids);
  PERFORM public._qa_users_purge(p_ids);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_fr_cleanup(uuid[],uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_fr_cleanup(uuid[],uuid) TO service_role;
