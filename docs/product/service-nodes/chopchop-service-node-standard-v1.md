# CHOPCHOP Service Node Standard v1

Status: FROZEN v1 (Node 0 output)
Derived from: `docs/product/service-nodes/course-golden-reference-audit.md`
Applies to: every CHOPCHOP service node (Course, Bonbonna, Repas, Marché, Envoyer, and any future node).

A **service node** is a complete customer-visible service: discovery through
financial finalization, receipt, recovery and operational support — including
its supply side when a second human role is required.

A node is not "done" because it compiles or because a happy path renders.
The v1 test is:

> Can a real customer discover, request, understand, complete, pay for, recover
> from failure in, and return to this service — while the supply side can safely
> fulfil it and Operations can support it — without hidden manual improvisation?

---

## 0. Evidence grades

| Grade | Meaning |
|---|---|
| **LIVE-PROVEN** | Executed against live production/staging data this cycle with observed result. |
| **REGRESSION-PROVEN** | Covered by an identifiable automated regression sweep (e.g. Slice 13 `_qa_s13_run*`) that passed. |
| **CODE-VERIFIED** | Read in source/DB definition; logic is correct by inspection but not executed this cycle. |
| **VISUAL-YELLOW** | Depends on an authenticated visual session that was unavailable; UI truth unconfirmed. |
| **FIELD-YELLOW** | Depends on real Conakry field/network/device behaviour not yet observed. |
| **GAP** | Not implemented, or implemented as a facade. |

Rules: a facade never scores above GAP. Historical regression evidence must be
labelled with its slice/batch. Never upgrade CODE-VERIFIED to LIVE-PROVEN by assertion.

## 0b. Node verdicts

| Verdict | Definition |
|---|---|
| **REFERENCE** | Meets every hard exit gate, no P0/P1 gaps, and is safe to copy. |
| **LAUNCH-READY** | Meets every hard exit gate; only P2/P3 items open. |
| **READY WITH YELLOWS** | Gates met in code/regression, blocked only on VISUAL-YELLOW / FIELD-YELLOW. |
| **HOLD** | One or more hard exit gates fail. |
| **NOT SUFFICIENTLY BUILT** | Lifecycle materially incomplete. |

---

## 1. The 8 mandatory lenses

### Lens 1 — Discovery & comprehension
**Questions**: Is the node reachable from the primary shell in <=2 taps? Is it
flag-gated, and does the OFF state say something honest? Does a first-time user
understand what they get, roughly what it costs, and how long it takes, before
committing?
**Required evidence**: entry-point file(s) + flag key; empty/unavailable state.
**Hard blockers**: unreachable node; flag OFF that renders a dead or lying screen;
no pre-commitment price/economic preview where money is involved.
**Acceptable YELLOWs**: VISUAL-YELLOW on layout; copy polish pending.
**Optional/future**: onboarding tour, promo merchandising, search ranking.

### Lens 2 — Transaction / runtime completeness
**Questions**: Does every state in the node's lifecycle exist and transition
server-side? Is every transition an authorised RPC rather than a client table
write? Is there a terminal state for success, cancellation and failure?
**Required evidence**: state list + RPC per transition + RLS posture on the
runtime table.
**Hard blockers**: client-writable runtime state; a state with no exit; a UI
state with no server counterpart.
**Acceptable YELLOWs**: FIELD-YELLOW on realtime latency.
**Optional/future**: state animation, ETA refinement.

### Lens 3 — Supply-side fulfilment (where a second role exists)
**Questions**: Who fulfils, and how are they made eligible? How do they learn
about the job, what economics do they see, and how do they accept, execute,
verify and complete it? What happens on abandonment?
**Required evidence**: eligibility check, job surface, accept/decline path,
completion authority check.
**Hard blockers**: anyone can complete a job that is not theirs; no eligibility
check; no abandonment path.
**Acceptable YELLOWs**: FIELD-YELLOW on real courier/merchant behaviour.
**Optional/future**: batching, heatmaps, incentives.

### Lens 4 — Financial integration
**Questions**: Is every displayed amount derived from server truth? Is the
economic snapshot frozen at commitment? Are capture, commission, collateral and
settlement handled by the locked Slice 0–13 primitives? Is there any client-side
financial arithmetic?
**Required evidence**: policy snapshot source, capture/settlement RPC names,
ledger/audit rows produced.
**Hard blockers**: client-computed money that is then persisted; silent partial
settlement; success UI on a failed money step; bypass of the locked primitives.
**Acceptable YELLOWs**: rail deliberately flag-OFF under staged activation;
no live provider receipt yet.
**Optional/future**: split payment, tipping, invoicing.

