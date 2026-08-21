-- =====================================================================
-- NODE 5 · A10 — EXISTING CONFLICT REMEDIATION
-- Canonical, read-only professional-identity conflict detector.
-- No data mutation. Governance diagnostic only.
-- =====================================================================

CREATE OR REPLACE FUNCTION public._professional_actor_class(_user uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN _user IS NULL THEN 'unowned_entity'
    WHEN EXISTS (SELECT 1 FROM public.admin_users a
                  WHERE a.user_id = _user AND a.status = 'active') THEN 'staff_admin'
    WHEN NOT EXISTS (SELECT 1 FROM public.profiles pr WHERE pr.user_id = _user) THEN 'orphan_unknown'
    WHEN COALESCE((SELECT pr.email FROM public.profiles pr WHERE pr.user_id = _user), '')
         ~* '(@chopchop\.test$|@example\.(com|org)$|^qa[-_.])' THEN 'qa_test'
    WHEN COALESCE((SELECT pr.email FROM public.profiles pr WHERE pr.user_id = _user), '')
         ~* '^(demo|internal)[-_.]' THEN 'demo'
    ELSE 'real_user'
  END
$$;

REVOKE ALL ON FUNCTION public._professional_actor_class(uuid) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Deterministic scanner. Emits one row per detected condition.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._professional_conflict_scan()
RETURNS TABLE(
  subject_user_id uuid,
  conflict_code text,
  severity text,
  active_type text,
  driver_artifacts jsonb,
  merchant_assets jsonb,
  released_types text[],
  role_signals text[],
  finance jsonb,
  classification text,
  recommended_action text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
WITH subj AS (
  SELECT user_id FROM public.professional_identities WHERE user_id IS NOT NULL
  UNION SELECT user_id FROM public.driver_profiles
  UNION SELECT user_id FROM public.driver_applications
  UNION SELECT owner_user_id FROM public.merchant_stores WHERE owner_user_id IS NOT NULL
  UNION SELECT owner_user_id FROM public.food_restaurants WHERE owner_user_id IS NOT NULL
  UNION SELECT owner_user_id FROM public.merchants WHERE owner_user_id IS NOT NULL
  UNION SELECT user_id FROM public.user_roles WHERE role::text IN ('driver','merchant')
),
ev AS (
  SELECT
    s.user_id AS uid,
    (SELECT p.professional_type FROM public.professional_identities p
      WHERE p.user_id = s.user_id AND p.claim_state = 'active' LIMIT 1) AS act,
    (SELECT count(*) FROM public.professional_identities p
      WHERE p.user_id = s.user_id AND p.claim_state = 'active') AS act_n,
    COALESCE((SELECT array_agg(DISTINCT p.professional_type) FROM public.professional_identities p
               WHERE p.user_id = s.user_id AND p.claim_state <> 'active'), '{}'::text[]) AS rel_types,
    -- CURRENT (non-withdrawn, authority-bearing) driver artifacts
    COALESCE((SELECT jsonb_agg(jsonb_build_object('kind','driver_profile','state',d.status))
                FROM public.driver_profiles d
               WHERE d.user_id = s.user_id AND d.status::text IN ('pending','approved','suspended')), '[]'::jsonb)
    || COALESCE((SELECT jsonb_agg(jsonb_build_object('kind','driver_application','state',a.decision))
                FROM public.driver_applications a
               WHERE a.user_id = s.user_id AND a.decision::text IN ('pending','approved')), '[]'::jsonb) AS cur_driver,
    -- HISTORICAL driver artifacts (never a current conflict)
    COALESCE((SELECT jsonb_agg(jsonb_build_object('kind','driver_profile','state',d.status))
                FROM public.driver_profiles d
               WHERE d.user_id = s.user_id AND d.status::text IN ('withdrawn','rejected')), '[]'::jsonb) AS hist_driver,
    -- CURRENT merchant assets
    COALESCE((SELECT jsonb_agg(jsonb_build_object('kind','merchant_store','state',ms.status))
                FROM public.merchant_stores ms
               WHERE ms.owner_user_id = s.user_id
                 AND ms.status NOT IN ('archived','rejected')), '[]'::jsonb)
    || COALESCE((SELECT jsonb_agg(jsonb_build_object('kind','food_restaurant','state',fr.status))
                FROM public.food_restaurants fr
               WHERE fr.owner_user_id = s.user_id
                 AND fr.status NOT IN ('archived','rejected')), '[]'::jsonb)
    || COALESCE((SELECT jsonb_agg(jsonb_build_object('kind','merchant_entity','state',m.status))
                FROM public.merchants m
               WHERE m.owner_user_id = s.user_id AND m.status = 'active'), '[]'::jsonb) AS cur_merchant,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('kind','merchant_store','state',ms.status))
                FROM public.merchant_stores ms
               WHERE ms.owner_user_id = s.user_id
                 AND ms.status IN ('archived','rejected')), '[]'::jsonb) AS hist_merchant,
    COALESCE((SELECT array_agg(DISTINCT r.role::text) FROM public.user_roles r
               WHERE r.user_id = s.user_id AND r.role::text IN ('driver','merchant')), '{}'::text[]) AS roles,
    jsonb_build_object(
      'wallet_party_types', COALESCE((SELECT array_agg(DISTINCT w.party_type::text) FROM public.wallets w
                                       WHERE w.owner_user_id = s.user_id), '{}'::text[]),
      'pending_driver_cashouts', (SELECT count(*) FROM public.driver_cashout_requests dc
                                   WHERE dc.driver_user_id = s.user_id
                                     AND dc.status NOT IN ('paid','rejected','cancelled')),
      'pending_merchant_settlements', (SELECT count(*) FROM public.merchant_settlement_requests msr
                                        WHERE msr.merchant_user_id = s.user_id
                                          AND msr.status NOT IN ('paid','rejected','cancelled')),
      'open_merchant_payables', (SELECT count(*) FROM public.merchant_payables mp
                                  WHERE mp.merchant_user_id = s.user_id
                                    AND mp.state NOT IN ('settled','cancelled'))
    ) AS fin,
    public._professional_actor_class(s.user_id) AS klass
  FROM subj s
),
hits AS (
  SELECT ev.*, v.code, v.sev, v.rec
  FROM ev
  CROSS JOIN LATERAL (VALUES
    ('C1_DUAL_ACTIVE_IDENTITY','CRITICAL', ev.act_n > 1,
      'Structural violation of the XOR unique index. Escalate; do not pick a side.'),
    ('C2_ACTIVE_DRIVER_WITH_CURRENT_MERCHANT_ASSET','CRITICAL',
      ev.act = 'driver' AND ev.cur_merchant <> '[]'::jsonb,
      'Freeze both sides. Determine lawful class from operational + financial history before any action.'),
    ('C3_ACTIVE_MERCHANT_WITH_CURRENT_DRIVER_ARTIFACT','CRITICAL',
      ev.act = 'merchant' AND ev.cur_driver <> '[]'::jsonb,
      'Freeze both sides. Determine lawful class from operational + financial history before any action.'),
    ('C4_CURRENT_DRIVER_ARTIFACT_WITHOUT_ACTIVE_DRIVER_IDENTITY','CRITICAL',
      ev.cur_driver <> '[]'::jsonb AND ev.act IS DISTINCT FROM 'driver',
      'Driver authority exists without a canonical lane. Reconcile the artifact lifecycle, never backfill a lane blindly.'),
    ('C5_CURRENT_MERCHANT_ASSET_WITHOUT_ACTIVE_MERCHANT_IDENTITY','CRITICAL',
      ev.cur_merchant <> '[]'::jsonb AND ev.act IS DISTINCT FROM 'merchant',
      'Merchant authority exists without a canonical lane. Reconcile the asset lifecycle, never backfill a lane blindly.'),
    ('C6_RELEASED_DRIVER_STILL_OPERATIONAL','HIGH',
      'driver' = ANY(ev.rel_types) AND ev.act IS DISTINCT FROM 'driver' AND ev.cur_driver <> '[]'::jsonb,
      'A4 release did not settle the artifact. Move the artifact to its historical state; keep history.'),
    ('C7_RELEASED_MERCHANT_STILL_OPERATIONAL','HIGH',
      'merchant' = ANY(ev.rel_types) AND ev.act IS DISTINCT FROM 'merchant' AND ev.cur_merchant <> '[]'::jsonb,
      'A4 release did not settle the asset. Archive/suspend the asset; keep economic history.'),
    ('C8_PROFESSIONAL_FINANCE_CLASS_MISMATCH','HIGH',
      ((ev.fin->>'pending_driver_cashouts')::bigint > 0 AND ev.act IS DISTINCT FROM 'driver')
      OR (((ev.fin->>'pending_merchant_settlements')::bigint > 0
           OR (ev.fin->>'open_merchant_payables')::bigint > 0) AND ev.act IS DISTINCT FROM 'merchant'),
      'NEW money movement is possible under the wrong class. Hold the request; do not merge or delete wallets.'),
    ('C9_LEGACY_ROLE_MISMATCH','MEDIUM',
      ('driver' = ANY(ev.roles) AND ev.act IS DISTINCT FROM 'driver')
      OR ('merchant' = ANY(ev.roles) AND ev.act IS DISTINCT FROM 'merchant'),
      'Compatibility residue only; confirm it grants no server authority before any cleanup.'),
    ('C10_ORPHAN_PROFESSIONAL_ARTIFACT','MEDIUM',
      ev.klass = 'orphan_unknown',
      'Artifact references no canonical account. Classify provenance before touching anything.'),
    ('I2_LAWFUL_HISTORICAL_CROSS_CLASS','INFO',
      array_length(ev.rel_types,1) IS NOT NULL
      AND ev.act IS NOT NULL AND NOT (ev.act = ANY(ev.rel_types))
      AND ev.cur_driver = '[]'::jsonb OR FALSE,
      'Lawful A4 release followed by an opposite-class claim. Not a defect. Do not "clean up".')
  ) AS v(code, sev, hit, rec)
  WHERE v.hit
)
SELECT uid, code, sev, act, cur_driver || hist_driver, cur_merchant || hist_merchant,
       rel_types, roles, fin, klass, rec
