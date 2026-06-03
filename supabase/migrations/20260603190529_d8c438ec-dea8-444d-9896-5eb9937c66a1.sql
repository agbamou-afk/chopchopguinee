
-- Sanitized: does the signed-in user have a wallet PIN set?
CREATE OR REPLACE FUNCTION public.user_has_pin()
RETURNS TABLE(has_pin boolean, updated_at timestamptz)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT TRUE, p.updated_at
    FROM public.user_pins p
   WHERE p.user_id = auth.uid()
  UNION ALL
  SELECT FALSE, NULL::timestamptz
   WHERE NOT EXISTS (SELECT 1 FROM public.user_pins WHERE user_id = auth.uid())
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.user_has_pin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_has_pin() TO authenticated;

-- Sanitized: signed-in customer's own top-up history.
-- Excludes: confirmation_code, customer_om_code_*, matched_provider_transaction_id,
-- notes, agent_user_id, transaction_id, raw provider payloads.
CREATE OR REPLACE FUNCTION public.list_my_topup_requests(p_limit int DEFAULT 20)
RETURNS TABLE(
  id uuid,
  reference text,
  amount_gnf bigint,
  status text,
  provider text,
  created_at timestamptz,
  updated_at timestamptz,
  expires_at timestamptz,
  confirmed_at timestamptz,
  cancelled_reason text,
  customer_code_submitted_at timestamptz,
  receiving_label text,
  receiving_phone text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.id, t.reference, t.amount_gnf, t.status::text, t.provider,
         t.created_at, t.updated_at, t.expires_at, t.confirmed_at,
         t.cancelled_reason, t.customer_om_code_submitted_at,
         a.label, a.phone_e164
    FROM public.topup_requests t
    LEFT JOIN public.payment_receiving_accounts a
      ON a.id = t.receiving_account_id
   WHERE t.client_user_id = auth.uid()
   ORDER BY t.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 100));
$$;

REVOKE ALL ON FUNCTION public.list_my_topup_requests(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_my_topup_requests(int) TO authenticated;
