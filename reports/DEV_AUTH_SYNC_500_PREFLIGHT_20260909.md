# Development Auth / Sync 500 preflight — 2026-09-09

## Scope and outcome

Development only. No deployment, migration, secrets, routing, Production write,
client installation, queue retry, or account change performed in this preflight.
Closure BLOCKED / NOT COMPLETE; do not classify sync as PASS.

HEAD: `9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8`, dirty integrated working tree.
Existing changes preserved. No commit created.

## Current evidence (10:30–10:32 CST)

- Wrangler deployments list and versions view identify active Development version
  `ab629ee6-e454-4b1b-a96c-c53ae1aa5f0a`, created 2026-09-08T11:53:08.647Z.
- DB binding: `b1ddde34-c459-49bb-b9d1-7a41303ccb2d`; R2 binding:
  `taste-map-photos-development`. These match current Development config.
- Secret names present: APP_STORE_ISSUER_ID, APP_STORE_KEY_ID,
  APP_STORE_PRIVATE_KEY. No values read or printed. Missing-secret determination
  is not complete; presence alone does not prove validity.
- Development migration-list query failed with Cloudflare code 7500:
  account free-tier daily row-read limit exceeded. No repeat migration query or
  broad scan performed. Actual ledger/schema version remains UNVERIFIED.
  Current source includes `0040_privacy_retention.sql`; existence is not proof
  this migration is required for the observed failures or applied remotely.
- GET /health: HTTP 200, application/json, {"status":"ok"}.
- GET /api/v1/sync/pull without authentication: HTTP 401 JSON;
  CF-Ray `a382c7a098d4199c-AMS`.
- POST /api/v1/auth/refresh with a synthetic invalid opaque token:
  HTTP 401 JSON, invalid_refresh_token; CF-Ray `a382c555db7b65f9-AMS`.
  This is NOT a valid-session rotation test and does NOT close the refresh gate.
- GET /ready: HTTP 503 JSON; database=true, photos=true,
  authConfigured=false, storeKitConfigured=false;
  CF-Ray `a382c5506e671a71-AMS`.
- Source `worker/productionReadiness.ts` explicitly requires production for
  authConfigured. Development readiness therefore has an environment-semantic
  issue independent of whether authentication works. No change made yet.

The runtime responses above and the D1 management-query failure must not be
conflated. The quota failure is proven for migration inspection, but does not
establish the root cause of either earlier authenticated HTTP 500. No safe
authenticated push fixture has been run, and no successful refresh is claimed.

## Protected device scene

Build 2026090902 remains the recovery build. Device process inspection shows only
the separate QA app process 15300, not the recovery installation's executable
path. That QA process was not touched.

Existing protected snapshot remains:
`/tmp/tastemap-sync-white-fix.D3fAak/stopped/` (DB, WAL, SHM, consistent.sqlite).
Photo preservation evidence still records six files, all bytes equal.
Latest recorded pending count is 36; no new device DB read or retry was performed.
Original mutation IDs/owners were not modified. Prior detailed queue evidence is
in `/tmp/tastemap-sync-white-fix.D3fAak/remaining-mutations.json`.

## Remaining work

Restore D1 query availability, then inspect bounded migration/schema evidence and
the deployed source against local/Production read-only metadata. Establish a
separate authenticated Development fixture without borrowing the real queue.
Capture actual refresh/push errors before choosing a minimal fix. Back up before
any migration. Only after fixture verification may the original device retry
proceed under the user's authorized protocol.

DEV AUTH REFRESH ROOT CAUSE: NOT YET PROVEN
DEV SYNC PUSH ROOT CAUSE: NOT YET PROVEN
COMMON INFRA ROOT CAUSE: UNCONFIRMED
DEV MIGRATION DRIFT: UNVERIFIED
DEV WORKER FIX: NOT YET
DEV DEPLOYMENT: NOT PERFORMED
PRODUCTION TOUCHED: NO
AUTH REFRESH AFTER: NOT YET (invalid-token boundary only)
SAFE SYNC PUSH AFTER: NOT YET
REAL DEVICE RETRY: NOT YET
PENDING BEFORE: 36
PENDING AFTER: 36 (last protected snapshot; no new retry)
DATA LOSS: NONE OBSERVED; full recovery acceptance pending
DUPLICATE DATA: NONE OBSERVED; full recovery acceptance pending
SYNC REAL DEVICE: FAIL / NOT CLOSED
DELETE / ACCOUNT SWITCH TESTS MAY RESUME: NO
