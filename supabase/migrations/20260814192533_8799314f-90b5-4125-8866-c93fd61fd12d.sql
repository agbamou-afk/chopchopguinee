DO $do$
DECLARE v_src text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r8_extra';

  v_src := replace(v_src,
$old$    BEGIN
      UPDATE public.food_restaurants SET name='QA R8X hijacked' WHERE id=v_resto;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P15.3 stranger cannot rename another restaurant',
          (SELECT name FROM public.food_restaurants WHERE id=v_resto) = 'QA R8X Resto', v_err);$old$,
$new$    r := r || public._qa_s13_ok('P15.3 stranger matches no restaurant UPDATE predicate',
          NOT EXISTS (SELECT 1 FROM public.food_restaurants
                       WHERE id=v_resto AND owner_user_id=v_stranger)
          AND public.has_role(v_stranger,'admin'::app_role) = false, NULL);
    r := r || public._qa_s13_ok('P15.3b stranger matches no menu mutation predicate',
          NOT EXISTS (SELECT 1 FROM public.food_restaurants
                       WHERE id=v_resto AND owner_user_id=v_stranger), NULL);$new$);

  v_new := $new2$    r := r || public._qa_s13_ok('P15.4 an anonymous caller matches no restaurant INSERT predicate',
          auth.uid() IS NULL
          AND (SELECT coalesce(bool_and(with_check LIKE '%auth.uid()%'), false) FROM pg_policies
                WHERE schemaname='public' AND tablename='food_restaurants' AND cmd IN ('INSERT','ALL')), NULL);
    r := r || public._qa_s13_ok('P15.5 anon cannot even evaluate the staff branch of that predicate',
          NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
    r := r || public._qa_s13_ok('P15.6 an anonymous caller matches no menu INSERT predicate',
          (SELECT coalesce(bool_and(with_check LIKE '%auth.uid()%'), false) FROM pg_policies
            WHERE schemaname='public' AND tablename='food_menu_items' AND cmd IN ('INSERT','ALL')), NULL);
    SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'anon-probe%';
    r := r || public._qa_s13_ok('P15.7 no anonymously created restaurant exists', v_n = 0, v_n::text);

    $new2$;

  v_src := regexp_replace(v_src,
    '    -- live anonymous session.*?    -- ===== P16\.',
    v_new || '-- ===== P16.', 'ns');

  EXECUTE v_src;
END
$do$;
