# SMTP / Auth Email — Production Launch Readiness

**Status:** YELLOW — CODE + DOMAIN READY / NEEDS LIVE INBOX TESTS.
Sender domain `notify.chopchopguinee.com` is verified and delegated to Lovable
nameservers (`ns3.lovable.cloud`, `ns4.lovable.cloud`). Auth email pipeline
(`auth-email-hook` + queue) is deployed. Remaining work is live-inbox
verification and monitoring.

CHOPCHOP auth emails (signup confirmation, password reset, magic links) route through the
Lovable-managed auth email pipeline (`auth-email-hook`). No SMTP credentials are stored in
`src/` or in any client bundle.

## Ops checklist — must be GREEN before launch

- [x] Sender domain configured (`notify.chopchopguinee.com`)
- [x] DNS records verified (NS delegation green in Cloud → Emails)
- [x] Branded auth templates deployed (signup, recovery, magic-link, invite, email-change, reauthentication)
- [x] `auth-email-hook` deployed on latest queue-based pattern
- [x] Ops Command Center "Emails auth" chip wired to real health probe (`email_get_health` RPC)
- [ ] Sender name set to **CHOPCHOP**
- [ ] Sender email set (e.g. `no-reply@notify.chopchopguinee.com`)
- [ ] Reply-to address set (e.g. `support@chopchopguinee.com`)
- [ ] Live test: signup with a real Gmail address → confirmation email arrives in inbox (not spam)
- [ ] Live test: signup with a real Orange / Yahoo / iCloud address → confirmation email arrives in inbox
- [ ] Live test: password reset → recovery email arrives, link works
- [ ] Live test: link click confirms account and redirects into the app
- [ ] Bounce / complaint monitoring location documented for ops

## How to run the live inbox test (ops walkthrough)

1. From an incognito browser, open the published app and sign up with a real
   Gmail address you control.
2. Watch the inbox (and spam folder) for the CHOPCHOP confirmation email.
   It should arrive within 60 seconds.
3. Click the confirmation link. It must land back in the app authenticated.
4. From the sign-in screen, use "Mot de passe oublié" with the same address.
   Confirm the recovery email arrives and the reset link works.
5. Repeat steps 1–4 with a real Orange, Yahoo, and iCloud address.
6. Open **Admin → Centre opérations**. The "Emails auth" chip should show
   `Prêt` with a non-zero 7-day send count.
7. Open **Cloud → Emails** and confirm each test send is logged with status
   `sent` and no DLQ rows.

If any inbox test fails, follow the recovery steps below before retrying.

## What the agent must never do

- Hardcode SMTP host / port / username / password / API key in `src/` or in committed config
- Expose SMTP or provider secrets to the browser
- Claim SMTP is "configured" without DNS verification and live inbox tests
- Recommend a third-party SMTP service unless the user explicitly requests one

## If a launch test fails

1. Check Cloud → Emails for domain status and recent send log
2. Inspect `email_send_log` for failed / suppressed rows
3. Check `suppressed_emails` for the recipient address
4. Re-run the auth template scaffold + deploy if the hook is on an older pattern
5. Escalate to platform/security agent if DNS or queue is broken