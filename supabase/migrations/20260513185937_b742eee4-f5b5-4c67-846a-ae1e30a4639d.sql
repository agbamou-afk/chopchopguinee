
-- 1) app_settings: clé/valeur pour configuration plateforme (Orange Money merchant, etc.)
CREATE TABLE IF NOT EXISTS public.app_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL DEFAULT '{}'::jsonb,
  description text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone read app_settings"
ON public.app_settings FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "Finance/god admins write app_settings"
ON public.app_settings FOR ALL TO authenticated
USING (public.has_app_role(auth.uid(), 'god_admin') OR public.has_app_role(auth.uid(), 'finance_admin'))
WITH CHECK (public.has_app_role(auth.uid(), 'god_admin') OR public.has_app_role(auth.uid(), 'finance_admin'));

-- Seed default Orange Money config (empty until admin sets it)
INSERT INTO public.app_settings (key, value, description)
VALUES (
  'orange_money',
  jsonb_build_object(
    'merchant_msisdn', '',
    'merchant_name', 'CHOP CHOP',
    'mode', 'manual_csv',
    'webhook_configured', false,
    'last_import_at', null,
    'status', 'missing'
  ),
  'Configuration du compte marchand Orange Money'
) ON CONFLICT (key) DO NOTHING;

-- 2) Fraud-aware deterministic auto-match
CREATE OR REPLACE FUNCTION public.om_auto_match(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_event public.payment_provider_events;
  v_topup public.topup_requests;
  v_match_count int;
  v_recent_count int;
  v_high_value bigint := 5000000;
BEGIN
  SELECT * INTO v_event FROM public.payment_provider_events WHERE id = p_event_id FOR UPDATE;
  IF v_event.id IS NULL THEN
    RETURN jsonb_build_object('status', 'not_found');
  END IF;

  -- Already processed?
  IF v_event.processing_status IN ('credited','rejected') THEN
    RETURN jsonb_build_object('status', v_event.processing_status, 'event_id', v_event.id);
  END IF;

  -- Provider must report success
  IF v_event.status <> 'successful' THEN
    UPDATE public.payment_provider_events
       SET processing_status = 'rejected', notes = coalesce(notes,'') || ' | provider status not successful'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status', 'rejected', 'reason', 'provider_status');
  END IF;

  -- Try to find a unique deterministic match: same amount, pending, not expired,
  -- AND (phone match OR reference present in payer memo / raw payload)
  WITH candidates AS (
    SELECT t.*
    FROM public.topup_requests t
    LEFT JOIN public.profiles p ON p.user_id = t.client_user_id
    WHERE t.provider = 'orange_money'
      AND t.status::text IN ('pending','matched','needs_review')
      AND t.amount_gnf = v_event.amount_gnf
      AND t.expires_at > now()
      AND (
        (v_event.payer_phone IS NOT NULL AND (
            regexp_replace(p.phone, '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
            OR regexp_replace(t.user_phone, '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
          ))
        OR (v_event.raw_payload::text ILIKE '%' || t.reference || '%')
      )
  )
  SELECT count(*) INTO v_match_count FROM candidates;

  IF v_match_count = 0 THEN
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review', notes = coalesce(notes,'') || ' | no candidate'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status', 'needs_review', 'reason', 'no_match');
  END IF;

  IF v_match_count > 1 THEN
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review', notes = coalesce(notes,'') || ' | ambiguous'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status', 'needs_review', 'reason', 'ambiguous', 'matches', v_match_count);
  END IF;

  -- Exactly one candidate
  SELECT t.* INTO v_topup
  FROM public.topup_requests t
  LEFT JOIN public.profiles p ON p.user_id = t.client_user_id
  WHERE t.provider = 'orange_money'
    AND t.status::text IN ('pending','matched','needs_review')
    AND t.amount_gnf = v_event.amount_gnf
    AND t.expires_at > now()
    AND (
      (v_event.payer_phone IS NOT NULL AND (
          regexp_replace(p.phone, '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
          OR regexp_replace(t.user_phone, '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
        ))
      OR (v_event.raw_payload::text ILIKE '%' || t.reference || '%')
    )
  LIMIT 1;

  -- Fraud guards: high value forces review
  IF v_event.amount_gnf > v_high_value THEN
    UPDATE public.topup_requests SET status = 'needs_review'::topup_status WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           matched_user_id = v_topup.client_user_id,
           matched_topup_request_id = v_topup.id,
           match_confidence = 0.95,
           notes = coalesce(notes,'') || ' | high_value'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status', 'needs_review', 'reason', 'high_value', 'topup_request_id', v_topup.id);
  END IF;

  -- Fraud guard: rate limit - more than 5 credited topups in 24h for this user
  SELECT count(*) INTO v_recent_count
  FROM public.topup_requests
  WHERE client_user_id = v_topup.client_user_id
    AND status::text = 'credited'
    AND confirmed_at > now() - interval '24 hours';
  IF v_recent_count >= 5 THEN
    UPDATE public.topup_requests SET status = 'needs_review'::topup_status WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status = 'needs_review',
           matched_user_id = v_topup.client_user_id,
           matched_topup_request_id = v_topup.id,
           match_confidence = 0.9,
           notes = coalesce(notes,'') || ' | rate_limit'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status', 'needs_review', 'reason', 'rate_limit', 'topup_request_id', v_topup.id);
  END IF;

  -- Auto-credit
  PERFORM public.wallet_topup_om_credit(v_event.id, v_topup.id);
  RETURN jsonb_build_object('status', 'credited', 'topup_request_id', v_topup.id);
END;
$$;

-- 3) Helper: list pending OM topups for an admin reconciliation candidate dropdown
CREATE OR REPLACE FUNCTION public.om_pending_topups_for_event(p_event_id uuid)
RETURNS TABLE (
  topup_id uuid,
  reference text,
  client_user_id uuid,
  client_phone text,
  client_name text,
  amount_gnf bigint,
  created_at timestamptz,
  expires_at timestamptz,
  status text,
  amount_match boolean,
  phone_match boolean
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    t.id,
    t.reference,
    t.client_user_id,
    p.phone,
    p.full_name,
    t.amount_gnf,
    t.created_at,
    t.expires_at,
    t.status::text,
    (t.amount_gnf = e.amount_gnf) AS amount_match,
    (regexp_replace(coalesce(p.phone, t.user_phone, ''), '\D', '', 'g')
       = regexp_replace(coalesce(e.payer_phone, ''), '\D', '', 'g')) AS phone_match
  FROM public.payment_provider_events e
  CROSS JOIN public.topup_requests t
  LEFT JOIN public.profiles p ON p.user_id = t.client_user_id
  WHERE e.id = p_event_id
    AND t.provider = 'orange_money'
    AND t.status::text IN ('pending','matched','needs_review')
  ORDER BY (t.amount_gnf = e.amount_gnf) DESC,
           (regexp_replace(coalesce(p.phone, t.user_phone, ''), '\D', '', 'g')
              = regexp_replace(coalesce(e.payer_phone, ''), '\D', '', 'g')) DESC,
           t.created_at DESC
  LIMIT 20;
$$;
