
-- ============================================================
-- NODE 5 · A13 remediation 1/1 — canonical ownership keys + phone normalization
-- ============================================================

-- D1 (CRITICAL): agent_lookup_customer_wallet resolved a phone to profiles.id
-- (the profile row PK) and returned it as `customer_user_id`. profiles.id is
-- NEVER equal to profiles.user_id in this database, so the agent cash-in flow
-- carried a non-canonical key, and the `self_cashin_forbidden` guard compared a
-- profile id against auth.uid() and could never fire.
CREATE OR REPLACE FUNCTION public.agent_lookup_customer_wallet(p_phone text)
 RETURNS TABLE(customer_user_id uuid, display_name text, masked_phone text, wallet_exists boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid       uuid := auth.uid();
  v_norm      text;
  v_cust      uuid;
  v_full      text;
  v_first     text;
  v_masked    text;
  v_wallet_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501';
  END IF;
  IF NOT public._is_approved_service_agent(v_uid) THEN
    RAISE EXCEPTION 'service_agent_not_approved';
  END IF;

  v_norm := public._normalize_guinea_phone(p_phone);
  IF v_norm IS NULL THEN
    RAISE EXCEPTION 'invalid_phone';
  END IF;

  -- Canonical account key only. Never profiles.id.
  SELECT p.user_id, COALESCE(p.full_name, '')
    INTO v_cust, v_full
  FROM public.profiles p
  WHERE p.phone = v_norm
    AND COALESCE(p.account_status,'active') = 'active'
  LIMIT 1;

  IF v_cust IS NULL THEN
    RAISE EXCEPTION 'customer_not_found';
  END IF;
  IF v_cust = v_uid THEN
    RAISE EXCEPTION 'self_cashin_forbidden';
  END IF;
  IF public.is_user_banned(v_cust) THEN
    RAISE EXCEPTION 'customer_unavailable';
  END IF;

  v_first := split_part(trim(v_full), ' ', 1);
  IF length(coalesce(v_first,'')) = 0 THEN v_first := 'Client CHOP'; END IF;

  v_masked := CASE
    WHEN length(v_norm) >= 6 THEN substr(v_norm,1,5) || ' •• •• ' || right(v_norm, 2)
    ELSE v_norm END;

  SELECT id INTO v_wallet_id FROM public.wallets
   WHERE owner_user_id = v_cust AND party_type='client' LIMIT 1;

  customer_user_id := v_cust;
  display_name     := v_first;
  masked_phone     := v_masked;
  wallet_exists    := v_wallet_id IS NOT NULL;
  RETURN NEXT;
END;
$function$;

REVOKE ALL ON FUNCTION public.agent_lookup_customer_wallet(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_lookup_customer_wallet(text) TO authenticated, service_role;

-- D2: profiles.phone is client-writable (RLS: own row) with a UNIQUE index but
-- NO server-side normalization, so '+224622123456' and '00224622123456' could
-- coexist as two logically identical contact identities on two accounts.
-- Fail-closed canonicalisation. Contact attribute only — confers no authority.
CREATE OR REPLACE FUNCTION public._profiles_normalize_phone()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_norm text;
BEGIN
  IF NEW.phone IS NULL OR btrim(NEW.phone) = '' THEN
    NEW.phone := NULL;
    RETURN NEW;
  END IF;
  v_norm := public._normalize_guinea_phone(NEW.phone);
  IF v_norm IS NULL THEN
    RAISE EXCEPTION 'INVALID_PHONE' USING ERRCODE = '22023';
  END IF;
  NEW.phone := v_norm;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_profiles_normalize_phone ON public.profiles;
CREATE TRIGGER trg_profiles_normalize_phone
  BEFORE INSERT OR UPDATE OF phone ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._profiles_normalize_phone();

-- D3 (hardening): admin/agent contact lookup used raw text equality.
-- Contact lookup only; it already resolves to the canonical user_id.
CREATE OR REPLACE FUNCTION public.find_user_by_phone(p_phone text)
 RETURNS TABLE(user_id uuid, full_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_norm text;
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
  v_norm := COALESCE(public._normalize_guinea_phone(p_phone), p_phone);
  RETURN QUERY
    SELECT p.user_id, p.full_name
    FROM public.profiles p
    WHERE p.phone = v_norm
    LIMIT 1;
END;
$function$;

REVOKE ALL ON FUNCTION public.find_user_by_phone(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.find_user_by_phone(text) TO authenticated, service_role;