### Lens 5 — Failure / recovery
**Questions**: What happens on duplicate submit, duplicate accept, duplicate
completion, expired job, wrong verification secret, cancellation on each side
and at each stage, half-failed money step, offline, app restart?
**Required evidence**: a failure/recovery matrix like Course section E.
**Hard blockers**: any non-idempotent money-moving call; a half-failed money
step with no compensating action and no support-issue trail; a state a user can
get stuck in with no exit.
**Acceptable YELLOWs**: rare provider-timeout paths only code-verified.
**Optional/future**: automatic retry queues, self-serve refunds.

### Lens 6 — Operations / support / admin
**Questions**: Can Ops see live and historical instances of this node, act on
them, see the money, see disputes, and trace who did what?
**Required evidence**: admin surface(s), audit action names, support issue type,
feature flag(s) that materially gate the node.
**Hard blockers**: no admin visibility; no audit trail on money or state
override; no support intake.
**Acceptable YELLOWs**: read-only admin view pending a bulk action tool.
**Optional/future**: SLA dashboards, automated alerting.

### Lens 7 — UX / environmental resilience
**Questions**: Does it work at 390x844, on low data, with intermittent network,
with location denied, with the map/route provider failing, and after a cold
restart mid-mission?
**Required evidence**: degradation path per dependency; permission-denied state;
restore-from-server-state path.
**Hard blockers**: silent fake data used in place of a failed dependency
(e.g. a fallback coordinate used as a real pickup); unrecoverable mid-mission
restart; blocking full-screen spinner with no timeout.
**Acceptable YELLOWs**: VISUAL-YELLOW on unaudited breakpoints; FIELD-YELLOW on
real network behaviour.
**Optional/future**: full offline mode, background sync.

### Lens 8 — Engagement / reuse sufficiency
**Questions**: Why would a user come back? Does the node leave a truthful trace
(activity, receipt), give predictable pricing/status, and offer trust/safety
recall (saved places, ratings, support history)?
**Required evidence**: activity/receipt surface, any reuse accelerator that is
actually DB-backed.
**Hard blockers**: no receipt/history; a facade engagement feature presented as
functional (hardcoded promos, fake loyalty, fake ratings).
**Acceptable YELLOWs**: thin engagement layer, documented as such.
**Optional/future**: promos, referrals, loyalty, favourites, recommendations —
these must NEVER block a launch verdict.

---

## 2. Standard cross-service states & language

**UNIVERSAL STANDARD** — every node must map each of these to a real server state
or explicitly declare it Not Applicable with a reason:

| Canonical state | Meaning |
|---|---|
| `discoverable` | Node is reachable and honestly described. |
| `economic_preview` | Quote / price / earning preview before commitment. |
| `confirmation` | Explicit user commitment. |
| `pending` | Committed, awaiting counterpart. |
| `assigned` | Counterpart bound (driver, merchant, courier). |
| `preparation` | Optional stage where the supply side prepares/collects. |
| `in_progress` | Value is in motion / in custody. |
| `completed` | Service delivered. |
| `cancelled_failed_disputed` | Terminal non-success, with responsibility attributed. |
| `financial_result` | Authoritative money outcome (captured / settled / debt / refund). |
| `receipt_activity` | Truthful, retrievable record. |
| `support_recovery` | Human escalation path from any state. |

**SERVICE-SPECIFIC EXTENSIONS** — allowed, never universal:

| Extension | Nodes | Note |
|---|---|---|
| Pickup secret (code/QR) | Course, Bonbonna, Envoyer | Custody handover proof. |
| Offer fan-out + expiry | Course, Bonbonna, Envoyer | Dispatch model. |
| Presence toggle | Driver-supplied nodes | Not for merchants. |
| Opening hours / prep time | Repas, Marché | Not for rides. |
| Cart / catalogue / bargaining | Repas, Marché | Not for rides. |
| Declared value + claims | Envoyer | Not for rides. |
| Turn-by-turn navigation | Course, Bonbonna, delivery legs | Not for pickup-only orders. |

