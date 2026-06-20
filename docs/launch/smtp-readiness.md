# SMTP / Auth Email — Production Launch Readiness

**Status:** RED — CODE READY / NEEDS OPS.
Default / dev auth email delivery is **not** acceptable for mission launch.

CHOPCHOP auth emails (signup confirmation, password reset, magic links) route through the
Lovable-managed auth email pipeline (`auth-email-hook`). No SMTP credentials are stored in
`src/` or in any client bundle.

## Ops checklist — must be GREEN before launch

- [ ] Sender domain configured (e.g. `notify.chopchopguinee.com`)
- [ ] DNS records verified (NS delegation green in Cloud → Emails)
- [ ] Sender name set to **CHOPCHOP**
- [ ] Sender email set (e.g. `no-reply@notify.chopchopguinee.com`)
- [ ] Reply-to address set (e.g. `support@chopchopguinee.com`)
- [ ] Branded auth templates deployed (signup, recovery, magic-link, invite, email-change)
- [ ] Live test: signup with a real Gmail address → confirmation email arrives in inbox (not spam)
- [ ] Live test: signup with a real Orange / Yahoo / iCloud address → confirmation email arrives in inbox
- [ ] Live test: password reset → recovery email arrives, link works
- [ ] Live test: link click confirms account and redirects into the app
- [ ] Bounce / complaint monitoring location documented for ops

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