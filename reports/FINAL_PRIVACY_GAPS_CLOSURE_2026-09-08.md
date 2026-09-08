# Final privacy gap closure — local implementation

Scope: account deletion, R2 completion proof, D1 retention lifecycle, and factual policy review. No Production deployment, migration, D1 query, client cutover, or Final RC was performed. App Store Connect was not changed.

## Results

- R2 account deletion: PASS locally. Drains queued original/thumbnail keys, lists only the account prefix with pagination, retries partial failures, and requires both an empty fresh R2 listing and zero pending database keys before completion. Durable leases prevent duplicate cleanup workers.
- >1000 objects: PASS (0, 1, 999, 1000, 1001, 2502; isolation, duplicate requests, retry, remaining-object proof).
- D1 lifecycle: PASS locally. Central constants specify 30-day content redaction eligibility, 90-day security cleanup, and 365-day closed-account commerce/final purge eligibility. Retained sync tombstones and active-account preference event data have explicit functional purposes. Other users' valid rewards and necessary Apple proof postpone the final account purge until their dependency window ends. Bounded jobs are safely repeatable; windows are eligibility thresholds, not guarantees that a large backlog finishes on that exact day.
- Account deletion semantics: PASS locally. Account/session access is revoked first; R2 failures keep the job retryable. Completion means account disabled and object cleanup confirmed, with explicitly documented content/transaction retention; it does not mean every database record vanished immediately.
- Manifest / Info.plist / MapKit: existing PASS preserved. This change does not alter iOS permissions or Release packaging.
- App Privacy: PENDING USER SCREENSHOT. No assumptions or ASC edits.
- Policy source: NOT LOCATED. Policy patch: BLOCKED for actual source integration; factual review draft prepared.
- Final privacy consistency: FAIL / not closed, because the website source patch is not completed and App Privacy evidence remains pending.

## Website provenance

Cloudflare read-only control-plane evidence identifies `tastemap.cn` with Worker `fancy-fog-1341`. Latest listed deployment: 2026-08-25T03:32:48.163404Z, source `wrangler`. Script retrieval returned HTTP 204, and Pages project listing was empty. Searches of project/worktrees, git history, local website files, deployment logs, and archive inventories did not locate the original source or deployment directory. No source path can honestly be supplied. A fetched copy of production HTML is not treated as source.

Review-only edits to sections 2, 5, and 7–8 are in `docs/PRIVACY_POLICY_FACTUAL_PATCH_REVIEW_2026-09-08.md`. They cover suppliers, account deletion path, purchase identifiers and entitlement fields, Gift/Referral, photos, tombstones and retention. These edits have not been applied to or published on the website.

## Activation requirements

Apply migration `0040_privacy_retention.sql` and enable server environment variable `PRIVACY_RETENTION_ENABLED=true` in a separately reviewed deployment. This reuses the existing five-minute cron for deletion retries and its 18:00 UTC occurrence for daily retention. Neither activation nor remote migration occurred in this task. Deploying only the Worker without the required migration is not a supported rollout.

## Validation

- TypeScript: `tsc -b` and Worker `tsc --noEmit`: PASS.
- Worker: 38 files, 378 tests PASS; includes 16 new privacy integration tests against local SQLite with all migrations.
- iOS simulator: LocalMultiAccountIsolationTests + Task13PrivacySecurityReleaseTests: 10 PASS.
- BackupImportMergeEngineTests: 14 PASS, including F1-C4 repeated legacy cross-provider import no-op.
- No fresh Release build required by these Worker-only changes; prior verified Release manifest/permission evidence remains applicable.

Tests used local SQLite / fake R2 and the iOS simulator, not Production D1 or a real Sandbox offer code.
