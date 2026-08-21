
CREATE OR REPLACE FUNCTION public._qa_node5_fr_live_reconcile()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '120s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb; t record; res jsonb;
  _role text := COALESCE(NULLIF(current_setting('request.jwt.claims', true),'')::jsonb->>'role', current_user::text);
BEGIN
  IF auth.uid() IS NOT NULL OR _role IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE='42501';
  END IF;

  FOR t IN SELECT user_id FROM public.profiles WHERE account_status='deleted' ORDER BY user_id LOOP
    res := public.admin_account_closure_reconcile(t.user_id, 'node5 final remediation: legacy closure reconciliation');
    r := r || public._qa_s13_ok('N5LIVE reconciled '||left(t.user_id::text,8),
          (res->>'ok')::boolean, res::text);
  END LOOP;

  r := r || public._qa_s13_ok('N5LIVE no closed account keeps an active professional lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities pi
                     JOIN public.profiles p ON p.user_id=pi.user_id
                    WHERE p.account_status='deleted' AND pi.claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5LIVE no closed account keeps a capability role',
        NOT EXISTS (SELECT 1 FROM public.user_roles ur
                     JOIN public.profiles p ON p.user_id=ur.user_id
                    WHERE p.account_status='deleted'), NULL);
  r := r || public._qa_s13_ok('N5LIVE no closed driver stays approved or non-offline',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles dp
                     JOIN public.profiles p ON p.user_id=dp.user_id
                    WHERE p.account_status='deleted'
                      AND (dp.status='approved' OR dp.presence <> 'offline')), NULL);
  r := r || public._qa_s13_ok('N5LIVE no closed account keeps a pending ride offer',
        NOT EXISTS (SELECT 1 FROM public.ride_offers ro
                     JOIN public.profiles p ON p.user_id=ro.driver_id
                    WHERE p.account_status='deleted' AND ro.status='pending'), NULL);
  r := r || public._qa_s13_ok('N5LIVE no closed account keeps recovery material',
        NOT EXISTS (SELECT 1 FROM public.account_recovery_profiles arp
                     JOIN public.profiles p ON p.user_id=arp.user_id
                    WHERE p.account_status='deleted'), NULL);
  r := r || public._qa_s13_ok('N5LIVE no closed account keeps active governance',
        NOT EXISTS (SELECT 1 FROM public.admin_users au
                     JOIN public.profiles p ON p.user_id=au.user_id
                    WHERE p.account_status='deleted' AND au.status='active'), NULL);
  r := r || public._qa_s13_ok('N5LIVE every closed account is enqueued for auth termination',
        (SELECT count(*) FROM public.profiles WHERE account_status='deleted')
        = (SELECT count(*) FROM public.account_access_terminations t
            JOIN public.profiles p ON p.user_id=t.user_id WHERE p.account_status='deleted'), NULL);
  r := r || public._qa_s13_ok('N5LIVE closed-account money is preserved untouched',
        (SELECT COALESCE(sum(balance_gnf),0) FROM public.wallets w
          JOIN public.profiles p ON p.user_id=w.owner_user_id
         WHERE p.account_status='deleted') = 29448,
        (SELECT COALESCE(sum(balance_gnf),0)::text FROM public.wallets w
          JOIN public.profiles p ON p.user_id=w.owner_user_id
         WHERE p.account_status='deleted'));

  RETURN jsonb_build_object(
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END
$function$;

REVOKE EXECUTE ON FUNCTION public._qa_node5_fr_live_reconcile() FROM anon, authenticated, PUBLIC;
GRANT  EXECUTE ON FUNCTION public._qa_node5_fr_live_reconcile() TO service_role;
