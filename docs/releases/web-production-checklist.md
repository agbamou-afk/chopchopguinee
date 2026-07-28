# Web Production Release Checklist (`web-rc-1`)

Tick only what was actually observed. `PASS(code)` is not a tick for a gate.

## Preflight

- [x] RC identifier and commit recorded
- [x] Sandbox flags OFF (`om_sandbox_enabled`, `om_environment`)
- [x] Public wallet flag OFF
- [x] Provider mode = manual verification
- [x] 170 migrations committed, deterministic order
- [x] 23 Edge Functions present at RC SHA
- [x] All public tables have RLS enabled (0 without)
- [x] 0 error-level database linter findings
- [x] Clean production build (27.9s, `dist/sw.js`, 127 precache entries)
- [x] Typecheck clean
- [x] Unit tests 12/12
- [x] `react-hooks/rules-of-hooks` errors = 0 (guards flag-rollback safety)
- [x] Frontend secret sweep clean, 0 source maps
- [x] Demo panel absent from production bundle
- [ ] Orange Money real-money evidence attached
- [ ] SMTP inbox matrix completed and signed
- [ ] Deployment rollback rehearsed

## Deploy

- [ ] Migrations applied
- [ ] Edge Functions deployed at release SHA
- [ ] Feature flags set to launch values
- [ ] Frontend published

## Post-deploy smoke (see release doc §11)

- [ ] 1 home · [ ] 2 sign-in · [ ] 3 ride quote · [ ] 4 Repas/Marché lists
- [ ] 5 OM wallet panel · [ ] 6 driver online/offers
- [ ] 7 staff forced password change · [ ] 8 Ops readiness
- [ ] 9 sandbox OFF · [ ] 10 mobile 390×844 repeat

## Signoff

- [ ] Finance Admin — OM evidence
- [ ] Operations — SMTP evidence
- [ ] Release owner — P2 register accepted
- [ ] God Admin — rollback rehearsal
- [ ] Release owner — go-live authorised
