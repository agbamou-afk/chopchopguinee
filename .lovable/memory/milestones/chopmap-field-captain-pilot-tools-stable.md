---
name: CHOP Map — Field Captain / Pilot Tools (Stable)
description: Phase 2D locked 2026-06-16 — field pilots, captain/agent assignments, mobile visit form, daily reports, admin pilot dashboard
type: feature
---

# chopmap-field-captain-pilot-tools-stable

Locked 2026-06-16.

## Schema
- `field_pilots` — pilot sprints with status enum (planned/active/paused/completed/cancelled).
- `field_assignments` — per-pilot user assignments (field_captain / field_agent / verifier), optional zone.
- `field_merchant_visits` — visits with interest_level, visit_status (visited/submitted/duplicate_possible/needs_review/converted/rejected), optional lat/lng, links to `map_places` and `merchant_stores`.
- `field_daily_reports` — per-agent per-day report with transport flags + review workflow.

## RPC
- `field_submit_visit(...)` — SECURITY DEFINER, requires `is_assigned_to_pilot`. Creates a `submitted` map_place (confidence 35) when lat/lng provided. Flags `duplicate_possible` when another active place within ~120m exists. Never sets trusted/admin_verified.
- Helpers: `is_assigned_to_pilot`, `is_field_captain_of_pilot`.

## RLS
- Admins (admin/god_admin/operations_admin) manage all field tables.
- Agents read/insert/update only their own visits and reports; can't review own report.
- Captains read all pilot data and review (update) reports they don't own.
- No anon access. No public exposure.
- Field agents have no write path on `map_places` other than RPC (always `submitted`).

## UI
- `/admin/field/pilots` — create pilots, assign captains/agents/zones, summary cards, visit list, report review.
- `/field/captain` — captain view: assignments, today's visits, today's reports, review actions.
- `/field/visit` — mobile-first agent form: visit submission + daily report.
- Sidebar entry "Pilot terrain" under Carte group.

## Out of scope (intentional)
- No payroll, no live GPS, no public exposure.
- Transport flags recorded only — no wallet movement.
- Field agents cannot approve merchants or trust map_places.

## Smoke test 2026-06-16
- Pilot "CHOPCHOP Marchands — Pilote 30 jours" created.
- Admin assigned as captain + agent on Madina zone.
- Visit "Boutique Test Madina" recorded, linked submitted map_place at 9.5092,-13.7122 (confidence 35).
- Daily report submitted (5/4/2/0, transport matin ✓, retour ✗).
- RLS enforced: anon blocked, non-assigned users blocked by `is_assigned_to_pilot`.
- Build clean.

## Known follow-ups
- Optional map-tile visualization of pilot coverage (list view used today).
- Visit-to-merchant linking RPC exists in lib but no dedicated admin button yet (uses update).
- 385 pre-existing linter warnings unchanged by this phase (search_path on legacy fns, extension in public, etc.).