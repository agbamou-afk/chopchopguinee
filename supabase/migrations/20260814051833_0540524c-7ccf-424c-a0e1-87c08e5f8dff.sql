SELECT public.finance_policy_at('repas', now());

INSERT INTO public.finance_policies (
  mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
  collateral_mode, collateral_pct_bps, collateral_fixed_gnf, collateral_min_gnf,
  collateral_max_gnf, collateral_basis, require_collateral_before_offer,
  transaction_fee_bps, fee_basis, cash_funding_mode, cash_funding_pct_bps,
  cash_funding_max_gnf, cancel_before_dispatch_bps, cancel_after_dispatch_bps,
  cancel_basis, max_declared_value_gnf, claims_exposure_max_gnf,
  delivery_flat_fee_gnf, delivery_max_distance_km, pickup_platform_fee_bps, courier_payout_gnf,
  effective_from, enabled, note)
SELECT
  p.mission_type, p.commission_bps, p.fixed_commission_gnf, p.min_driver_balance_gnf,
  p.collateral_mode, p.collateral_pct_bps, p.collateral_fixed_gnf, p.collateral_min_gnf,
  p.collateral_max_gnf, p.collateral_basis, p.require_collateral_before_offer,
  p.transaction_fee_bps, p.fee_basis, p.cash_funding_mode, p.cash_funding_pct_bps,
  p.cash_funding_max_gnf, p.cancel_before_dispatch_bps, p.cancel_after_dispatch_bps,
  p.cancel_basis, p.max_declared_value_gnf, p.claims_exposure_max_gnf,
  15000, p.delivery_max_distance_km, p.pickup_platform_fee_bps, 15000,
  now(), true,
  'R5: align customer delivery price with courier payout so the cash rail stays operable; Chop Pay carries any future margin/promotion'
FROM public.finance_policy_at('repas', now()) p;

DELETE FROM public._qa_s13_results WHERE part BETWEEN 501 AND 506;
INSERT INTO public._qa_s13_results(part, result)
SELECT 501, jsonb_build_object('suite','node3_repas_r5',
  'pass', count(*) FILTER (WHERE ok), 'fail', count(*) FILTER (WHERE NOT ok),
  'failures', COALESCE(jsonb_agg(jsonb_build_object('section',section,'name',name,'detail',detail))
                        FILTER (WHERE NOT ok), '[]'::jsonb))
FROM public._qa_node3_repas_r5();

INSERT INTO public._qa_s13_results(part, result)
VALUES (502, jsonb_build_object('suite','node3_repas_r1_r4','result', public._qa_node3_repas_r1_r4())),
       (503, jsonb_build_object('suite','node3_repas_pickup','result', public._qa_node3_repas_pickup())),
       (504, jsonb_build_object('suite','node0_course','result', public._qa_node0_course())),
       (505, jsonb_build_object('suite','node1_bonbonna_full','result', public._qa_node1_bonbonna_full())),
       (506, jsonb_build_object('suite','node2_taxi_full','result', public._qa_node2_taxi_full()));