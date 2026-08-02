## Audit only — no code changed

### A. New-account email — exact missing link

Two separate gaps, neither is an SMTP failure.

1. **Email confirmation is disabled at the auth layer.** Every account in the database has `email_confirmed_at` equal to `created_at` and `confirmation_sent_at = NULL` — including the fresh test account created 2026-08-02 21:16 UTC. Auto-confirm is ON, so the `signup` confirmation email is never generated. This is why `email_send_log` shows zero activity since 2026-06-06 (8 historic rows only).
2. **No welcome email is wired.** A `welcome` template exists and is registered, and `NotificationService.welcome()` exists as a wrapper around `send-transactional-email` — but nothing ever calls it. The DB trigger on user creation only inserts profile/wallet/role rows. Zero references to `send-transactional-email` anywhere in `supabase/functions/`.

**SMTP itself is healthy:** `notify.chopchopguinee.com` is verified, NS-delegated to Lovable nameservers, project email setup complete, queue healthy. Auth hook is on the correct queue-based pattern with all six auth templates mapped. No live delivery is claimed — no send has been attempted since June.

**Registration is email-first**, deliberately: email + password only, phone collected as profile metadata, phone-as-email explicitly rejected (pilot restriction).

**Safest launch behavior** matches what you described and requires no security tradeoff, because auto-confirm is already the current posture:
- Keep account creation and login non-blocking (leave auto-confirm ON for now).
- Add a welcome email fired once after profile creation, using the existing registered `welcome` template.
- Optionally surface a soft, dismissible "confirm your email" nudge later — turning auto-confirm OFF must not happen until a live inbox delivery is actually observed, otherwise new signups get locked out.

### B. Repas `/admin/repas/payments` — root cause

The error is in the database function `admin_preview_repas_payment_settlement`, called from `src/pages/admin/RepasPayments.tsx`. Inside it, alias `li` is the `latest_intent` CTE over `payment_intents` — and `payment_intents` has no `merchant_store_id` column (verified live: the only store column is `related_store_id`). Three lines reference `li.merchant_store_id`.

The sibling Marché function was already corrected to use `li.related_store_id`; the Repas copy was never patched. Correct relationship: the store link for Repas lives on `food_restaurants.merchant_store_id`, with `payment_intents.related_store_id` as fallback.

**Pipeline completeness:** ownership, order creation, incoming orders, accept, preparing, ready, courier handoff (mission created at order time), trusted completion (`repas_complete_order`, DB-trigger-guarded), payment intent creation, capture and settlement are all implemented. Gaps: the admin settlement preview is broken (this bug); there is no restaurant "reject" transition and no dedicated cancel RPC (customer cancel is a raw RLS update while `placed`/`confirmed`); refunds exist only through the sandbox/OM refund path, not a merchant-initiated refund.

### C. Bottom nav / Services architecture

Current client tabs are Accueil, Activité, Compte (the Wallet tab is dropped under the Orange-Money-first flag), plus a permanent center FAB that opens one universal QR scanner whose result is routed by payload prefix (ride pickup / payment / merchant code). There is **no Services screen** — the closest artefact is `PrimaryActionGrid`, a 4-tile grid embedded in the home view (Wallet/OM, Course, Repas, Marché). Merchant and Driver are separate surfaces, not reachable from client nav. Navigation is a state machine in `Index.tsx`, not routes.

**Recommendation:** yes — move the scanner out of the primary tab slot. It is a situational action, not a destination, and it currently occupies the most valuable position in the bar. Target: Accueil, Services, Activité, Compte, with Services as a full grid (Course moto, Course toktok, Repas, Marché, Orange Money, Envoyer, Scanner, Devenir marchand, Devenir chauffeur, Aide). Scanner becomes a tile in Services plus an optional small header action on Home. This is a **product change**, not a defect.

### D. Envoyer / colis — current status

**Partially implemented — schema and presentation layer only, no creation path.**

Present: `mission_type` enum value `package_delivery`, matching driver capability, capability→mission-type mapping, full mission identity (Package icon, Expéditeur/Destinataire labels, `accent-envoyer` token), a complete `PACKAGE_PIPELINE` of driver states, `package_dispute` support type, and fully type-agnostic lifecycle RPCs that would work today.

Absent: no RPC or app code ever inserts a `package_delivery` mission; no driver ever receives the `package_delivery` capability (default is `rides_moto` only, and no admin or apply UI grants it); no route or composer screen. The one "Envoyer un colis" action explicitly falls through to the moto ride booking flow, with an in-code comment saying so.

**Narrowest safe path under the RC freeze:** do not reopen scope now. Keep the existing moto-coursier fallback, and in the new Services grid present Envoyer honestly — either as the moto-coursier flow labelled as such, or as a "Bientôt" tile. A real Envoyer module (sender/recipient composer, parcel pricing, capability grant UI, dedicated mission creation) is a post-RC phase of its own.

### E. Severity

| Item | Severity | Rationale |
|---|---|---|
| Repas admin settlement preview crash | **P1** | Admin-only page, hard error, blocks Repas settlement operations; no customer-facing impact and no financial corruption |
| No welcome email after signup | **P2** | Missing courtesy communication; account creation and login work |
| Auto-confirm ON / no confirmation email | **P2 (accepted posture)** | Deliberate today; becomes P1 only if you decide confirmation must block login before launch |
| Bottom nav → Services | **Product change** | Not a defect |
| Envoyer | **Product change / deferred scope** | Not a defect; current fallback is functional but under-labelled |

### F. Recommended execution order

1. Fix `admin_preview_repas_payment_settlement` — one `CREATE OR REPLACE` migration replacing `li.merchant_store_id` with `COALESCE(fr.merchant_store_id, li.related_store_id)`. Verify the page loads. Log as a new defect in the RC register.
2. Wire the welcome email: call the existing `welcome` template once after profile creation, with an idempotency key so retries don't duplicate. This produces the first real send since June and finally exercises the live pipeline — the first genuine data point for the SMTP gate.
3. Bottom nav restructure + Services grid (Home / Services / Activity / Account, scanner relocated into Services).
4. Envoyer decision: keep the honest moto-coursier fallback in Services for RC; schedule the real module post-RC.

### G. Do these block `web-production-release-candidate-stable`?

- **Item 2 (Repas) blocks it** — a hard 500-class error on a shipped admin page cannot be inside a locked RC baseline. It is a small, contained fix.
- **Item 1 (email)** does not strictly block the lock, but the SMTP gate is already YELLOW and will stay YELLOW regardless; wiring the welcome email is the cheapest way to generate the delivery evidence that gate needs.
- **Items 3 and 4 are product changes and must not enter the RC freeze.** They belong to a post-RC phase (proposed lock: `client-shell-services-navigation-stable`). Folding them in now would invalidate the mission matrix that has already been executed against this baseline.

Recommendation: fix Repas, wire the welcome email, re-run the affected admin and signup checks, then lock the RC on the remaining external-evidence gates. Ship nav and Envoyer immediately after, as their own phase.
