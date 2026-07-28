# Frontend Secret & Security Audit (`web-rc-1`)

Scope: `src/`, `index.html`, committed docs, and the built `dist/` bundle from
the RC build (2026-07-28, PWA v1.3.0, 127 precache entries).

## Result: **PASS — no secret exposure. No P0.**

## Sweep results

| Pattern | Result |
|---|---|
| `service_role` key material | **none.** Two source matches are French UI/comment copy (`src/lib/marche/payments.ts` comment, `src/pages/admin/RepasPayments.tsx` label) and one bundled copy of that label. No key value. |
| JWTs in bundle | exactly one distinct token; decoded payload `{"iss":"supabase","ref":…,"role":"anon"}` — the approved publishable key |
| Provider credentials (Orange Money) | none in frontend; all provider handling is server-side |
| SMTP credentials | none |
| Private API keys / `BEGIN PRIVATE KEY` | none |
| Hard-coded admin passwords | none |
| Temporary staff passwords | none in the bundle; generated server-side by `admin-create-staff-user` |
| Secret webhook tokens | none |
| Private database URLs | none; only the public project URL |
| `SUPABASE_SERVICE` / `DATABASE_URL` / `MAILGUN` / `RESEND_API` in `dist/` | none |
| Sandbox fixture codes (`OM-SBX-*`) in customer UI | not reachable in production — gated on `om_environment && om_sandbox_enabled`, both `false`, and server RPCs reject sandbox references outside sandbox mode |

## Allowed frontend values (confirmed present and appropriate)

- `VITE_SUPABASE_URL` — public project URL.
- `VITE_SUPABASE_PUBLISHABLE_KEY` — anon key, protected by RLS.
- `VITE_SUPABASE_PROJECT_ID` — public identifier.
- Map token — served at runtime by the `maps-config` Edge Function rather than
  embedded at build time, and rate-limited server-side.

## Configuration checks

| Check | Result |
|---|---|
| `.env` handling | contains only `VITE_`-prefixed public values; no `.env` emitted into `dist/` |
| Vite public-prefix discipline | no non-`VITE_` variable is read from client code |
| Source maps | **0** `.map` files emitted in `dist/assets` — no source exposure |
| Console logging of sensitive payloads | one occurrence found and fixed (DEF-003, driver offer payload); no payment reference, token or PII logging remains in production paths |
| Error messages | user-facing errors are French, generic, and do not surface SQL, table names or internal identifiers |
| Debug/demo bypass | `DemoTestPanel` is `import.meta.env.DEV`-gated and **absent from the production bundle** (zero matches in `dist/`); `?demo=1` is inert in production |
| Secrets in committed documentation | none — docs reference secret *names* only |

## Standing rules for Android 1.0

1. Never move a provider credential, service-role key or SMTP credential into
   client code or into a Capacitor bundle — the native app ships the same
   frontend and inherits the same exposure surface.
2. Any new client-exposed token must be public-by-design and domain/rate
   restricted.
3. Source maps stay off for production builds.
4. New `console` calls touching mission, payment or identity payloads must be
   `import.meta.env.DEV`-gated.
