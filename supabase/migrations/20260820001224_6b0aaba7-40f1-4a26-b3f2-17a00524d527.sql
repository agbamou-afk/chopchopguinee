CREATE TABLE IF NOT EXISTS public._qa_final_board (
  id bigserial primary key, kind text, suite text, total int, failed int, err text, note text
);
DELETE FROM public._qa_final_board;

INSERT INTO public._qa_final_board(kind, suite, note)
SELECT 'snapshot', 'pre', jsonb_build_object(
  'wallets_balance', (SELECT COALESCE(sum(balance_gnf),0) FROM public.wallets),
  'wallets_held', (SELECT COALESCE(sum(held_gnf),0) FROM public.wallets),
  'wallet_txn_count', (SELECT count(*) FROM public.wallet_transactions),
  'ledger_postings', (SELECT count(*) FROM public.ledger_postings),
  'ledger_sum', (SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings),
  'flags_md5', (SELECT md5(string_agg(f.key||'='||f.enabled::text, ',' ORDER BY f.key)) FROM public.feature_flags f),
  'price_obs', (SELECT count(*) FROM public.marche_procurement_price_observations),
  'marche_listings', (SELECT count(*) FROM public.marketplace_listings)
)::text;

DO $$
DECLARE f record; j jsonb; arr jsonb; t int; fl int;
BEGIN
  FOR f IN
    SELECT p.proname AS nm,
           CASE WHEN p.proname LIKE '\_qa\_s13\_run%' THEN 'slice13' ELSE 'node' END AS kind
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.pronargs = 0 AND p.prorettype='jsonb'::regtype
       AND (p.proname LIKE '\_qa\_node%' OR p.proname LIKE '\_qa\_s13\_run%')
       AND p.proname NOT LIKE '%\_fxcore'
     ORDER BY 1
  LOOP
    BEGIN
      EXECUTE format('SELECT public.%I()', f.nm) INTO j;
      arr := CASE WHEN jsonb_typeof(j)='array' THEN j ELSE COALESCE(j->'results', j->'failures', '[]'::jsonb) END;
      SELECT count(*), count(*) FILTER (WHERE (x->>'ok')::boolean IS FALSE) INTO t, fl FROM jsonb_array_elements(arr) x;
      IF jsonb_typeof(j)='object' AND (j ? 'total') THEN
        t := (j->>'total')::int; fl := COALESCE((j->>'failed')::int, fl);
      END IF;
      INSERT INTO public._qa_final_board(kind, suite, total, failed, err)
      VALUES (f.kind, f.nm, t, fl,
        (SELECT string_agg(x->>'label', ' | ') FROM jsonb_array_elements(arr) x WHERE (x->>'ok')::boolean IS FALSE));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_final_board(kind, suite, err) VALUES (f.kind, f.nm, 'ABORT: '||SQLERRM);
    END;
  END LOOP;
END $$;

INSERT INTO public._qa_final_board(kind, suite, note)
SELECT 'snapshot', 'post', jsonb_build_object(
  'wallets_balance', (SELECT COALESCE(sum(balance_gnf),0) FROM public.wallets),
  'wallets_held', (SELECT COALESCE(sum(held_gnf),0) FROM public.wallets),
  'wallet_txn_count', (SELECT count(*) FROM public.wallet_transactions),
  'ledger_postings', (SELECT count(*) FROM public.ledger_postings),
  'ledger_sum', (SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings),
  'flags_md5', (SELECT md5(string_agg(f.key||'='||f.enabled::text, ',' ORDER BY f.key)) FROM public.feature_flags f),
  'price_obs', (SELECT count(*) FROM public.marche_procurement_price_observations),
  'marche_listings', (SELECT count(*) FROM public.marketplace_listings)
)::text;