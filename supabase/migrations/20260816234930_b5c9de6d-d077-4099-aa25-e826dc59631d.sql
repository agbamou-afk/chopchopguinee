DROP FUNCTION IF EXISTS public._qa_node3_repas_r7_semantics();
DROP FUNCTION IF EXISTS public._qa_node3_repas_r7_readtruth();
DROP FUNCTION IF EXISTS public._qa_node3_repas_r7_ext();
DROP FUNCTION IF EXISTS public._qa_node3_repas_r7_fixture_phone_backfill();
ALTER FUNCTION public._qa_node3_repas_r7_semantics_fxcore() RENAME TO _qa_node3_repas_r7_semantics;
ALTER FUNCTION public._qa_node3_repas_r7_readtruth_fxcore() RENAME TO _qa_node3_repas_r7_readtruth;
ALTER FUNCTION public._qa_node3_repas_r7_ext_fxcore() RENAME TO _qa_node3_repas_r7_ext;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_semantics() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_ext() FROM PUBLIC, anon, authenticated;

ALTER TABLE public.repas_custody_events DISABLE TRIGGER USER;
ALTER TABLE public.repas_custody_credentials DISABLE TRIGGER USER;
ALTER TABLE public.mission_events DISABLE TRIGGER USER;
ALTER TABLE public.chop_pay_order_runtime DISABLE TRIGGER USER;
ALTER TABLE public.cash_order_runtime DISABLE TRIGGER USER;
ALTER TABLE public.food_orders DISABLE TRIGGER USER;
ALTER TABLE public.missions DISABLE TRIGGER USER;
ALTER TABLE public.repas_ops_events DISABLE TRIGGER USER;
ALTER TABLE public.merchant_payables DISABLE TRIGGER USER;
ALTER TABLE public.wallet_transactions DISABLE TRIGGER USER;

DO $do$
DECLARE v_orders uuid[]; v_missions uuid[]; v_users uuid[];
BEGIN
  SELECT coalesce(array_agg(f.id), '{}') INTO v_orders
    FROM public.food_orders f JOIN public.food_restaurants fr ON fr.id = f.restaurant_id
   WHERE fr.slug LIKE 'qa-n3r7-%';
  SELECT coalesce(array_agg(id), '{}') INTO v_missions
    FROM public.missions WHERE dropoff_address LIKE 'QA R7 %' OR ref_food_order_id = ANY(v_orders);
  SELECT coalesce(array_agg(id), '{}') INTO v_users FROM auth.users WHERE email LIKE 'qa-s13-n3r7%';

  DELETE FROM public.repas_custody_events WHERE order_id = ANY(v_orders);
  DELETE FROM public.repas_custody_credentials WHERE order_id = ANY(v_orders);
  DELETE FROM public.repas_ops_events WHERE food_order_id = ANY(v_orders);
  DELETE FROM public.repas_ops_cases WHERE food_order_id = ANY(v_orders);
  DELETE FROM public.food_order_messages WHERE thread_id IN (SELECT id FROM public.food_order_threads WHERE food_order_id = ANY(v_orders));
  DELETE FROM public.food_order_threads WHERE food_order_id = ANY(v_orders);
  DELETE FROM public.food_order_items WHERE order_id = ANY(v_orders);
  DELETE FROM public.mission_events WHERE mission_id = ANY(v_missions);
  DELETE FROM public.mission_financial_holds WHERE source_module = 'repas' AND source_id = ANY(v_orders);
  DELETE FROM public.chop_pay_order_runtime WHERE source_module = 'repas' AND source_id = ANY(v_orders);
  DELETE FROM public.cash_order_runtime WHERE source_module = 'repas' AND source_id = ANY(v_orders);
  DELETE FROM public.customer_cancellation_debts WHERE source_module = 'repas' AND source_id = ANY(v_orders);
  DELETE FROM public.food_orders WHERE id = ANY(v_orders);
  DELETE FROM public.missions WHERE id = ANY(v_missions);
  DELETE FROM public.food_menu_items WHERE name LIKE 'QA R7 %';
  DELETE FROM public.repas_pricing_promotions WHERE name LIKE 'QA R7 %';
  DELETE FROM public.food_restaurants WHERE slug LIKE 'qa-n3r7-%';
  DELETE FROM public.merchant_payables WHERE merchant_store_id IN (SELECT id FROM public.merchant_stores WHERE slug LIKE 'qa-n3r7-%');
  DELETE FROM public.merchant_stores WHERE slug LIKE 'qa-n3r7-%';
  -- storage objects are removed separately through the Storage API

  DELETE FROM public.wallet_transactions
   WHERE to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(v_users))
      OR from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(v_users));
  DELETE FROM public.wallets WHERE owner_user_id = ANY(v_users);
  DELETE FROM public.user_roles WHERE user_id = ANY(v_users);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(v_users);
  DELETE FROM public.profiles WHERE id = ANY(v_users);
  DELETE FROM auth.users WHERE id = ANY(v_users);
END $do$;

ALTER TABLE public.repas_custody_events ENABLE TRIGGER USER;
ALTER TABLE public.repas_custody_credentials ENABLE TRIGGER USER;
ALTER TABLE public.mission_events ENABLE TRIGGER USER;
ALTER TABLE public.chop_pay_order_runtime ENABLE TRIGGER USER;
ALTER TABLE public.cash_order_runtime ENABLE TRIGGER USER;
ALTER TABLE public.food_orders ENABLE TRIGGER USER;
ALTER TABLE public.missions ENABLE TRIGGER USER;
ALTER TABLE public.repas_ops_events ENABLE TRIGGER USER;
ALTER TABLE public.merchant_payables ENABLE TRIGGER USER;
ALTER TABLE public.wallet_transactions ENABLE TRIGGER USER;

SELECT jsonb_build_object(
  'restaurants', (SELECT count(*) FROM public.food_restaurants WHERE slug LIKE 'qa-n3r7-%'),
  'stores', (SELECT count(*) FROM public.merchant_stores WHERE slug LIKE 'qa-n3r7-%'),
  'menu', (SELECT count(*) FROM public.food_menu_items WHERE name LIKE 'QA R7 %'),
  'users', (SELECT count(*) FROM auth.users WHERE email LIKE 'qa-s13-n3r7%'),
  'missions', (SELECT count(*) FROM public.missions WHERE dropoff_address LIKE 'QA R7 %'),
  'promos', (SELECT count(*) FROM public.repas_pricing_promotions WHERE name LIKE 'QA R7 %'),
  'disabled_triggers_left', (SELECT count(*) FROM pg_trigger WHERE tgenabled = 'D' AND NOT tgisinternal)
) AS residue_after;