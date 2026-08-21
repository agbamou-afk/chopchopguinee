DO $mig$
DECLARE
  src text;
  old_b6 text; new_b6 text; old_d5 text; new_d5 text;
BEGIN
  src := pg_get_functiondef('public._qa_node5_identity_a3()'::regprocedure);

  old_b6 := $a$  r := r || public._qa_s13_ok('N5A3.B6 claim recorded its onboarding provenance',
        (SELECT claim_source FROM public.professional_identities WHERE user_id=u_drv AND claim_state='active')
          IN ('driver_profiles','driver_applications'), NULL);$a$;

  new_b6 := $a$  r := r || public._qa_s13_ok('N5A3.B6 canonical driver_apply composition point owns the lane claim, recorded before the artifact',
        (SELECT claim_source FROM public.professional_identities WHERE user_id=u_drv AND claim_state='active') = 'driver_apply'
        AND pg_get_functiondef('public.driver_apply(jsonb)'::regprocedure) ILIKE '%professional_lane_require(%'
        AND (SELECT claimed_at FROM public.professional_identities WHERE user_id=u_drv AND claim_state='active')
            <= (SELECT created_at FROM public.driver_profiles WHERE user_id=u_drv), NULL);$a$;

  old_d5 := $a$  r := r || public._qa_s13_ok('N5A3.D5 one merchant owner keeps exactly one store (platform rule holds)',
        v_err ILIKE '%merchant_stores_owner_user_id_key%', v_err);
  r := r || public._qa_s13_ok('N5A3.D5b the refused second store created no extra store row',
        (SELECT count(*) FROM public.merchant_stores WHERE owner_user_id=u_mer) = 1, NULL);$a$;

  new_d5 := $a$  r := r || public._qa_s13_ok('N5A3.D5 one merchant owner keeps exactly one LIVE (non-archived) store',
        v_err IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_index i
                     WHERE i.indrelid='public.merchant_stores'::regclass AND i.indisunique
                       AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%status%archived%'
                       AND pg_get_indexdef(i.indexrelid) ILIKE '%(owner_user_id)%'), v_err);
  r := r || public._qa_s13_ok('N5A3.D5b the refused second store created no extra store row',
        (SELECT count(*) FROM public.merchant_stores WHERE owner_user_id=u_mer) = 1, NULL);
  UPDATE public.merchant_stores SET status='archived' WHERE id=v_store;
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug)
    VALUES (u_mer, u_mer, 'QA A3 Store 3', 'qa-a3-store3-'||substr(u_mer::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.D5c archived store history is preserved and never blocks lawful re-entry',
        v_err IS NULL
        AND (SELECT count(*) FROM public.merchant_stores WHERE owner_user_id=u_mer AND status='archived') = 1
        AND (SELECT count(*) FROM public.merchant_stores WHERE owner_user_id=u_mer AND status <> 'archived') = 1, v_err);
  DELETE FROM public.merchant_stores WHERE owner_user_id=u_mer AND id <> v_store;
  UPDATE public.merchant_stores SET status='pending' WHERE id=v_store;$a$;

  IF position(old_b6 in src) = 0 THEN RAISE EXCEPTION 'B6 anchor not found'; END IF;
  IF position(old_d5 in src) = 0 THEN RAISE EXCEPTION 'D5 anchor not found'; END IF;

  src := replace(src, old_b6, new_b6);
  src := replace(src, old_d5, new_d5);

  EXECUTE src;
END $mig$;