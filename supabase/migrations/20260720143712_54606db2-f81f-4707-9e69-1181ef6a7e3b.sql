
CREATE OR REPLACE FUNCTION public.email_get_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  v_sent int := 0;
  v_failed int := 0;
  v_dlq int := 0;
  v_suppressed int := 0;
  v_pending int := 0;
  v_last_sent timestamptz;
  v_queue_len int := 0;
  v_dlq_len int := 0;
BEGIN
  IF caller IS NULL OR NOT public.is_admin(caller) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  WITH latest AS (
    SELECT DISTINCT ON (message_id) status, created_at
    FROM public.email_send_log
    WHERE message_id IS NOT NULL
      AND created_at >= now() - interval '7 days'
    ORDER BY message_id, created_at DESC
  )
  SELECT
    COUNT(*) FILTER (WHERE status = 'sent'),
    COUNT(*) FILTER (WHERE status = 'failed'),
    COUNT(*) FILTER (WHERE status = 'dlq'),
    COUNT(*) FILTER (WHERE status = 'suppressed'),
    COUNT(*) FILTER (WHERE status = 'pending'),
    MAX(created_at) FILTER (WHERE status = 'sent')
  INTO v_sent, v_failed, v_dlq, v_suppressed, v_pending, v_last_sent
  FROM latest;

  BEGIN
    SELECT COUNT(*) INTO v_queue_len FROM pgmq.q_auth_emails;
  EXCEPTION WHEN OTHERS THEN v_queue_len := 0;
  END;
  BEGIN
    SELECT v_queue_len + COUNT(*) INTO v_queue_len FROM pgmq.q_transactional_emails;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  BEGIN
    SELECT COUNT(*) INTO v_dlq_len FROM pgmq.a_auth_emails;
  EXCEPTION WHEN OTHERS THEN v_dlq_len := 0;
  END;
  BEGIN
    SELECT v_dlq_len + COUNT(*) INTO v_dlq_len FROM pgmq.a_transactional_emails;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'sent_7d', v_sent,
    'failed_7d', v_failed,
    'dlq_7d', v_dlq,
    'suppressed_7d', v_suppressed,
    'pending_7d', v_pending,
    'last_sent_at', v_last_sent,
    'queue_backlog', v_queue_len,
    'dlq_backlog', v_dlq_len,
    'checked_at', now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.email_get_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.email_get_health() TO authenticated;
GRANT EXECUTE ON FUNCTION public.email_get_health() TO service_role;
