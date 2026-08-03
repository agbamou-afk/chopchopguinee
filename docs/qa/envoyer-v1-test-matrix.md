# Envoyer v1 — QA matrix (A–AH)

Legend: **PASS** executed · **PASS(code)** verified by code/schema inspection
only · **YELLOW** not executed.

| # | Case | Result | Evidence |
|---|---|---|---|
| A | Envoyer tile present in Services (3rd) | PASS | Slice 2/3 UI |
| B | Composer opens from Services | PASS(code) | `ServicesView` → `EnvoyerComposer` |
| C | Composer opens from Home shortcut | PASS(code) | `Index.handleAction("parcel")` |
| D | Interim dialog removed | PASS | dead block deleted |
| E | Pickup/destination search works | PASS(code) | `LocationField` → `maps-search` |
| F | "Ma position" geolocation | PASS(code) | `useGeolocation` + reverse geocode |
| G | Recipient phone normalised (+224) | PASS(code) | `_normalize_guinea_phone` |
| H | Category selection + prohibited items notice | PASS(code) | `types.ts` |
| I | Quote is server-authoritative | PASS(code) | `package_delivery_quote` from `fare_settings` |
| J | Quote expiry (15 min) enforced | PASS(code) | quote table + RPC check |
| K | Checkout creates intent with `source_module='package'` | PASS(code) | constraint updated |
| L | Idempotency key prevents duplicate packages | PASS(code) | unique key in RPC |
| M | Sandbox finalisation creates mission + codes | YELLOW | not executed |
| N | Production/manual finalisation creates mission | **PASS** | DEF-015 closed; verified in a rolled-back transaction against the live schema |
| O | Codes visible to sender only | PASS(code) | `pds_sender_read` RLS is the only SELECT policy |
| P | Courier cannot read secrets | PASS(code) | no courier policy on `package_delivery_secrets` |
| Q | Courier view excludes codes | PASS(code) | `package_delivery_courier_view` payload |
| R | Courier view exposes recipient phone (policy-consistent) | PASS(code) | matches ride/food policy |
| S | Package missions hidden from non-capable drivers | PASS(code) | missions RLS capability predicate |
| T | Package mission accept by capable driver | YELLOW | no driver run |
| U | Pickup code verification | YELLOW | no driver run |
| V | Wrong pickup code rejected | PASS(code) | code comparison branch |
| W | Delivery code verification + completion | YELLOW | no driver run |
| X | Earnings credited only when not sandbox | PASS(code) | `IF NOT v_pkg.is_sandbox` guard |
| Y | Cancel before assignment → full refund request | PASS(code) | fee = 0 branch |
| Z | Cancel after assignment → 10 % fee | PASS(code) | fee branch |
| AA | Cancel after pickup → support dispute, no self refund | PASS(code) | `package_dispute` insert |
| AB | Cancel idempotent | PASS(code) | `cancelled_at` early return |
| AC | Refund row accepts `package` module | PASS(code) | constraint updated |
| AD | Activity shows package tracking | PASS(code) | `PackageDeliveries` in `OrdersView` |
| AE | `envoyer_enabled` OFF hides the module | PASS | flag row `false` |
| AF | No wallet balance exposure | PASS | `wallet_public_enabled` false; no balance read added |
| AG | Typecheck clean | PASS | `tsgo` exit 0 |
| AH | Production build clean | PASS | build green, PWA precache 128 entries |

## DEF-015 closure QA (2026-08-03)

Executed with `psql` inside `BEGIN … ROLLBACK`, real schema, production-shaped
(non-sandbox) fixtures, zero committed financial value.

| # | Case | Result | Evidence |
|---|---|---|---|
| 1 | Pending package intent has no mission before confirmation | PASS | `mission_id` NULL pre-confirm |
| 2 | Confirmation creates exactly one mission | PASS | 1 mission, 1 code pair |
| 3 | Replay returns same mission, no duplicates | PASS | missions 1, secrets 1, recon events unchanged at 2 |
| 4 | Amount mismatch rejected | PASS | `amount_mismatch`, no mission created |
| 5 | Wrong source module cannot call the finaliser | PASS | `not_a_package_intent` |
| 6 | Induced failure → `needs_review` + support issue, no fake success | PASS | state `needs_review`, 1 linked `payment_failed` issue, error recorded in metadata |
| 7 | No wallet/master-wallet/driver earning at confirmation | PASS | 0 wallet transactions |
| 8 | Sandbox package flow zero-delta | PASS(code) | `om_sandbox_finalize_authorized_intent` untouched; `confirm_payment_intent` still rejects sandbox intents |
| 9 | Non-package confirmation regresses cleanly | PASS | Repas intent confirms to `confirmed` |
| 10 | Real Orange Money money movement | YELLOW | not executed — no real-money run performed |
