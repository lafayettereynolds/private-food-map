# Final Integration: Development dependency and Worker closure

## Scope and authorization

Following the user's instruction to continue after the missing-0040 explanation, only the Development dependency and corresponding Development Worker were changed. No Production requests with write semantics, real-device operation, photo deletion, account deletion, logout or sync was performed. No scheduled retention job was enabled or invoked.

Evidence/private backup directory: `/tmp/tastemap-dev-0040.SlGzwa` (private temporary directory, outside Git). The SQL export is mode 0600. It contains private Development data and must not be committed or published. Raw export logs may contain a temporary download URL; do not publish them.

## 0040 migration

- Exported Development database before mutation; restored the export locally.
- Rehearsed the exact canonical `0040_privacy_retention.sql` against that restored database. All original columns/rows of 67 existing tables remained byte-equivalent under ordered query serialization. New scheduling and purge-authorization tables were empty; lease columns existed. Reapplication correctly rejected the already-existing schema.
- SHA-256: `ae9a750b973c1db67dabb44034bffdfe63695ae210d22047dfd13d7f720c2878`.
- Isolated Wrangler migration directory contained ONLY that exact file; migration list confirmed exactly one pending migration. Wrangler's migration runner applied it and appended its ledger entry. No manual ledger rewrite.
- Remote postcheck: every preexisting ledger row unchanged, including 0041 Discovery and 0042 Photo Delete. Both were neither repeated nor renumbered.
- Remote `account_deletion_jobs` now has `cleanup_lease` and `cleanup_lease_until`; `privacy_purge_authorization` remains empty.
- Post-migration counts matched the backup: restaurants 4014, visits 5104, photos 52, restaurant_lists 98, restaurant_list_items 648, referral_audit_log 0, app_store_verification_audit 0.
- Five current-source targeted test files: 72/72 PASS. An initial incorrectly broad run also collected a nested `.private/privacy-production-candidate` worktree; that unrelated result was excluded, not edited or skipped in the current suite.
- Files: `verify.mjs`, `apply.log`, `targeted-current.log`, `development-predeploy.json`, `preflight.log` under the private evidence directory.

## Development Worker

- Previous version: `d19cbcd2-df59-45ea-91b5-035f578e398b` (rollback reference preserved).
- New active version: `581b3f08-fc17-44f6-a089-c7d720d73769` at 100%.
- Compiled module SHA-256: `28bc61da1034ccd59952a4879aafc689f9de1ec6f28e92ed51a9b90c0861243a`.
- Built via explicit Development config and `wrangler deploy --dry-run`; version upload inherited all existing bindings with strict inheritance. Existing active version was compared before activation to reject concurrent changes.
- Version runtime, all bindings and post-deploy settings verified unchanged (excluding deployment annotations). No route/DNS operation.
- D1: `food-map-db-development`, `b1ddde34-c459-49bb-b9d1-7a41303ccb2d`.
- R2: `taste-map-photos-development`.
- `PRIVACY_RETENTION_ENABLED` was not true before or after. No new cron activation.
- Deployment script restores the exact previous version if activation/postchecks fail. Postchecks succeeded; rollback was not necessary.

| Probe on api-dev.tastemap.cn | Result |
| --- | --- |
| GET /health | 200 application/json, exact `{"status":"ok"}` |
| GET /api/v1/sync/pull without login | 401 application/json |
| GET /api/v1/photos/{nonexistent-test-uuid}/content without login | 401 application/json |

These are deployment/authentication-boundary probes, not authenticated physical-device Sync/Discovery acceptance. Current source owner-isolation tests remain separate evidence. New personal prediction/filter Worker implementation is deployed to Development; it has not yet been verified from a new real-device build.

Private evidence: `worker-build.log`, `worker-bundle/index.js`, `deploy.mjs`, `upload.json`, `verification.json`, `deploy.log`.

## Next gate

The missing-0040 blocker recorded in `FINAL_INTEGRATION_PERSONAL_FILTER_CHECKPOINT_2026-09-09.md` is now CLOSED for Development.

HYBRID_PRIMARY cutover, distinct signed Release/Internal build, Archive, physical-device smoke and Internal TestFlight upload are still NOT RUN. Runtime audit confirms Release still selects RootTabView and only the development Hybrid enum existed at this checkpoint. The existing ReleaseSandbox also enables Sandbox-specific Premium UI, so it must not be casually reused as the normal Internal candidate merely to obtain a Development API endpoint. Preserve the ordinary Premium surface and same app identity when preparing that candidate.

Production, real iPhone and its retained test records were not modified. The broader Final Integration task remains IN PROGRESS.
