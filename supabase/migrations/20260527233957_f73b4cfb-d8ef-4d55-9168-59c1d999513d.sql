-- Defense-in-depth: even though authenticated/anon have zero column grants on
-- public.topup_requests (confirmation_code is unreadable directly), drop the
-- residual client SELECT policy so the scanner and any future grant changes
-- can't accidentally re-expose sensitive columns. Clients read their pending
-- top-up exclusively via the SECURITY DEFINER RPC `get_my_pending_topup`.
DROP POLICY IF EXISTS "Client views own topups" ON public.topup_requests;