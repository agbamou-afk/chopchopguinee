# CHOPCHOP — End-to-End Tests (Playwright)

Internal QA infrastructure. **Never** point these at production accounts or live data.

## Run locally

```bash
# one-time: install browsers
npx playwright install chromium

# run all tests (auto-starts `npm run dev` on :8080)
npm run test:e2e

# headed mode (watch the browser)
npm run test:e2e:headed

# target a remote preview URL instead of the dev server
PLAYWRIGHT_BASE_URL=https://id-preview--<id>.lovable.app npm run test:e2e
```

## Layout

- `playwright.config.ts` — base config (mobile Pixel 5 viewport, fr-FR)
- `tests/e2e/helpers.ts` — `skipSplash`, `gotoSandbox`, blank-screen guards
- `tests/e2e/01-public-flows.spec.ts` — home / auth / 404
- `tests/e2e/02-navigation.spec.ts` — route smoke
- `tests/e2e/03-merchant.spec.ts` — merchant landing & hub
- `tests/e2e/04-sandbox-ops.spec.ts` — SandboxOpsPanel mount + scenario run
- `tests/e2e/05-wallet-smoke.spec.ts` — wallet visibility

## Guarantees

- All tests use `?sandbox=1` — synthetic actors only, no Supabase writes.
- No production users or seeded prod data required.
- Tests are idempotent and can re-run without cleanup.