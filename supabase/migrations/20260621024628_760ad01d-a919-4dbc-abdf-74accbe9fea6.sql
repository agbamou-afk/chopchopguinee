
ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS changed_password_at timestamptz;

CREATE OR REPLACE FUNCTION public.admin_clear_must_change_password()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role public.admin_role;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT admin_role INTO v_role
  FROM public.admin_users
  WHERE user_id = v_uid AND status = 'active'
  LIMIT 1;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'not a staff account' USING ERRCODE = '42501';
  END IF;

  UPDATE public.admin_users
  SET must_change_password = false,
      changed_password_at = now(),
      updated_at = now()
  WHERE user_id = v_uid;

  INSERT INTO public.audit_logs(actor_user_id, actor_role, module, action, target_type, target_id, after)
  VALUES (v_uid, v_role, 'staff', 'staff.password_changed', 'user', v_uid::text,
          jsonb_build_object('changed_at', now()));

  RETURN jsonb_build_object('ok', true);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_clear_must_change_password() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_clear_must_change_password() TO authenticated;
