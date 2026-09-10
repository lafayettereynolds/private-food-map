# Final Review RC integration — backend prerequisite closed

## 2026-09-10 16:51 Production UGC follow-up

The separately authorized minimal backend deployment is PASS. Current Production is
`2ec7bc75-7c89-4d8a-9a3a-4a3c85e6c858`; rollback reference is `eaed4e92-1881-444a-9729-1230b2882b8e`.
The approved UGC backend increment was integrated onto the retention-enabled source
as `a78d9b9`, not deployed from the older RC Worker tree. Worker 461/461, TypeScript,
production build/purity and exact six-module semantic diff PASS. Fresh D1 backup
restored successfully. Ledger 44, retention enabled, cron, bindings, routes,
domains and assets preserved. Live safety endpoint returns 401 JSON unauthenticated;
its implementation is present in the verified live bundle. Authenticated capability
semantics passed isolated tests without real-user writes. Post-deploy retention
30/90/365 candidates are all zero, FK PASS. No migrations or D1/R2 business writes.

PRODUCTION UGC BACKEND: READY FOR FINAL REVIEW RC.
The historical blocker below is resolved; remaining archive/distribution/processing/
TestFlight-device gates are still NOT RUN, not automatically promoted to PASS.
Detailed evidence: `private-food-map-production-ugc-20260910/reports/PRODUCTION_UGC_DEPLOYMENT_20260910.md`.

## Frozen baseline

- Branch: `release/production-rc-20260910`.
- HEAD before this task: `dcbdc59b2b835da785c642f9d64326ab0e5943a0`.
- Tracked source fingerprint: SHA-256 `1e79965d4ffcde31331ffdd62ea2f7197d8d64980cad51c768b848d2e0a6542c`, 2143 files, sorted path + NUL + bytes.
- No staged or tracked dirty files at entry. Existing untracked `node_modules`, `reports/DEV_TO_PROD_MIGRATION_PLAN_DRY_RUN_20260910.md`, and `reports/PRODUCTION_RC_1012_EMPTY_DATA_READ_ONLY_DIAGNOSIS.md` preserved.
- Other Final Integration worktree unchanged. No reset, rebase, force, or branch replacement.
- User confirms 1012 Production smoke PASS. This does not certify the new candidate.

## Source integration

- `430fe7a`: six approved files integrated; byte comparison against the approved commit PASS, including Privacy Manifest, audit/tests and canonical website sources. No website deployment performed.
- `f1360004127131c07c8be337a0c1c8238849a6f9`: 40 non-generated files integrated by patch; all 40 match the approved commit byte-for-byte. Old branch-generated Web assets deliberately excluded. A future clean build must stage the combined source.
- `fbad2bd`: already integrated as `21a369c`; implementation/projection/fixture files match, and full tests include personal rating coverage. Not applied twice.
- Integration-only test update: four historical policy text expectations in `SettingsInteractionContract.test.tsx` now assert the approved exact policy wording. No tests removed/skipped; no policy semantics changed to satisfy tests.
- Existing Production endpoint/renderer/signing configuration unchanged. Generated staged assets still belong to 1012 and are NOT a new RC.

## Executed local checks

Private evidence: `.private/final-review-rc-20260910/` (Git ignored).

| Check | Result |
| --- | --- |
| Web + Worker full, final rerun | 1601/1601 PASS, 0 FAIL, 0 pending |
| TypeScript Web + Worker | PASS |
| Swift bridge | 43/43 PASS |
| Privacy source tests | 5/5 PASS |
| Approved source byte comparison | Privacy 6/6; UGC 40/40 |
| git diff whitespace check | PASS |
| Native full against historical failures | NOT RUN |
| Interactive UGC harness in combined source | NOT RUN |
| New Archive / distribution / signed manifest / asset parity / purity | NOT RUN |

Initial full suite was 1600/1601 because the older Settings test required superseded retention wording. Final full rerun is green after the exact assertion correction. The dependency symlink is preserved; bundled pnpm attempted dependency validation/removal and aborted without a TTY, so tests used the existing installed Vitest/TypeScript entry points directly. No dependency purge was performed.

## Confirmed Production prerequisite blocker

Official Wrangler `whoami` restored usable existing OAuth authorization after an initial control-plane 401. No new token or expanded scope was created.

Read-only control-plane observation at `2026-09-10T08:19:59.705Z`:

- Deployment: `b61fcc9a-a897-4d2e-ab72-9a323756522d`.
- Active Worker version: `eaed4e92-1881-444a-9729-1230b2882b8e`, 100%.
- GET Worker script returned multipart source, 926694 bytes.
- `/api/v1/community/safety`: absent.
- `community-safety-read`: absent.

The approved UGC change requires that endpoint in `moderationV1.ts`, routed by `worker/index.ts`. Native `moderateCommunity` and shared `UGCSafetyMenu` request authoritative capabilities before exposing report/block actions. The UGC handoff report explicitly requires deploying the updated Worker before the client; this is not merely an optional UI enhancement. Existing backend report/block capabilities do not supply the new capability endpoint.

Do not claim UGC production readiness or upload the new client while this prerequisite is absent. No authenticated business mutation was sent to verify it; no user content was read.

## Stop / handoff

FINAL REVIEW RC BASE: 1012 / dcbdc59

WORKSPACE PRESERVED: PASS

UGC SOURCE INTEGRATED: PASS

PRIVACY MANIFEST SOURCE INTEGRATED: PASS

RATING FIX: PASS

API: https://api.tastemap.cn

UGC PRODUCTION PREREQUISITE: BLOCKED

NEW REGRESSIONS: 0 in executed suites; Native full and artifact/device gates outstanding

FINAL BUILD: NOT GENERATED (1013 not reserved or checked against ASC)

ARCHIVE / DISTRIBUTION / ARTIFACT PURITY / ARTIFACT PARITY: NOT RUN

APP STORE CONNECT UPLOAD / APPLE PROCESSING: NOT RUN

TESTFLIGHT INSTALL / FINAL REAL DEVICE SMOKE: NOT RUN

QUEUE: NOT READ THIS TURN

FINAL APP REVIEW CANDIDATE: NO

NEXT: obtain explicit minimal Production UGC Worker deployment authorization; preserve live retention fixes and bindings, no migrations. Then close remaining regression/build/distribution gates and upload one normal App Store-eligible build for internal testing only. Do not deploy the historical 1012 Worker wholesale because Production has newer retention changes.

Production, iPhone, ASC metadata, screenshots and submission state were not modified. No Submit for Review.
