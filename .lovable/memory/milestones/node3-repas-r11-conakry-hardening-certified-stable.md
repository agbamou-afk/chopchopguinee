# Milestone: node3-repas-r11-conakry-hardening-certified-stable

- HEAD at certification: `02e8dfbfd183a39e7f11840c34724b58b8403061`
- Date: 2026-08-14 (UTC)
- Verdict: **LOCKED / CERTIFIED**

## Scope of this closeout
Narrow R11 closeout correction only. No re-scope, no feature activation, no deployment.

### Change summary (1 seam, QA tooling only)
- `public._qa_node3_repas_r1_r4_fxcore()` asserted anon EXECUTE (`B0.1`) against the obsolete
  exact regprocedure string
  `public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text)`,
  which aborted the whole R1–R4 suite after R11 extended the canonical signature.
- Rewrote only that reference to the current canonical 12-arg identity:
  `(uuid,jsonb,text,text,uuid,text,double precision,double precision,text,text,text,text)`.
- No production wrapper/overload added — R11 P0.7 still proves exactly one order-create signature.
- Repo-wide + DB-wide scan for the same stale exact-regprocedure reference: only
  `_qa_node3_repas_r1_r4_fxcore` was affected (`_qa_node3_repas_r11_conakry_hardening_fxcore`
  already used the 12-arg identity). Historic migration files left untouched by design.
- Zero changes to economics, lifecycle, auth, RLS, feature flags, or R1–R10 product behavior.

## Final regression board (all re-run after the LAST edit)
| Suite | Result |
|---|---|
| R11 Conakry hardening | 116 / 0 failed |
| R10 operations | 134 / 0 |
| R9 recovery flows | 68 / 0 |
| R8 discovery truth | 202 / 0 |
| R7 tracking + receipt | 203 / 0 |
| R6 custody | 171 / 0 |
| R5 static | 71 / 0 |
| R5 runtime | 91 / 0 |
| R4.5 Retrait / pickup | 64 / 0 |
| R1–R4 canonical | **148 / 0** (was aborting) |
| Node 0 Course | 34 / 0 |
| Node 1 Bonbonna | 78 / 0 |
| Node 2 Taxi | 97 / 0 |
| Slice 13 (run1–run7: 18+32+54+98+115+87+103) | 507 / 0 |

Client gates:
- Vitest: 12 files / **71 passed**
- `tsgo --noEmit -p tsconfig.app.json`: exit 0
- Production build: PASS; PWA `generateSW` — 134 precache entries, `dist/sw.js` generated
- `git status`: clean working tree

## Activation posture (unchanged)
- No feature flags toggled; no rollout, no deployment performed.
- R11 hard boundaries preserved (destination snapshot immutability, server-authoritative
  location quality, durable destination draft, bounded low-data tracking fallback).

## Limitations
- `repas_order_create` remains a single canonical signature; the three R11 destination
  parameters are trailing DEFAULT NULL, so 9-arg positional legacy calls stay compatible.
- Historic migration SQL files still contain the pre-R11 signature string as immutable history.
