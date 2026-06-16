---
name: CHOP Map — Duplicate Detection + Merge Queue Stable
description: Map Phase 2C locked. Admin-only duplicate queue, scored candidates, controlled merge preserves merchant + driver-report links, soft-deactivates source, no auto-merge, no hard delete.
type: feature
---

# chopmap-duplicate-detection-merge-queue-stable

Locked 2026-06-16. Map Phase 2C complete.

## Schema
- `map_place_duplicate_candidates` (admin-only RLS, unique on normalized pair)
- Indexes on `map_places (lat,lng)`, `lower(name)`, `verification_status`

## RPCs (SECURITY DEFINER, admin-gated)
- `map_detect_place_duplicates(p_place_id uuid, p_radius_meters int=150)` — scores by distance + name eq + category + commune; inserts candidates idempotently
- `map_merge_places(source, target, candidate?, reason?)` → jsonb {moved_stores, moved_reports}
  - source: `active=false`, `verification_status='duplicate'`, `duplicate_of=target`
  - target: aliases append source.name, notes filled with COALESCE only (no overwrite)
  - `merchant_stores.map_place_id` and `map_driver_reports.place_id` re-pointed to target
  - candidate → `status='merged'`
  - audit_logs row written
- `map_mark_place_duplicate(...)` — soft flag without moving refs

## Admin UI
- `/admin/map/duplicates` (`MapDuplicatesAdmin.tsx`)
- Scan trigger, status filter, side-by-side place summaries, explicit "Fusionner B → A" / "A → B" buttons with confirm dialog (merge direction made explicit)

## Smoke test results (DB-level, 2026-06-16)
- Seeded 2 nearby similar places → scan inserted 1 candidate, score 55, reasons: nearby_coordinates, same_category, same_commune
- Dismiss path leaves both places untouched ✓
- Merge effects verified: source deactivated + flagged duplicate_of target, target aliases extended, merchant_store moved, driver_report moved, candidate=merged ✓
- RLS on `map_place_duplicate_candidates`: admin-only read+write ✓
- Inactive duplicate source filtered from public map (active=false) ✓
- Build clean

## Known limits (acceptable)
- `similar_name` reason only fires on exact lowercase equality (no trigram). Future enhancement if false-negatives observed.
- Duplicate scan capped at 200 base rows per pass; rerun for full coverage.