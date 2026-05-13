-- Set a default merchant MSISDN placeholder (admins can edit via Settings UI)
UPDATE public.app_settings
SET value = jsonb_set(
  COALESCE(value, '{}'::jsonb),
  '{merchant_msisdn}',
  to_jsonb(COALESCE(NULLIF(value->>'merchant_msisdn',''), '+224 620 00 00 00'))
),
updated_at = now()
WHERE key = 'orange_money';

-- ===== Smoke test: end-to-end OM matching =====
DO $$
DECLARE
  v_event_id uuid;
  v_result jsonb;
  v_dup_err text;
BEGIN
  -- Case A: no candidates (small amount) -> expected needs_review
  INSERT INTO public.payment_provider_events
    (provider, provider_transaction_id, event_type, payer_phone, amount_gnf, status, processing_status, raw_payload)
  VALUES ('orange_money','SMOKE-A-' || extract(epoch from now())::text,'payment.received','+224620111111',25000,'successful','received','{"smoke":"a"}'::jsonb)
  RETURNING id INTO v_event_id;
  v_result := public.om_auto_match(v_event_id);
  RAISE NOTICE 'SMOKE A (no candidate): %', v_result;

  -- Case B: high-value -> expected needs_review (fraud guard)
  INSERT INTO public.payment_provider_events
    (provider, provider_transaction_id, event_type, payer_phone, amount_gnf, status, processing_status, raw_payload)
  VALUES ('orange_money','SMOKE-B-' || extract(epoch from now())::text,'payment.received','+224620222222',6000000,'successful','received','{"smoke":"b"}'::jsonb)
  RETURNING id INTO v_event_id;
  v_result := public.om_auto_match(v_event_id);
  RAISE NOTICE 'SMOKE B (high-value): %', v_result;

  -- Case C: duplicate provider_transaction_id -> expected unique violation
  BEGIN
    INSERT INTO public.payment_provider_events
      (provider, provider_transaction_id, event_type, payer_phone, amount_gnf, status, processing_status, raw_payload)
    VALUES ('orange_money', (SELECT provider_transaction_id FROM public.payment_provider_events WHERE raw_payload->>'smoke'='a'),
            'payment.received','+224620111111',25000,'successful','received','{"smoke":"c"}'::jsonb);
    RAISE NOTICE 'SMOKE C (dup): NOT BLOCKED — unexpected';
  EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS v_dup_err = MESSAGE_TEXT;
    RAISE NOTICE 'SMOKE C (dup): blocked OK -> %', v_dup_err;
  END;

  -- Cleanup
  DELETE FROM public.payment_provider_events WHERE raw_payload->>'smoke' IN ('a','b','c');
  RAISE NOTICE 'SMOKE cleanup done';
END$$;