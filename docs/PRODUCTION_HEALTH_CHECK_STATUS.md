# Production health check — 2026-09-08

Status: local fix and tests PASS; Production rollout BLOCKED, original version restored.

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
