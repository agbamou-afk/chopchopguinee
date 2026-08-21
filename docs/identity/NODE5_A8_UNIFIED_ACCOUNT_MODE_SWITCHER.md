# Node 5 · A8 — Unified Account / Mode Switcher

Status: **IMPLEMENTED / CERTIFIED**
Suite: `_qa_node5_identity_a8` — **93 / 93 PASS**
Board at close: **5,301 assertions · 0 failed**

## Law

Mode is **presentation only**. Switching workspace changes what the app shows and
nothing else: no identity claim, no capability, no role, no ownership, no approval
state, no money movement.

Lawful mode sets are derived server-side from the A2/A3 active professional identity:

| Active professional identity | Available modes        |
| ---------------------------- | ---------------------- |
| none                         | `client`               |
| driver                       | `client`, `driver`     |
| merchant                     | `client`, `merchant`   |

Client is universal — every account keeps it. No account can ever hold all three.
Mode availability follows the professional **class**, not approval status: a pending
driver or a submitted (unapproved) store still sees its workspace; the workspace
itself remains gated by the A6/A7 operational primitives.

## Server surface

- `account_available_modes(uuid)` — internal derivation (service_role only).
- `account_mode_context()` — caller-scoped read: professional type, available modes,
  stored preference, and **effective mode** (preference validated against the lane).
- `account_mode_set(text)` — validated write. Unknown values refuse (`INVALID_MODE`);
  an unlawful professional request deterministically degrades to `client` and reports
  `refused: true`.
- `_account_mode_preference_guard` trigger on `user_preferences` — defense in depth:
  a direct/tampered write of an unlawful professional preference is neutralised to
  `client`.

Released lane → stale professional preference stops resolving immediately. Reclaiming
the opposite class never resurrects the old workspace; historical identity rows are
preserved, never erased.

## Client surface

- `src/lib/identity/accountMode.ts` — RPC wrappers and normalisation.
- `src/hooks/useAccountMode.ts` — server-authoritative workspace context.
- `src/components/identity/ModeSwitcher.tsx` — the single canonical switcher; renders
  only server-approved workspaces and hides itself for single-workspace accounts.
- `src/hooks/useAppMode.ts` — persistence now routes through `account_mode_set`;
  the loaded mode is the server's effective mode, and a refused switch realigns
  local state. Unlawful local overrides are cleared on the first server read.
- `src/lib/merchantRouting.ts` — `persistMerchantAppMode` uses the validated RPC
  instead of a direct preference write.

## Certification highlights

- Surface shape, SECURITY DEFINER + pinned `search_path`, grant posture (A1–A13).
- Derivation matrix incl. admin-role-only, released lane, pending driver, submitted store (B1–B12).
- Caller context incl. signed-out refusal (C1–C6).
- Preference validation incl. direct-table tampering (D1–D16).
- Release + opposite-class reclaim with stale preference (E1–E8).
- No canonical authority function or RLS policy reads UI mode (F1–F9).
- Finance non-interference: no wallet, transaction, ledger, payable or payout effect (G1–G6).
- Customer universality (H1–H5) and full residue/baseline restoration (I1–I18).
