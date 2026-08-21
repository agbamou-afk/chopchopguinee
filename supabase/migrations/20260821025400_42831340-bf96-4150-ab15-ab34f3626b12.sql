DO $mig$
DECLARE
  def text := pg_get_functiondef('public._qa_node5_identity_a6'::regproc);
  a1 text := E'        (SELECT count(*) FROM public.wallet_transactions WHERE wallet_id IN\n           (SELECT id FROM public.wallets WHERE user_id = ANY(ids))) = 0, NULL);';
  n1 text := E'        (SELECT count(*) FROM public.wallet_transactions wt\n          WHERE wt.related_user_id = ANY(ids)\n             OR wt.from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))\n             OR wt.to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))) = 0, NULL);';
  a2 text := E'        (SELECT count(*) FROM public.ledger_postings lp\n          JOIN public.ledger_accounts la ON la.id=lp.account_id\n          WHERE la.owner_user_id = ANY(ids)) = 0, NULL);';
  n2 text := E'        (SELECT count(*) FROM public.ledger_journals lj WHERE lj.actor_user_id = ANY(ids)) = 0, NULL);';
BEGIN
  IF position(a1 in def) = 0 THEN RAISE EXCEPTION 'A6_QA_K1_ANCHOR_MISSING'; END IF;
  IF position(a2 in def) = 0 THEN RAISE EXCEPTION 'A6_QA_K2_ANCHOR_MISSING'; END IF;
  def := replace(def, a1, n1);
  def := replace(def, a2, n2);
  EXECUTE def;
END $mig$;