FROM hits
UNION ALL
-- Legacy pre-Node-5 merchant directory entities with no canonical owner.
-- They confer no authority (no owner to authorize), so they are INFO.
SELECT NULL::uuid, 'I1_LEGACY_MERCHANT_ENTITY_NO_OWNER', 'INFO', NULL,
       '[]'::jsonb,
       jsonb_build_array(jsonb_build_object('kind','merchant_entity','state',m.status,'id',m.id)),
       '{}'::text[], '{}'::text[], '{}'::jsonb, 'unowned_entity',
       'Legacy directory row; confers no merchant authority because no canonical owner exists. Do not auto-assign an owner.'
FROM public.merchants m
WHERE m.owner_user_id IS NULL
$$;

REVOKE ALL ON FUNCTION public._professional_conflict_scan() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------
-- Admin / governance diagnostic surface.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.professional_identity_conflict_audit()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  u uuid := auth.uid();
  v_rows jsonb;
  v_summary jsonb;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF NOT public._is_ops_or_god_admin(u) THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.severity, s.conflict_code), '[]'::jsonb)
    INTO v_rows FROM public._professional_conflict_scan() s;

  SELECT COALESCE(jsonb_object_agg(t.severity, t.n), '{}'::jsonb) INTO v_summary
    FROM (SELECT severity, count(*) AS n FROM public._professional_conflict_scan() GROUP BY 1) t;

  RETURN jsonb_build_object(
    'generated_at', now(),
    'summary', v_summary,
    'critical', COALESCE((v_summary->>'CRITICAL')::int, 0),
    'high', COALESCE((v_summary->>'HIGH')::int, 0),
    'medium', COALESCE((v_summary->>'MEDIUM')::int, 0),
    'info', COALESCE((v_summary->>'INFO')::int, 0),
    'conflicts', v_rows
  );
END $$;

REVOKE ALL ON FUNCTION public.professional_identity_conflict_audit() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.professional_identity_conflict_audit() TO authenticated;