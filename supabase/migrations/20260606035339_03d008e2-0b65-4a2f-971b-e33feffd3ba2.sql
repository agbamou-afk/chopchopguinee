
CREATE OR REPLACE FUNCTION public.admin_email_delivery_diagnostics(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pgmq
AS $$
DECLARE
  caller uuid := auth.uid();
  is_admin boolean := false;
  email_lc text := lower(trim(coalesce(p_email, '')));
  u record;
  latest record;
  pending_count int := 0;
  sent_count int := 0;
  failed_count int := 0;
  dlq_count int := 0;
  queue_pending int := 0;
  queue_dlq int := 0;
  is_suppressed boolean := false;
  suppressed_reason text := null;
  recommended text;
BEGIN
  IF caller IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthenticated');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = caller
      AND status = 'active'
      AND admin_role IN ('god_admin','super_admin')
  ) INTO is_admin;

  IF NOT is_admin THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  IF email_lc = '' OR position('@' in email_lc) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_email');
  END IF;

  SELECT id, email, created_at, confirmation_sent_at, email_confirmed_at, last_sign_in_at
    INTO u
  FROM auth.users
  WHERE lower(email) = email_lc
  LIMIT 1;

  SELECT count(*) FILTER (WHERE status = 'pending'),
         count(*) FILTER (WHERE status = 'sent'),
         count(*) FILTER (WHERE status IN ('failed','bounced','complained')),
         count(*) FILTER (WHERE status = 'dlq')
    INTO pending_count, sent_count, failed_count, dlq_count
  FROM public.email_send_log
  WHERE lower(recipient_email) = email_lc;

  SELECT template_name, status, error_message, message_id, created_at, metadata
    INTO latest
  FROM public.email_send_log
  WHERE lower(recipient_email) = email_lc
  ORDER BY created_at DESC
  LIMIT 1;

  SELECT EXISTS (
    SELECT 1 FROM public.suppressed_emails WHERE lower(email) = email_lc
  ) INTO is_suppressed;

  IF is_suppressed THEN
    SELECT reason INTO suppressed_reason
    FROM public.suppressed_emails WHERE lower(email) = email_lc LIMIT 1;
  END IF;

  -- Best-effort queue depth — ignore failure if pgmq schema isn't reachable.
  BEGIN
    SELECT count(*) INTO queue_pending FROM pgmq.q_auth_emails;
  EXCEPTION WHEN OTHERS THEN queue_pending := -1; END;
  BEGIN
    SELECT count(*) INTO queue_dlq FROM pgmq.a_auth_emails;
  EXCEPTION WHEN OTHERS THEN queue_dlq := -1; END;

  IF u.id IS NULL THEN
    recommended := 'Aucun utilisateur Auth avec cet email. Demander à l''utilisateur de refaire signup.';
  ELSIF u.email_confirmed_at IS NOT NULL THEN
    recommended := 'Compte déjà confirmé — utiliser Se connecter / mot de passe oublié.';
  ELSIF is_suppressed THEN
    recommended := 'Adresse supprimée (bounce/plainte/unsubscribe). Inscrire un autre email.';
  ELSIF latest.status = 'dlq' OR dlq_count > 0 THEN
    recommended := 'Email parti en DLQ — inspecter process-email-queue et fournisseur.';
  ELSIF latest.status = 'sent' THEN
    recommended := 'Email accepté par le fournisseur — vérifier spam, puis "Renvoyer confirmation".';
  ELSIF latest.status = 'pending' THEN
    recommended := 'Email en file d''attente — vérifier que process-email-queue tourne.';
  ELSIF latest.template_name IS NULL THEN
    recommended := 'Auth user existe mais aucune trace d''email — déclencher "Renvoyer confirmation".';
  ELSE
    recommended := 'Statut inconnu — voir détail latest_status.';
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'email', email_lc,
    'auth_user_exists', u.id IS NOT NULL,
    'auth_user_id', u.id,
    'email_confirmed', u.email_confirmed_at IS NOT NULL,
    'confirmation_sent_at', u.confirmation_sent_at,
    'email_confirmed_at', u.email_confirmed_at,
    'last_sign_in_at', u.last_sign_in_at,
    'auth_user_created_at', u.created_at,
    'send_log', jsonb_build_object(
      'pending', pending_count,
      'sent', sent_count,
      'failed', failed_count,
      'dlq', dlq_count
    ),
    'latest_template', latest.template_name,
    'latest_status', latest.status,
    'latest_error', latest.error_message,
    'latest_message_id', latest.message_id,
    'latest_created_at', latest.created_at,
    'latest_metadata', latest.metadata,
    'suppressed', is_suppressed,
    'suppressed_reason', suppressed_reason,
    'queue_pending_count', queue_pending,
    'queue_dlq_count', queue_dlq,
    'recommended_action', recommended
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_email_delivery_diagnostics(text) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_email_delivery_diagnostics(text) TO authenticated, service_role;
