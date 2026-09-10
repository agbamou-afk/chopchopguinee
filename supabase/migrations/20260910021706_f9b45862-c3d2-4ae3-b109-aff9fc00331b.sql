CREATE OR REPLACE FUNCTION public.ops_command_overview()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
  v_mode text;
  v_now timestamptz := now();
  v_today timestamptz := date_trunc('day', now());
  snap jsonb;
  items jsonb;
BEGIN
  -- G4: authority is the G1/G2 capability registry. `ops.liveops.view` is ALLOW for
  -- Operations and God, READ for Finance. Absence of a grant is denial.
  v_role := public.admin_role_canonical(v_uid);
  v_mode := public.admin_capability_mode('ops.liveops.view', v_uid);
  IF v_mode IS NULL THEN
    RAISE EXCEPTION 'capability_denied: ops.liveops.view';
  END IF;

  SELECT jsonb_build_object(
    'rides_active', (SELECT count(*) FROM public.rides WHERE status::text IN ('pending','in_progress')),
    'rides_today', (SELECT count(*) FROM public.rides WHERE created_at >= v_today),
    'rides_unassigned', (SELECT count(*) FROM public.rides WHERE status::text = 'pending' AND driver_id IS NULL),
    'missions_active', (SELECT count(*) FROM public.missions WHERE state::text NOT IN ('delivered','failed')),
    'repas_active', (SELECT count(*) FROM public.food_orders WHERE state::text IN ('placed','confirmed','preparing','ready','out_for_delivery')),
    'marche_active', (SELECT count(*) FROM public.marche_orders WHERE status NOT IN ('cancelled','completed','delivered','rejected','expired')),
    'envoyer_active', (SELECT count(*) FROM public.package_deliveries WHERE coalesce(package_status,'') NOT IN ('delivered','cancelled','failed')),
    'drivers_online', (SELECT count(*) FROM public.driver_locations WHERE updated_at >= v_now - interval '15 minutes'),
    'drivers_approved', (SELECT count(*) FROM public.driver_profiles WHERE status::text = 'approved'),
    'driver_apps_pending', (SELECT count(*) FROM public.driver_applications WHERE decision::text = 'pending'),
    'merchant_apps_pending', (SELECT count(*) FROM public.merchant_stores WHERE onboarding_status = 'submitted'),
    'ops_cases_open', (SELECT count(*) FROM public.marche_ops_cases WHERE status = 'open')
                    + (SELECT count(*) FROM public.repas_ops_cases WHERE status = 'open'),
    'support_open', (SELECT count(*) FROM public.support_issues
                      WHERE status::text IN ('open','in_review','waiting_on_user','waiting_on_courier','waiting_on_merchant','escalated')),
    'support_critical', (SELECT count(*) FROM public.support_issues
                      WHERE status::text IN ('open','in_review','escalated') AND severity::text IN ('high','critical')),
    'map_duplicates_open', (SELECT count(*) FROM public.map_place_duplicate_candidates WHERE status = 'open')
  ) INTO snap;

  WITH q AS (
    (SELECT 'driver_approval'::text kind, 'Chauffeurs'::text service,
            'Candidature chauffeur'::text label, left(a.id::text,8) reference,
            'en attente'::text state, a.created_at since, 'normal'::text severity,
            NULL::text finance_context, '/admin/drivers'::text href
       FROM public.driver_applications a WHERE a.decision::text = 'pending'
      ORDER BY a.created_at LIMIT 20)
    UNION ALL
    (SELECT 'merchant_approval', 'Marchands', 'Boutique à valider', left(s.id::text,8),
            coalesce(s.onboarding_status,'—'), s.submitted_at, 'normal', NULL, '/admin/merchants'
       FROM public.merchant_stores s WHERE s.onboarding_status = 'submitted'
      ORDER BY s.submitted_at LIMIT 20)
    UNION ALL
    (SELECT 'ride_unassigned', 'Courses', 'Course sans chauffeur', left(r.id::text,8),
            r.status::text, r.created_at,
            CASE WHEN r.created_at < v_now - interval '10 minutes' THEN 'critical' ELSE 'high' END,
            NULL, '/admin/live'
       FROM public.rides r
      WHERE r.status::text = 'pending' AND r.driver_id IS NULL
      ORDER BY r.created_at LIMIT 20)
    UNION ALL
    (SELECT 'mission_stuck', 'Missions', 'Mission bloquée', left(m.id::text,8),
            m.state::text, m.updated_at,
            CASE WHEN m.updated_at < v_now - interval '2 hours' THEN 'critical' ELSE 'high' END,
            nullif(m.issue_reason,''), '/admin/orders'
       FROM public.missions m
      WHERE m.state::text NOT IN ('delivered','failed')
        AND m.updated_at < v_now - interval '45 minutes'
      ORDER BY m.updated_at LIMIT 20)
    UNION ALL
    (SELECT 'repas_exception', 'Repas', 'Commande Repas en retard', left(o.id::text,8),
            o.state::text, o.updated_at, 'high',
            'Paiement: ' || coalesce(o.payment_status,'inconnu')
              || ' · Règlement: ' || coalesce(o.settlement_state,'—'),
            '/admin/repas'
       FROM public.food_orders o
      WHERE o.state::text IN ('placed','confirmed','preparing','ready','out_for_delivery')
        AND o.updated_at < v_now - interval '30 minutes'
      ORDER BY o.updated_at LIMIT 20)
    UNION ALL
    (SELECT 'repas_case', 'Repas', 'Cas opérationnel Repas', left(c.id::text,8),
            coalesce(c.reason_code, c.status), c.created_at,
            CASE WHEN c.severity IN ('high','critical') THEN 'critical' ELSE 'high' END,
            NULL, '/admin/repas'
       FROM public.repas_ops_cases c WHERE c.status = 'open'
      ORDER BY c.created_at LIMIT 20)
    UNION ALL
    (SELECT 'marche_exception', 'Marché', 'Commande Marché en retard', left(o.id::text,8),
            coalesce(o.fulfillment_state, o.status), o.updated_at, 'high',
            'Règlement réservation: ' || coalesce(o.reservation_settlement_kind,'—'),
            '/admin/marche/ops'
       FROM public.marche_orders o
      WHERE o.status NOT IN ('cancelled','completed','delivered','rejected','expired')
        AND o.updated_at < v_now - interval '45 minutes'
      ORDER BY o.updated_at LIMIT 20)
    UNION ALL
    (SELECT 'marche_case', 'Marché', 'Cas opérationnel Marché', left(c.id::text,8),
            coalesce(c.reason_code, c.case_type), c.opened_at,
            CASE WHEN c.severity IN ('high','critical') THEN 'critical' ELSE 'high' END,
            NULL, '/admin/marche/ops'
       FROM public.marche_ops_cases c WHERE c.status = 'open'
      ORDER BY c.opened_at LIMIT 20)
    UNION ALL
    (SELECT 'envoyer_stuck', 'Envoyer', 'Colis bloqué', coalesce(p.reference, left(p.id::text,8)),
            coalesce(p.package_status,'—'), p.updated_at,
            CASE WHEN coalesce(p.claim_state,'none') <> 'none' THEN 'critical' ELSE 'high' END,
            'Paiement: ' || coalesce(p.payment_status,'inconnu'), '/admin/orders'
       FROM public.package_deliveries p
      WHERE coalesce(p.package_status,'') NOT IN ('delivered','cancelled','failed')
        AND p.updated_at < v_now - interval '60 minutes'
      ORDER BY p.updated_at LIMIT 20)
    UNION ALL
    (SELECT 'support', 'Support', coalesce(i.title,'Ticket support'), left(i.id::text,8),
            i.status::text, i.created_at,
            CASE WHEN i.severity::text IN ('high','critical') THEN 'critical' ELSE 'normal' END,
            NULL, '/admin/support'
       FROM public.support_issues i
      WHERE i.status::text IN ('open','in_review','escalated','waiting_on_courier','waiting_on_merchant')
      ORDER BY i.created_at LIMIT 20)
    UNION ALL
    (SELECT 'map_duplicate', 'Carte', 'Doublon de lieu', left(d.id::text,8),
            d.status, d.created_at, 'normal', NULL, '/admin/map/duplicates'
       FROM public.map_place_duplicate_candidates d WHERE d.status = 'open'
      ORDER BY d.created_at LIMIT 10)
  )
  SELECT coalesce(jsonb_agg(x ORDER BY x.rank, x.since), '[]'::jsonb) INTO items
  FROM (
    SELECT q.*, CASE severity WHEN 'critical' THEN 0 WHEN 'high' THEN 1 ELSE 2 END rank
    FROM q ORDER BY rank, since LIMIT 60
  ) x;

  RETURN jsonb_build_object(
    'generated_at', v_now,
    'role', v_role,
    'mode', v_mode,
    'snapshot', snap,
    'attention', items
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.ops_command_overview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ops_command_overview() TO authenticated, service_role;