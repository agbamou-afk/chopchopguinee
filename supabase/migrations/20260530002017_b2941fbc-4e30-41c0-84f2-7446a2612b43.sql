
-- 1) Schema additions
ALTER TABLE public.topup_requests
  ADD COLUMN IF NOT EXISTS customer_om_code_normalized text,
  ADD COLUMN IF NOT EXISTS customer_om_code_raw text,
  ADD COLUMN IF NOT EXISTS customer_om_code_submitted_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_topup_requests_om_code
  ON public.topup_requests (customer_om_code_normalized)
  WHERE customer_om_code_normalized IS NOT NULL;

ALTER TABLE public.payment_provider_events
  ADD COLUMN IF NOT EXISTS om_code_normalized text,
  ADD COLUMN IF NOT EXISTS receiving_account_id uuid
    REFERENCES public.payment_receiving_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ppe_om_code
  ON public.payment_provider_events (om_code_normalized)
  WHERE om_code_normalized IS NOT NULL;

-- 2) Normalizer (immutable)
CREATE OR REPLACE FUNCTION public.normalize_om_code(p_code text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_code IS NULL THEN NULL
    ELSE upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'))
  END;
$$;

-- 3) Backfill + trigger to keep om_code_normalized in sync with provider_transaction_id
UPDATE public.payment_provider_events
   SET om_code_normalized = public.normalize_om_code(provider_transaction_id)
 WHERE om_code_normalized IS NULL AND provider_transaction_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.ppe_set_om_code_normalized()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.om_code_normalized IS NULL THEN
    NEW.om_code_normalized := public.normalize_om_code(NEW.provider_transaction_id);
  END IF;
  -- If raw_payload carries a receiving_account_id, lift it onto the column
  IF NEW.receiving_account_id IS NULL
     AND NEW.raw_payload ? 'receiving_account_id'
     AND (NEW.raw_payload->>'receiving_account_id') ~ '^[0-9a-fA-F-]{36}$' THEN
    NEW.receiving_account_id := (NEW.raw_payload->>'receiving_account_id')::uuid;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ppe_om_code ON public.payment_provider_events;
CREATE TRIGGER trg_ppe_om_code
BEFORE INSERT OR UPDATE ON public.payment_provider_events
FOR EACH ROW EXECUTE FUNCTION public.ppe_set_om_code_normalized();

