DROP FUNCTION IF EXISTS public._repas_custody_consume(uuid, text, text, uuid);

CREATE FUNCTION public._repas_custody_consume(p_order_id uuid, p_kind text, p_code text, p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v public.repas_custody_credentials; v_att int;
BEGIN
  SELECT * INTO v FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND kind = p_kind FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_NOT_ISSUED'; END IF;
  IF v.consumed_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_ALREADY_USED'; END IF;
  IF v.locked_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_LOCKED'; END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'CUSTODY_CODE_REQUIRED';
  END IF;

  IF public._repas_custody_hash(v.code_salt, trim(p_code)) IS DISTINCT FROM v.code_hash THEN
    -- Soft refusal: raising here would roll back the attempt counter with the
    -- rest of the statement, which would make the lockout unreachable.
    UPDATE public.repas_custody_credentials
       SET attempts = attempts + 1,
           locked_at = CASE WHEN attempts + 1 >= 5 THEN now() ELSE locked_at END,
           updated_at = now()
     WHERE id = v.id
     RETURNING attempts INTO v_att;
    RETURN jsonb_build_object('ok', false, 'error', 'CUSTODY_CODE_INVALID',
                              'attempts', v_att, 'attempts_left', GREATEST(5 - v_att, 0),
                              'locked', v_att >= 5);
  END IF;

  UPDATE public.repas_custody_credentials
     SET consumed_at = now(), consumed_by = p_actor, updated_at = now()
   WHERE id = v.id;
  RETURN jsonb_build_object('ok', true);
END; $function$;

REVOKE ALL ON FUNCTION public._repas_custody_consume(uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;

DO $do$
DECLARE v_def text; v_new text; v_name text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['repas_custody_confirm_handoff',
                                'repas_custody_confirm_delivery',
                                'repas_custody_confirm_pickup_collection'] LOOP
    SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname = v_name;
    IF v_def NOT LIKE '%PERFORM public._repas_custody_consume(%' THEN
      RAISE EXCEPTION 'CONSUME_CALL_NOT_FOUND_%', v_name;
    END IF;
    v_new := regexp_replace(v_def, 'DECLARE', 'DECLARE v_consume jsonb;');
    v_new := regexp_replace(v_new,
      'PERFORM public\._repas_custody_consume\(([^;]*)\);',
      E'v_consume := public._repas_custody_consume(\\1);\n  IF NOT (v_consume->>''ok'')::boolean THEN RETURN v_consume; END IF;');
    IF v_new LIKE '%PERFORM public._repas_custody_consume(%' THEN
      RAISE EXCEPTION 'CONSUME_PATCH_FAILED_%', v_name;
    END IF;
    EXECUTE v_new;
  END LOOP;
END $do$;