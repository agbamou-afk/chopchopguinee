CREATE OR REPLACE FUNCTION public._qa_g5_finance_command_center()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  res jsonb := '[]'::jsonb;
  god uuid := gen_random_uuid(); ops uuid := gen_random_uuid();
  fin uuid := gen_random_uuid(); plain uuid := gen_random_uuid();
  susp uuid := gen_random_uuid(); tmp uuid := gen_random_uuid();
  ids uuid[]; v jsonb; err text; ok boolean;
  grants_before int; grants_after int;
  ledger_before bigint; ledger_after bigint;
  wallets_before text; wallets_after text;
  evt_before text; evt_after text;
BEGIN
  ids := ARRAY[god, ops, fin, plain, susp, tmp];
  SELECT count(*) INTO grants_before FROM public.admin_capability_grants;
  SELECT count(*) INTO ledger_before FROM public.ledger_postings;
  SELECT md5(coalesce(string_agg(id::text||balance_gnf||held_gnf||status::text, ',' ORDER BY id),''))
    INTO wallets_before FROM public.wallets;
  SELECT md5(coalesce(string_agg(id::text||coalesce(processing_status,''), ',' ORDER BY id),''))
    INTO evt_before FROM public.payment_provider_events;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  SELECT u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'qa.g5.'||u::text||'@chopchop.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb
  FROM unnest(ids) u;
  INSERT INTO public.profiles (user_id, full_name)
  SELECT u, 'QA G5 fixture' FROM unnest(ids) u ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.admin_users (user_id, admin_role, status, notes, must_change_password) VALUES
    (god ,'god_admin'     ,'active'   ,'qa_g5_fixture', false),
    (ops ,'ops_admin'     ,'active'   ,'qa_g5_fixture', false),
    (fin ,'finance_admin' ,'active'   ,'qa_g5_fixture', false),
    (susp,'finance_admin' ,'suspended','qa_g5_fixture', false),
    (tmp ,'finance_admin' ,'active'   ,'qa_g5_fixture', true);

  -- A · capability posture ------------------------------------------------
  res := res || jsonb_build_object('id',1,'name','finance holds finance.wallet.read (ALLOW)','pass',
    public.admin_capability_mode('finance.wallet.read', fin) = 'allow');
  res := res || jsonb_build_object('id',2,'name','operations holds no finance.wallet.read','pass',
    public.admin_capability_mode('finance.wallet.read', ops) IS NULL);
  res := res || jsonb_build_object('id',3,'name','customer holds no finance capability','pass',
    public.admin_capability_mode('finance.wallet.read', plain) IS NULL
    AND public.admin_role_canonical(plain) IS NULL);
  res := res || jsonb_build_object('id',4,'name','suspended finance staff has no authority','pass',
    public.admin_role_canonical(susp) IS NULL
    AND public.admin_capability_mode('finance.wallet.read', susp) IS NULL);
  res := res || jsonb_build_object('id',5,'name','temp-password finance staff has zero capability','pass',
    public.admin_staff_readiness(tmp) = 'temp_password_required'
    AND public.admin_capability_mode('finance.wallet.read', tmp) IS NULL
    AND public.admin_capability_mode('finance.payout.confirm', tmp) IS NULL);
  res := res || jsonb_build_object('id',6,'name','money movement is approval-bound, never ALLOW','pass',
    public.admin_capability_mode('finance.wallet.credit', fin) = 'approval_required'
    AND public.admin_capability_mode('finance.wallet.adjust', fin) = 'approval_required'
    AND public.admin_capability_mode('finance.treasury.move', fin) = 'approval_required'
    AND public.admin_capability_mode('finance.payout.confirm', fin) = 'approval_required'
    AND public.admin_capability_mode('finance.refund.approve', fin) = 'approval_required'
    AND public.admin_capability_mode('finance.policy.change', fin) = 'approval_required');
  res := res || jsonb_build_object('id',7,'name','operational capabilities are READ for finance','pass',
    public.admin_capability_mode('ops.orders.manage', fin) = 'read'
    AND public.admin_capability_mode('ops.drivers.manage', fin) = 'read'
    AND NOT coalesce(public.admin_capability('ops.orders.manage', fin), false));
  res := res || jsonb_build_object('id',8,'name','governance stays outside finance','pass',
    public.admin_capability_mode('governance.staff.manage', fin) IS NULL
    AND public.admin_capability_mode('governance.flags.manage', fin) IS NULL
    AND public.admin_capability_mode('governance.settings.manage', fin) IS NULL);

  -- B · the read model ------------------------------------------------------
  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  v := public.finance_command_overview();
  res := res || jsonb_build_object('id',9,'name','finance reads the command-center model','pass',
    v ? 'snapshot' AND v ? 'attention' AND v ? 'exceptions' AND (v->>'role') = 'finance_admin');
  res := res || jsonb_build_object('id',10,'name','snapshot carries every canonical finance queue','pass',
    (v->'snapshot') ? 'topups_pending' AND (v->'snapshot') ? 'provider_events_open'
    AND (v->'snapshot') ? 'cashouts_pending' AND (v->'snapshot') ? 'settlements_pending'
    AND (v->'snapshot') ? 'payables_open' AND (v->'snapshot') ? 'payouts_open'
    AND (v->'snapshot') ? 'refunds_pending' AND (v->'snapshot') ? 'intents_review'
    AND (v->'snapshot') ? 'wallets_frozen');
  res := res || jsonb_build_object('id',11,'name','attention and exceptions are arrays, never null','pass',
    jsonb_typeof(v->'attention') = 'array' AND jsonb_typeof(v->'exceptions') = 'array');
  res := res || jsonb_build_object('id',12,'name','exception totals agree with the exception list','pass',
    (v->>'exceptions_total')::int = jsonb_array_length(v->'exceptions'));
  res := res || jsonb_build_object('id',13,'name','read model exposes no PII','pass',
    NOT (v::text ILIKE '%payer_phone%' OR v::text ILIKE '%payout_phone%'
      OR v::text ILIKE '%msisdn%' OR v::text ILIKE '%full_name%' OR v::text ILIKE '%email%'));
  res := res || jsonb_build_object('id',14,'name','every attention row carries its execution mode','pass',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'attention') a
                WHERE NOT (a ? 'mode') OR NOT (a ? 'href') OR NOT (a ? 'severity')));
  res := res || jsonb_build_object('id',15,'name','attention rows only route to finance surfaces','pass',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v->'attention') a
                WHERE (a->>'href') NOT LIKE '/admin/%'));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(god), true);
  res := res || jsonb_build_object('id',16,'name','god admin reads the same model','pass',
    public.finance_command_overview() ? 'snapshot');

  -- C · denials ------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok := false; BEGIN PERFORM public.finance_command_overview(); EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM; END;
  res := res || jsonb_build_object('id',17,'name','operations is denied the finance read model','pass',
    ok AND err ILIKE '%capability_denied%');
  PERFORM set_config('request.jwt.claims', public._as_user_claims(plain), true);
  ok := false; BEGIN PERFORM public.finance_command_overview(); EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',18,'name','a customer is denied the finance read model','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(susp), true);
  ok := false; BEGIN PERFORM public.finance_command_overview(); EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',19,'name','a suspended finance account is denied','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(tmp), true);
  ok := false; BEGIN PERFORM public.finance_command_overview(); EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',20,'name','a temp-password finance account is denied','pass', ok);
  PERFORM set_config('request.jwt.claims', '', true);
  ok := false; BEGIN PERFORM public.finance_command_overview(); EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',21,'name','an unauthenticated caller is denied','pass', ok);

  -- D · governed provider-event rejection ----------------------------------
  res := res || jsonb_build_object('id',22,'name','payment_provider_events has no direct UPDATE policy','pass',
    NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='payment_provider_events' AND cmd='UPDATE'));
  res := res || jsonb_build_object('id',23,'name','authenticated holds no write grant on provider events','pass',
    NOT has_table_privilege('authenticated','public.payment_provider_events','UPDATE')
    AND NOT has_table_privilege('authenticated','public.payment_provider_events','INSERT')
    AND NOT has_table_privilege('authenticated','public.payment_provider_events','DELETE'));
  res := res || jsonb_build_object('id',24,'name','anon cannot execute the finance read model','pass',
    NOT has_function_privilege('anon','public.finance_command_overview()','EXECUTE')
    AND NOT has_function_privilege('anon','public.admin_reject_om_event(uuid,text)','EXECUTE'));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok := false; BEGIN PERFORM public.admin_reject_om_event(gen_random_uuid(),'x'); EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM; END;
  res := res || jsonb_build_object('id',25,'name','operations cannot reject a provider event','pass',
    ok AND err ILIKE '%capability_denied%');
  PERFORM set_config('request.jwt.claims', public._as_user_claims(plain), true);
  ok := false; BEGIN PERFORM public.admin_reject_om_event(gen_random_uuid(),'x'); EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',26,'name','a customer cannot reject a provider event','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ok := false; BEGIN PERFORM public.admin_reject_om_event(gen_random_uuid(),'   '); EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM; END;
  res := res || jsonb_build_object('id',27,'name','a rejection without a reason is refused','pass',
    ok AND err ILIKE '%reason_required%');
  ok := false; BEGIN PERFORM public.admin_reject_om_event(gen_random_uuid(),'motif'); EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM; END;
  res := res || jsonb_build_object('id',28,'name','rejecting an unknown event fails closed','pass',
    ok AND err ILIKE '%event_not_found%');

  -- E · approval binding on money -------------------------------------------
  ok := false; BEGIN PERFORM public.admin_set_payout_policy(NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'qa g5',NULL);
    EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM; END;
  res := res || jsonb_build_object('id',29,'name','finance cannot change payout policy without approval','pass',
    ok AND (err ILIKE '%approval_required%' OR err ILIKE '%capability_denied%'));
  ok := false; BEGIN PERFORM public.admin_set_feature_flag('qa_g5_flag', true, NULL);
    EXCEPTION WHEN OTHERS THEN ok := true; err := SQLERRM; END;
  res := res || jsonb_build_object('id',30,'name','finance cannot flip a platform flag','pass', ok);
  ok := false; BEGIN PERFORM public.admin_staff_role_grant(plain, 'finance_admin', 'qa', NULL);
    EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',31,'name','finance cannot grant a staff role','pass', ok);

  -- F · no drift -------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '', true);
  SELECT count(*) INTO grants_after FROM public.admin_capability_grants;
  SELECT count(*) INTO ledger_after FROM public.ledger_postings;
  SELECT md5(coalesce(string_agg(id::text||balance_gnf||held_gnf||status::text, ',' ORDER BY id),''))
    INTO wallets_after FROM public.wallets;
  SELECT md5(coalesce(string_agg(id::text||coalesce(processing_status,''), ',' ORDER BY id),''))
    INTO evt_after FROM public.payment_provider_events;
  res := res || jsonb_build_object('id',32,'name','no capability registry drift','pass', grants_before = grants_after);
  res := res || jsonb_build_object('id',33,'name','no ledger drift','pass', ledger_before = ledger_after);
  res := res || jsonb_build_object('id',34,'name','no wallet balance drift','pass', wallets_before = wallets_after);
  res := res || jsonb_build_object('id',35,'name','no provider event drift','pass', evt_before = evt_after);

  -- cleanup ------------------------------------------------------------------
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);
  res := res || jsonb_build_object('id',36,'name','fixtures leave zero residue','pass',
    NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids))
    AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = ANY(ids)));

  RETURN jsonb_build_object(
    'total', jsonb_array_length(res),
    'passed', (SELECT count(*) FROM jsonb_array_elements(res) x WHERE (x->>'pass')::boolean),
    'failures', (SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(res) x
                 WHERE NOT (x->>'pass')::boolean),
    'results', res);
EXCEPTION WHEN OTHERS THEN
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);
  RAISE;
END;$$;

REVOKE ALL ON FUNCTION public._qa_g5_finance_command_center() FROM PUBLIC, anon, authenticated;