Forbidden: forcing ride vocabulary (fare, pickup code, presence) onto commerce
nodes, or forcing catalogue vocabulary onto mobility nodes.

---

## 3. Hard exit gates for `*-service-node-stable`

A node may be locked only when ALL of the following hold:

1. No open P0/P1 runtime defect.
2. Full customer lifecycle implemented across the universal states.
3. Full supply-side lifecycle implemented where a second role exists.
4. Finance wired to the locked Slice 0–13 authoritative architecture; **no
   client-side financial reconstruction** of any persisted amount.
5. Duplicate/replay safety on every money-moving and state-moving call.
6. Cancellation + recovery path with responsibility attribution.
7. Support and admin visibility, with audit provenance.
8. Auth/RLS isolation: runtime tables not client-writable; cross-tenant reads impossible.
9. Mobile (390x844), low-data, offline and error/permission states handled.
10. Receipts/history truthful and reconcilable with the ledger.
11. No fake success states anywhere.
12. Typecheck, tests and build green.
13. Known YELLOWs documented explicitly in the node audit.
14. One real or controlled two-actor / two-device smoke where the node needs
    multiple human roles — if blocked by field availability, record FIELD-YELLOW,
    never PASS.

Gate 4, 5, 11 and 14 are non-negotiable; a failure there forces HOLD.

---

## 4. Service Node Scorecard (template)

| Lens | Grade | Evidence | Blockers |
|---|---|---|---|
| Runtime | | | |
| Finance | | | |
| Customer UX | | | |
| Supply UX | | | |
| Recovery | | | |
| Ops | | | |
| Security | | | |
| Environment | | | |
| Engagement | | | |
| Field QA | | | |
| **Verdict** | | | |

### Filled example — Node 0 Course (evidence from the Course audit only)

| Lens | Grade | Evidence | Blockers |
|---|---|---|---|
| Runtime | REGRESSION-PROVEN | `ride_create/accept/set_phase/confirm_pickup/start/complete/cancel`; `rides` SELECT-only RLS | — |
| Finance | REGRESSION-PROVEN with GAP | Slice 13 507/507; snapshot commission; `SETTLEMENT_REQUIRED_INSUFFICIENT_HOLD` | CRS-G1 client fare, CRS-G2 client hold |
| Customer UX | CODE-VERIFIED + VISUAL-YELLOW | RideBooking -> RealtimeTripScreen -> receipt | CRS-G3 no payment selector |
| Supply UX | CODE-VERIFIED | offers, accept, navigation, arrival, completion, earnings | CRS-G9 weak-GPS not surfaced |
| Recovery | REGRESSION-PROVEN | duplicate accept/complete, stale offer, wrong code, cancel stages, compensating release | CRS-G6 no driver no-show flow |
| Ops | CODE-VERIFIED | OrdersAdmin, LiveOps, DriversAdmin, SupportAdmin, AuditAdmin, `ride.settled` | — |
| Security | REGRESSION-PROVEN | SECURITY DEFINER RPCs, `ONLY_ASSIGNED_DRIVER_CAN_COMPLETE`, customer-only pickup confirm | — |
| Environment | CODE-VERIFIED + FIELD-YELLOW | polling fallback, low-data mode, no fake pickup coordinate, session restore | CRS-G5 no native push |
| Engagement | PARTIAL | saved places, ratings, activity/receipts real | CRS-G7 recents, CRS-G8 fake promo carousel |
| Field QA | FIELD-YELLOW | no live two-device Conakry run this cycle | Gate 14 unmet |
| **Verdict** | **REFERENCE WITH GAPS** | Benchmark for all nodes; CRS-G1/G2/G3 must be closed before Course itself can be locked `LAUNCH-READY` | — |

Bonbonna, Repas, Marché and Envoyer are **not scored** here; they are future audits.

---

## 5. Execution order (frozen)

| Node | Scope | Status |
|---|---|---|
| Node 0 | Course — Golden Reference | DONE (this document) |
| Node 1 | Bonbonna | NOT STARTED |
| Node 2 | Repas | NOT STARTED |
| Node 3 | Marché | NOT STARTED |
| Node 4 | Envoyer | NOT STARTED |
| Node 5 | Cross-Service UX / Engagement | NOT STARTED |
| Node 6 | Release Blocker Closure | NOT STARTED |
| Node 7 | Android Release Candidate | NOT STARTED |

Node 1 must not begin until explicitly instructed.
