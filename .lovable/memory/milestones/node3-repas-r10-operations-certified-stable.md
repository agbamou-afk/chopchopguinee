---
name: Node 3 Repas R10 — Operations / Core-Team Intervention
description: Certified append-only Repas ops case + intervention control plane; queue, timeline, custody reissue, finance-gated cancellation; 134/134 PASS
type: feature
---

# node3-repas-r10-operations-certified-stable

- Data model: `repas_ops_cases` (open/escalated/resolved) + `repas_ops_events`
  (append-only, trigger-enforced). Both tables are RPC-only: all privileges
  revoked from `anon` and `authenticated`, `service_role` retained.
- Read models: `repas_ops_queue(filter,search,limit)` derives attention flags
  from canonical order/mission/payment/custody truth. Age is measured from
  `created_at` (total) and `updated_at` (current step) — the generic touch
  trigger otherwise masks stuck orders. No custody secret is ever returned.
- `repas_ops_case_detail(order_id)` merges order milestones with ops
  interventions and returns server-computed `allowed_actions`.
- `repas_ops_command(...)` is the single idempotent intervention plane:
  open_case / add_note / contact_* / escalate / resolve / reopen /
  custody_reissue / cancel_order / dispute_resolve. Exact replay returns the
  prior canonical result and moves zero additional value.
- Economics route only through certified engines (`admin_chop_pay_cancel`,
  `admin_chop_pay_dispute_resolve`, `admin_cash_order_dispute_resolve`).
  `operations_admin` is refused finance actions; god/finance tier required.
- Custody reissue invalidates the old code atomically and never reveals the
  new one to the operator; it changes no order or custody state.
- Deliberate fail-closed: courier reassignment is unavailable
  (`NO_CERTIFIED_REASSIGNMENT_PRIMITIVE`); merchant rejection cannot be
  rewound (`ACTION_NOT_REVERSIBLE`); no mark-delivered path exists.
- Known limitation: the pre-existing `Admins manage orders` policy on
  `food_orders` still allows `app_role = admin` direct CRUD; lifecycle
  bypass is nonetheless blocked by the certified state triggers (proved).
- QA: `public._qa_node3_repas_r10_operations()` — **134/134 PASS**, rollback
  clean, zero fixture residue, master wallet and feature flags unchanged.
