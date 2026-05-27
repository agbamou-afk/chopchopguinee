
-- 1) Restrict confirmation_code & sensitive top-up fields via column-level GRANTs
REVOKE SELECT ON public.topup_requests FROM authenticated;
REVOKE SELECT ON public.topup_requests FROM anon;
GRANT SELECT (
  id, reference, client_user_id, agent_user_id, amount_gnf,
  status, expires_at, confirmed_at, cancelled_reason,
  transaction_id, provider, created_at, updated_at
) ON public.topup_requests TO authenticated;
GRANT ALL ON public.topup_requests TO service_role;

-- Safe accessor that returns the secret confirmation code only to the row owner
CREATE OR REPLACE FUNCTION public.get_my_pending_topup()
RETURNS TABLE(
  id uuid,
  reference text,
  amount_gnf bigint,
  confirmation_code text,
  expires_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.id, t.reference, t.amount_gnf, t.confirmation_code, t.expires_at
  FROM public.topup_requests t
  WHERE t.client_user_id = auth.uid()
    AND t.status = 'pending'
    AND t.provider = 'agent'
  ORDER BY t.created_at DESC
  LIMIT 1;
$$;
REVOKE EXECUTE ON FUNCTION public.get_my_pending_topup() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_pending_topup() TO authenticated;

-- 2) Allow users to submit their own driver application (pending only)
CREATE POLICY "Users submit own application"
ON public.driver_applications
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND decision = 'pending'::driver_application_decision
  AND decided_by IS NULL
  AND decided_at IS NULL
);

-- 3) Restrict find_user_by_phone to active agents and admins to stop enumeration
CREATE OR REPLACE FUNCTION public.find_user_by_phone(p_phone text)
RETURNS TABLE(user_id uuid, full_name text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF NOT public.is_any_admin(auth.uid())
     AND NOT EXISTS (
       SELECT 1 FROM public.agent_profiles ap
       WHERE ap.user_id = auth.uid() AND ap.status = 'active'
     ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  RETURN QUERY
    SELECT p.user_id, p.full_name
    FROM public.profiles p
    WHERE p.phone = p_phone
    LIMIT 1;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.find_user_by_phone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO authenticated;
