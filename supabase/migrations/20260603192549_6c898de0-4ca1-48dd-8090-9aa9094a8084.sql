ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS deleted_at timestamptz;

CREATE TABLE IF NOT EXISTS public.account_deletion_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  requested_by uuid,
  request_type text NOT NULL CHECK (request_type IN ('self_delete','admin_test_delete','admin_anonymize')),
  status text NOT NULL DEFAULT 'processed' CHECK (status IN ('pending','processed','refused','failed')),
  reason text,
  processed_at timestamptz DEFAULT now(),
  processed_by uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.account_deletion_requests TO authenticated;
GRANT ALL ON public.account_deletion_requests TO service_role;

ALTER TABLE public.account_deletion_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users view own deletion requests"
  ON public.account_deletion_requests FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Admins view all deletion requests"
  ON public.account_deletion_requests FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()));

CREATE OR REPLACE FUNCTION public.user_has_financial_history(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    EXISTS (SELECT 1 FROM public.wallet_transactions WHERE related_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.topup_requests WHERE client_user_id = _user_id OR agent_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.payment_intents WHERE user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.rides WHERE client_id = _user_id OR driver_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.food_orders WHERE user_id = _user_id);
$$;

GRANT EXECUTE ON FUNCTION public.user_has_financial_history(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._anonymize_user_core(_target uuid, _suspended_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.profiles
     SET account_status='deleted', deleted_at=now(),
         full_name='Utilisateur supprimé', display_name='Utilisateur supprimé',
         first_name=NULL, last_name=NULL, phone=NULL, email=NULL, avatar_url=NULL,
         updated_at=now()
   WHERE user_id=_target;

  UPDATE public.driver_profiles
     SET presence='offline', status='suspended',
         suspended_reason=COALESCE(suspended_reason,_suspended_reason),
         updated_at=now()
   WHERE user_id=_target;

  BEGIN UPDATE public.merchants SET status='inactive', updated_at=now() WHERE owner_user_id=_target;
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  BEGIN UPDATE public.service_profiles SET status='archived', visibility='private', updated_at=now() WHERE user_id=_target;
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  BEGIN UPDATE public.marketplace_listings SET status='archived', updated_at=now() WHERE seller_id=_target;
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_account_deletion(_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid();
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  PERFORM public._anonymize_user_core(_uid, 'account_deleted_by_user');
  INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type, status, reason, processed_by)
  VALUES (_uid,_uid,'self_delete','processed',_reason,_uid);
  RETURN jsonb_build_object('ok', true, 'mode', 'anonymized');
END;
$$;

REVOKE ALL ON FUNCTION public.request_account_deletion(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_anonymize_user(_target uuid, _reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _caller uuid := auth.uid();
BEGIN
  IF _caller IS NOT NULL
     AND NOT (public.has_admin_role(_caller,'god_admin'::admin_role)
              OR public.has_admin_role(_caller,'super_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  PERFORM public._anonymize_user_core(_target, 'admin_anonymized');
  INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type, status, reason, processed_by)
  VALUES (_target,_caller,'admin_anonymize','processed',_reason,_caller);
  RETURN jsonb_build_object('ok', true, 'mode', 'anonymized');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_anonymize_user(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_anonymize_user(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_log_test_delete(_target uuid, _caller uuid, _reason text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type, status, reason, processed_by)
  VALUES (_target,_caller,'admin_test_delete','processed',_reason,_caller);
$$;

REVOKE ALL ON FUNCTION public.admin_log_test_delete(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_log_test_delete(uuid, uuid, text) TO service_role;