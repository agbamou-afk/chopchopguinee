DO $mig$
DECLARE src text; newsrc text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = '_qa_s1c_inner';
  newsrc := replace(src,
$old$  UPDATE public.wallets SET balance_gnf = balance_gnf + 500000
   WHERE owner_user_id = d1 AND party_type = 'driver';
  IF NOT FOUND THEN
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf, currency, status)
    VALUES (d1, 'driver', 500000, 0, 'GNF', 'active');
  END IF;$old$,
$new$  UPDATE public.wallets SET balance_gnf = balance_gnf + 5000000, held_gnf = 0, status = 'active'
   WHERE owner_user_id = d1 AND party_type = 'driver';
  IF NOT FOUND THEN
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf, currency, status)
    VALUES (d1, 'driver', 5000000, 0, 'GNF', 'active');
  END IF;
  UPDATE public.wallets SET balance_gnf = balance_gnf + 5000000, held_gnf = 0, status = 'active'
   WHERE owner_user_id = d2 AND party_type = 'driver';
  IF NOT FOUND THEN
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf, currency, status)
    VALUES (d2, 'driver', 5000000, 0, 'GNF', 'active');
  END IF;$new$);
  IF newsrc = src THEN RAISE EXCEPTION 'harness funding block not found'; END IF;
  EXECUTE newsrc;
END $mig$;