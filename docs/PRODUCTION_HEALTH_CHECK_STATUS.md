# Production health check — 2026-09-08

LATEST: CURRENT PRODUCTION BASELINE `dd0369b9-26c1-4fe7-a23b-9a56f5887661` is formally ADOPTED / PASS. Previous verified baseline / rollback reference: `87b45679-2bc8-4f4b-b0a4-c82b65c155e9`. Retained verified evidence: health200JSON, core ready200JSON, unauthenticated sync401JSON, API.TASTEMAP.CN/D1/R2 PASS, original28 assets byte/hash parity PASS. Formal client Base URL remains https://api.tastemap.cn with no origin fallback. Production Sandbox Offers remain rejected with403 sandbox_offer_forbidden (expected security boundary). [Current baseline and approved real-device plan](../reports/PRODUCTION_BASELINE_ADOPTION_2026-09-08.md) supersedes historical notices below. No deployment, DNS or endpoint change in this status update.

CURRENT DECISION: retain candidate ede1474e and its verified code-identical secrets successor f8dd5e0f. Health and 28/28 asset parity PASS; formal baseline adoption is still blocked. The historical restore/build-package request below is superseded, not a current instruction. See [current audit](../reports/PRODUCTION_BASELINE_AUDIT_2026-09-08.md).

Historical status of the first attempt: local fix and tests PASS; rollout blocked, original version restored. **Superseded live-state observation:** another deployment subsequently published `ede1474e-cbaa-4e98-b75c-413af8ccc427`; health now passes. See `PRODUCTION_ASSETS_RECOVERY_2026-09-08.md` for the follow-up, 28-file static parity evidence, and baseline conflict. The old version below is not the current live version anymore.

## Scope and local files

- `worker/index.ts`: public `GET /health` returns exact `{"status":"ok"}`, HTTP 200, `Content-Type: application/json`, `Cache-Control: no-store`, before authentication or assets.
- `wrangler.jsonc`: adds `/health` to existing `assets.run_worker_first`; other settings unchanged by this task.
- `worker/health.test.js`: five passing regression cases (three unauthenticated/header variants, existing SPA fallback, configuration/binding contract).
- Worker TypeScript check passed.

## Production evidence and rollout boundary

Worker: `private-food-map`; custom domain: `https://origin-api.tastemap.cn`.
Original/current restored version: `29c76424-037c-418d-b607-7a3d07ed6f1d`.
Downloaded original Worker has `/api/*` routes, including `/api/v1/auth/*`, `/api/v1/sync/pull`, `/api/v1/sync/push`, and legacy `/api/sync`.
Non-API paths are passed to `ASSETS.fetch`. Original assets use SPA fallback and Worker-first only for `/api/*`.

The downloaded production module was patched and independently tested with three health request variants; all remaining module bytes were verified unchanged. A deployment using `keep_assets: true` preserved the original assets but also retained the old assets routing despite the supplied new configuration. Version upload and settings readback likewise did not activate `/health` routing. HTTP verification therefore still returned HTML, not JSON. The attempted deployment was not accepted; production was restored to its original version.

All D1/R2/environment bindings were compared and remained identical. No database writes/migrations, R2 object operations, iOS signing/Bundle Identifier changes, or frontend deployment were performed. No local dirty business code was published.

## Client URL

iOS Base URL for this direct Worker origin: `https://origin-api.tastemap.cn` (no `/api` suffix). `APIConfiguration.url(for:)` appends the already-prefixed `/api/v1/...` client paths. `/restaurants` and `/visits` are not root-level API endpoints.

Live unauthenticated `/api/v1/sync/pull` returned HTTP 401 JSON (`Sync authentication is required.`), confirming the API path and continued authentication enforcement. The health requirement remains NOT PASSED.

## Required next input

Obtain the complete exact static Assets build directory/manifest for the original Production deployment. Redeploy the unchanged production module plus this health handler with those exact assets and Worker-first `/health`, `/api/*`. Do not use the current dirty workspace `dist` or deploy the full current Worker: both contain unrelated unshipped changes.

Require post-deployment runtime configuration readback and `curl -i https://origin-api.tastemap.cn/health` returning HTTP 200 JSON before marking completion. This is a liveness endpoint, not a D1/R2 readiness check.
