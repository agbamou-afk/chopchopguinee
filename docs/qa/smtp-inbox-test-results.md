# SMTP Inbox Test Results (`web-rc-1`)

**Gate status: YELLOW — NOT GREEN. No live mailbox delivery has been observed.**

## System state (verified)

| Item | Value |
|---|---|
| Architecture | Lovable-managed `auth-email-hook` → `auth_emails` pgmq queue → `process-email-queue` |
| Sender domain | `notify.chopchopguinee.com` (delegated) |
| Health RPC | `email_get_health()` present |
| Ops chip | Ops Command Center readiness strip, 60s polling |
| `email_send_log` rows | 8 total (4 `sent`, 4 `pending`), last activity 2026-06-06 |

**Update (web-rc-1, DEF-013):** auto-confirm is ON, so GoTrue emits no `signup`
confirmation mail — that is why the log had been silent since 2026-06-06. A
`welcome` app email now fires once per new account (key `welcome-<userId>`),
which is the trigger Operations should use to execute the matrix below.

Configuration is not delivery. Eight historic rows with a stale timestamp and a
`pending` remainder are **not** evidence that production mail reaches inboxes.

## Required matrix — to be completed by Operations

| Message | Gmail | Yahoo | iCloud | Orange (or closest operational) |
|---|---|---|---|---|
| signup verification (if enabled) | | | | |
| password recovery | | | | |
| staff temporary password / forced change | | | | |
| other supported transactional/auth email | | | | |

For **every** cell record:

1. sender display name
2. From address
3. Reply-To
4. subject line
5. branding correct (CHOP CHOP, not template default)
6. mobile rendering at 390×844
7. link opens `https://chopchopguinee.com` (production domain, not preview)
8. link not expired at first use
9. inbox vs spam/junk placement
10. delivery latency (enqueue → receipt)
11. duplicate sends: none
12. `email_send_log` row transitions `pending → sent`
13. Cloud → Emails status at time of test
14. `email_get_health()` output
15. screenshot reference

## Exit condition

Mark GREEN only when real delivery is observed for the required inboxes, or when
the release owner signs a documented equivalent below.

| Role | Name | Signature | Date |
|---|---|---|---|
| Operations (executed tests) | | | |
| Release owner (accepts result) | | | |

Only after this table is signed may the Ops chip be treated as `Prêt` for
release purposes.
