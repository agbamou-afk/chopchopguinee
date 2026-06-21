---
name: Ops Command Center — Stable
description: Lightweight admin landing console for mission launch operators with launch readiness, today counts, urgent queues, and role-gated quick links
type: milestone
---
Locked 2026-06-21.

- New route `/admin/ops` + sidebar entry "Centre opérations" (under Vue d'ensemble).
- Page: `src/pages/admin/OpsCommandCenter.tsx` — single screen with: launch readiness strip, today overview counts, urgent action queues, quick links, safety footer.
- All counts via `head: true` count queries against existing tables (rides, missions, food_orders, listing_interests, support_issues, driver_profiles, driver_locations, topup_requests, driver_cashout_requests, driver_applications, map_place_duplicate_candidates, merchant_stores, food_restaurants). Missing/forbidden tables resolve to `null` → "Non activé" badge.
- Polling: 60s interval, paused when tab hidden; manual refresh button.
- Role gating: Finance-only cards (top-ups, cashouts) hidden from Operations Admin. Master wallet balance card visible to God Admin only (via `wallet_get_master_balance` RPC; RLS still authoritative).
- Copy enforces operator-mediated discipline: "Ne pas créditer sans preuve", "Vérification opérateur uniquement", "Aucun virement automatique".
- No realtime, no charts, no maps rendered. No destructive actions on summary cards — all CTAs link to existing admin screens.
- No RLS weakened. No service_role usage.