# Taste Map Final Release Fixes — Task 02

## SyncEngine real-device failure diagnosis and hardening

- Date: 2026-08-30
- Branch: `main`
- Baseline: `0eafe9f3dccee92678f8ebb8b4e868a6ebdc730a`
- Intended commit: `Fix SyncEngine retry and status handling`
- Environment exercised: iOS Simulator and isolated Development Worker/D1 only
- Production accessed or modified: **No**

## 1. Diagnosis

The observed state — sync failed while pending mutations were already zero — is valid and was caused by two different phases being collapsed into one generic status:

1. The mutation push completed and the server explicitly acknowledged the mutation IDs.
2. Only after acknowledgement did the client remove those mutations from its durable queue.
3. A later pull or reconciliation phase could then fail.
4. The UI consequently showed a failed overall sync with `pending = 0`, but did not identify the failed phase.

The previous networking and retry bounds made this particularly confusing:

- sync requests inherited the session's long default timeout (approximately one minute);
- mutation/coordinator retry backoff could reach one hour;
- errors were not classified by reconciliation, push, or pull stage;
- the installed development build exposed only a generic failure state.

The two previously observed Import mutations were therefore not silently discarded. A read-only inspection of the installed development app's copied SwiftData store found:

- 121 restaurants;
- 41 visits;
- 0 queued mutations;
- 1 sync checkpoint at cursor 3317;
- every local restaurant and visit marked `synced`;
- 0 photo records.

The exact historical HTTP status cannot be reconstructed from the old generic diagnostics. The new diagnostics record the stage and safe failure category for future reproductions without logging payloads, tokens, restaurant names, visit notes, or user identity.

## 2. Changes

### Stage-aware synchronization

`SyncEngine` now wraps reconciliation, mutation push, and pull independently. A failure preserves the failing stage while retaining the underlying typed error.

### Bounded execution

- Sync request timeout: 15 seconds, clamped to a maximum of 30 seconds when injected.
- Retry backoff maximum: 60 seconds.
- Pull pages per synchronization pass: maximum 20.
- A server that continually reports `hasMore` now produces a retryable cursor-category failure instead of holding a pass indefinitely.
- Checkpoints are persisted after each successful page, so bounded continuation resumes incrementally.

### Development-only diagnostics

Debug builds now expose and log only safe operational metadata:

- failing stage;
- request category (`local`, `push`, or `pull`);
- failure category;
- HTTP status when available;
- duration;
- retry count;
- final disposition.

Release UI does not display these diagnostic rows. No request/response bodies, credentials, secrets, entity data, or user identifiers are logged.

### Coordinator behavior

- Concurrent automatic and manual triggers remain single-flight.
- Retry state is bounded and cleared after success.
- Account changes and logout clear stale failure presentation.
- Logout preserves the durable mutation queue rather than deleting unsynchronized work.
- A successful push followed by a failed pull reports failure without recreating an already acknowledged mutation.

## 3. Mutation acknowledgement safety

Queue deletion still occurs only after a matching server acknowledgement. The regression suite verifies that:

- duplicate sends reuse the same mutation ID;
- a successful server write followed by a lost client response is retried idempotently;
- an acknowledged push followed by a pull failure leaves the mutation removed and the entity intact;
- a push failure leaves the mutation queued;
- tombstones and two-client conflict behavior remain intact.

## 4. Automated test results

All selected tests passed:

- `SyncCoordinatorTests`: 15 tests
- `SyncEngineTests`: 7 tests
- `LocalMultiAccountIsolationTests`: 6 tests
- `P1DTwoClientSyncTests`: 1 two-client conflict/tombstone flow

Covered scenarios include:

- empty queue success and pull failure;
- push success followed by pull failure;
- push failure;
- manual retry recovery;
- automatic/manual single-flight coordination;
- bounded request timeout and backoff;
- permanent failure without retry loops;
- transient retry without duplicate mutation IDs;
- account switch and logout behavior;
- Task 01 current-user ownership isolation;
- two-client conflict and tombstone protection.

## 5. Real Development Worker/D1 validation

Development-only integration tests were enabled through an ephemeral `.xctestrun` environment, without changing repository configuration.

- Development URL: `https://api-dev.tastemap.cn`
- Real round trip: passed in 12.417 seconds
- Real two-client offline/conflict round trip: passed in 23.801 seconds

The real Development tests covered:

- Restaurant push/pull;
- Apple Maps-only restaurant identity;
- mutation idempotency;
- incremental cursor behavior;
- Visit-to-Restaurant association;
- two-client synchronization;
- tombstones and cleanup;
- current-user ownership enforcement.

No real Legacy Import was executed. No Production Worker, D1, R2, migration, secret, or deployment was accessed.

## 6. Build results

- Debug, generic iOS Simulator: **passed**
- Release, generic iOS Simulator: **passed**
- `git diff --check`: **passed**

The existing App Intents metadata warning remains unrelated: the app has no `AppIntents.framework` dependency.

## 7. Remaining manual smoke check

The currently installed iPhone build predates both Task 01's local ownership schema and this Task 02 diagnostic hardening. It was intentionally not overwritten automatically because installing the new schema over the user's existing device data is a real local migration event.

Before release, Lafayette should install the latest Debug build on the development iPhone and perform one manual `Sync Now`/retry smoke check. If a failure recurs, the new Debug-only Settings diagnostics will identify the exact stage and category. This is a manual release smoke item, not a blocker for the independent Tasks 03–07.

## 8. Safety statement

- Task 01 ownership changes were preserved and regression-tested.
- No SwiftData schema was changed in Task 02.
- No Worker, D1, migration, authentication, or Production configuration was changed.
- No historical mutation was manually recreated or deleted.
- No user data was written during device inspection.