-- 4) Replace om_auto_match: code-first matching, then phone/ref fallback
CREATE OR REPLACE FUNCTION public.om_auto_match(p_event_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event public.payment_provider_events;
  v_topup public.topup_requests;
  v_match_count int;
  v_high_value bigint := 5000000;
  v_recent_count int;
BEGIN
  SELECT * INTO v_event FROM public.payment_provider_events WHERE id = p_event_id FOR UPDATE;
  IF v_event.id IS NULL THEN RETURN jsonb_build_object('status','not_found'); END IF;
  IF v_event.processing_status IN ('credited','rejected') THEN
    RETURN jsonb_build_object('status', v_event.processing_status, 'event_id', v_event.id);
  END IF;
  IF v_event.status <> 'successful' THEN
    UPDATE public.payment_provider_events
       SET processing_status='rejected',
           notes = coalesce(notes,'') || ' | provider status not successful'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','rejected','reason','provider_status');
  END IF;

  -- ===== Code-based matching (preferred) =====
  IF v_event.om_code_normalized IS NOT NULL THEN
    SELECT count(*) INTO v_match_count
      FROM public.topup_requests t
     WHERE t.provider = 'orange_money'
       AND t.status::text IN ('pending','matched','needs_review')
       AND t.customer_om_code_normalized = v_event.om_code_normalized
       AND t.expires_at > now();

    IF v_match_count = 1 THEN
      SELECT * INTO v_topup FROM public.topup_requests t
       WHERE t.provider='orange_money'
         AND t.status::text IN ('pending','matched','needs_review')
         AND t.customer_om_code_normalized = v_event.om_code_normalized
         AND t.expires_at > now()
       LIMIT 1
       FOR UPDATE;

      -- Amount must match exactly
      IF v_topup.amount_gnf <> v_event.amount_gnf THEN
        UPDATE public.topup_requests SET status='needs_review'::topup_status,
               notes = coalesce(notes,'') || ' | amount_conflict_code'
         WHERE id = v_topup.id;
        UPDATE public.payment_provider_events
           SET processing_status='needs_review',
               matched_topup_request_id = v_topup.id,
               matched_user_id = v_topup.client_user_id,
               match_confidence = 0.7,
               notes = coalesce(notes,'') || ' | amount_conflict_code'
         WHERE id = v_event.id;
        RETURN jsonb_build_object('status','needs_review','reason','amount_conflict','topup_request_id',v_topup.id);
      END IF;

      -- Fraud guard: high value forces review
      IF v_event.amount_gnf > v_high_value THEN
        UPDATE public.topup_requests SET status='needs_review'::topup_status WHERE id = v_topup.id;
        UPDATE public.payment_provider_events
           SET processing_status='needs_review',
               matched_topup_request_id = v_topup.id,
               matched_user_id = v_topup.client_user_id,
               match_confidence = 0.98,
               notes = coalesce(notes,'') || ' | high_value'
         WHERE id = v_event.id;
        RETURN jsonb_build_object('status','needs_review','reason','high_value','topup_request_id',v_topup.id);
      END IF;

      -- Rate guard: more than 5 credited topups in 24h for this user
      SELECT count(*) INTO v_recent_count FROM public.topup_requests
       WHERE client_user_id = v_topup.client_user_id
         AND status::text = 'credited'
         AND confirmed_at > now() - interval '24 hours';
      IF v_recent_count >= 5 THEN
        UPDATE public.topup_requests SET status='needs_review'::topup_status WHERE id = v_topup.id;
        UPDATE public.payment_provider_events
           SET processing_status='needs_review',
               matched_topup_request_id = v_topup.id,
               matched_user_id = v_topup.client_user_id,
               match_confidence = 0.95,
               notes = coalesce(notes,'') || ' | rate_limit'
         WHERE id = v_event.id;
        RETURN jsonb_build_object('status','needs_review','reason','rate_limit','topup_request_id',v_topup.id);
      END IF;

      PERFORM public.wallet_topup_om_credit(v_event.id, v_topup.id);
      RETURN jsonb_build_object('status','credited','reason','code_match','topup_request_id',v_topup.id);
    ELSIF v_match_count > 1 THEN
      UPDATE public.payment_provider_events
         SET processing_status='needs_review',
             notes = coalesce(notes,'') || ' | duplicate_customer_code'
       WHERE id = v_event.id;
      RETURN jsonb_build_object('status','needs_review','reason','duplicate_customer_code','matches',v_match_count);
    ELSE
      -- No customer code yet — keep receipt parked, do NOT mark rejected.
      UPDATE public.payment_provider_events
         SET processing_status='received',
             notes = coalesce(notes,'') || ' | awaiting_customer_code'
       WHERE id = v_event.id
         AND processing_status NOT IN ('credited','rejected','needs_review');
      RETURN jsonb_build_object('status','awaiting_customer_code');
    END IF;
  END IF;

  -- ===== Fallback: legacy phone/reference fuzzy match (kept for parity) =====
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
            regexp_replace(coalesce(p.phone,''), '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
            OR regexp_replace(coalesce(t.user_phone,''), '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
          ))
        OR (v_event.raw_payload::text ILIKE '%' || t.reference || '%')
      )
  )
  SELECT count(*) INTO v_match_count FROM candidates;

  IF v_match_count = 0 THEN
    UPDATE public.payment_provider_events
       SET processing_status='needs_review', notes = coalesce(notes,'') || ' | no candidate'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','no_match');
  END IF;
  IF v_match_count > 1 THEN
    UPDATE public.payment_provider_events
       SET processing_status='needs_review', notes = coalesce(notes,'') || ' | ambiguous'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','ambiguous','matches',v_match_count);
  END IF;

  SELECT t.* INTO v_topup
  FROM public.topup_requests t
  LEFT JOIN public.profiles p ON p.user_id = t.client_user_id
  WHERE t.provider='orange_money'
    AND t.status::text IN ('pending','matched','needs_review')
    AND t.amount_gnf = v_event.amount_gnf
    AND t.expires_at > now()
    AND (
      (v_event.payer_phone IS NOT NULL AND (
          regexp_replace(coalesce(p.phone,''), '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
          OR regexp_replace(coalesce(t.user_phone,''), '\D', '', 'g') = regexp_replace(v_event.payer_phone, '\D', '', 'g')
        ))
      OR (v_event.raw_payload::text ILIKE '%' || t.reference || '%')
    )
  LIMIT 1;

  IF v_event.amount_gnf > v_high_value THEN
    UPDATE public.topup_requests SET status='needs_review'::topup_status WHERE id = v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status='needs_review',
           matched_user_id=v_topup.client_user_id,
           matched_topup_request_id=v_topup.id,
           match_confidence=0.95,
           notes = coalesce(notes,'') || ' | high_value'
     WHERE id = v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','high_value','topup_request_id',v_topup.id);
  END IF;

  SELECT count(*) INTO v_recent_count FROM public.topup_requests
   WHERE client_user_id=v_topup.client_user_id AND status::text='credited'
     AND confirmed_at > now() - interval '24 hours';
  IF v_recent_count >= 5 THEN
    UPDATE public.topup_requests SET status='needs_review'::topup_status WHERE id=v_topup.id;
    UPDATE public.payment_provider_events
       SET processing_status='needs_review',
           matched_user_id=v_topup.client_user_id,
           matched_topup_request_id=v_topup.id,
           match_confidence=0.9,
           notes = coalesce(notes,'') || ' | rate_limit'
     WHERE id=v_event.id;
    RETURN jsonb_build_object('status','needs_review','reason','rate_limit','topup_request_id',v_topup.id);
  END IF;

  PERFORM public.wallet_topup_om_credit(v_event.id, v_topup.id);
  RETURN jsonb_build_object('status','credited','topup_request_id',v_topup.id);
END;
$$;

REVOKE ALL ON FUNCTION public.om_auto_match(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.om_auto_match(uuid) TO authenticated;

-- 5) Customer submits OM confirmation code for their own top-up
CREATE OR REPLACE FUNCTION public.submit_customer_om_code(
  p_topup_request_id uuid,
  p_om_code text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_topup public.topup_requests;
  v_norm text;
  v_event public.payment_provider_events;
  v_event_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_om_code IS NULL OR length(trim(p_om_code)) = 0 THEN
    RAISE EXCEPTION 'Code Orange Money requis';
  END IF;

  v_norm := public.normalize_om_code(p_om_code);
  IF v_norm IS NULL OR length(v_norm) < 4 THEN
    RAISE EXCEPTION 'Code Orange Money invalide';
  END IF;
  IF length(v_norm) > 40 THEN
    RAISE EXCEPTION 'Code Orange Money trop long';
  END IF;

  SELECT * INTO v_topup FROM public.topup_requests
   WHERE id = p_topup_request_id FOR UPDATE;
  IF v_topup.id IS NULL THEN RAISE EXCEPTION 'Demande introuvable'; END IF;
  IF v_topup.client_user_id <> v_uid THEN RAISE EXCEPTION 'Non autorisé'; END IF;
  IF v_topup.provider <> 'orange_money' THEN RAISE EXCEPTION 'Demande non Orange Money'; END IF;
  IF v_topup.status::text NOT IN ('pending','matched','needs_review') THEN
    RAISE EXCEPTION 'Cette demande n''est plus active';
  END IF;
  IF v_topup.expires_at < now() THEN
    RAISE EXCEPTION 'Cette demande a expiré';
  END IF;

  -- Reject contradictory re-submissions
  IF v_topup.customer_om_code_normalized IS NOT NULL
     AND v_topup.customer_om_code_normalized <> v_norm THEN
    RAISE EXCEPTION 'Un code différent a déjà été soumis pour cette demande';
  END IF;

  -- Reject same code already used by another active top-up
  SELECT count(*) INTO v_event_count FROM public.topup_requests t
   WHERE t.customer_om_code_normalized = v_norm
     AND t.id <> v_topup.id
     AND t.status::text IN ('pending','matched','credited');
  IF v_event_count > 0 THEN
    UPDATE public.topup_requests
       SET status='needs_review'::topup_status,
           customer_om_code_normalized = v_norm,
           customer_om_code_raw = p_om_code,
           customer_om_code_submitted_at = now(),
           notes = coalesce(notes,'') || ' | duplicate_customer_code'
     WHERE id = v_topup.id;
    RETURN jsonb_build_object('status','needs_review','reason','duplicate_code');
  END IF;

  UPDATE public.topup_requests
     SET customer_om_code_normalized = v_norm,
         customer_om_code_raw = p_om_code,
         customer_om_code_submitted_at = now(),
         status = CASE WHEN status='pending'::topup_status THEN 'matched'::topup_status ELSE status END
   WHERE id = v_topup.id;

  -- Look up any matching admin receipt(s) already parked
  SELECT count(*) INTO v_event_count
    FROM public.payment_provider_events e
   WHERE e.om_code_normalized = v_norm
     AND e.status = 'successful'
     AND e.processing_status NOT IN ('credited','rejected');

  IF v_event_count = 1 THEN
    SELECT * INTO v_event FROM public.payment_provider_events
     WHERE om_code_normalized = v_norm
       AND status='successful'
       AND processing_status NOT IN ('credited','rejected')
     LIMIT 1;
    PERFORM public.om_auto_match(v_event.id);
    RETURN jsonb_build_object('status','attempted_match','event_id', v_event.id);
  ELSIF v_event_count > 1 THEN
    UPDATE public.topup_requests SET status='needs_review'::topup_status,
           notes = coalesce(notes,'') || ' | duplicate_event_code'
     WHERE id = v_topup.id;
    RETURN jsonb_build_object('status','needs_review','reason','duplicate_event_code');
  END IF;

  RETURN jsonb_build_object('status','awaiting_admin_receipt');
END;
$$;

REVOKE ALL ON FUNCTION public.submit_customer_om_code(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.submit_customer_om_code(uuid, text) TO authenticated;

-- 6) Sanitized customer status reader
CREATE OR REPLACE FUNCTION public.get_my_topup_om_status(p_topup_id uuid)
RETURNS TABLE (
  id uuid,
  reference text,
  amount_gnf bigint,
  status text,
  provider text,
  expires_at timestamptz,
  customer_om_code_submitted_at timestamptz,
  receiving_label text,
  receiving_phone text,
  receiving_instructions text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.id, t.reference, t.amount_gnf, t.status::text, t.provider,
         t.expires_at, t.customer_om_code_submitted_at,
         a.label, a.phone_e164, a.public_instructions
    FROM public.topup_requests t
    LEFT JOIN public.payment_receiving_accounts a ON a.id = t.receiving_account_id
   WHERE t.id = p_topup_id
     AND t.client_user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_topup_om_status(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.get_my_topup_om_status(uuid) TO authenticated;
