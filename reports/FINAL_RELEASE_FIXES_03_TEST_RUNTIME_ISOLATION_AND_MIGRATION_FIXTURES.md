# Taste Map Final Release Fixes — Task 03 Acceptance Report

Date: 2026-08-30
Task: Test runtime isolation and Worker migration fixtures
Baseline: `57f6af5 Fix SyncEngine retry and status handling`

## Outcome

Task 03 is complete. Worker integration databases now apply the repository's formal D1 migrations in filename order from one shared harness. The iOS test host now resolves an explicit runtime tier before constructing persistence, credentials, network clients, outboxes, or automatic services. Default unit/local/UI test execution cannot recover a real Keychain session or start automatic Development synchronization.

No Production Worker, D1, R2, secret, or migration was accessed or changed.

## Runtime tiers

| Tier | Persistence | Credentials | Network | Automatic services |
| --- | --- | --- | --- | --- |
| Application | Existing production app configuration | Existing Keychain store | Existing configured API client | Enabled |
| Unit | In-memory SwiftData | Process-local in-memory store | Fail-closed `URLProtocol` | Disabled |
| Local integration | In-memory SwiftData by default | Process-local in-memory store | Fail-closed `URLProtocol` | Disabled |
| UI | In-memory or explicit isolated UI fixture store | Process-local in-memory store | Fail-closed unless the fixture owns its transport | Disabled |
| Development E2E | Test-selected store | Test-only credentials | Explicitly enabled only with `TASTEMAP_TEST_TIER=development-e2e` and Development URL configuration | Disabled; the test drives synchronization directly |

The default test tier is derived from the XCTest environment, so it does not depend on the Simulator Keychain being empty. `TASTEMAP_TEST_TIER` is the explicit override for a deliberately selected test tier. Development network integration additionally remains guarded by the existing `TASTEMAP_RUN_DEV_SYNC_TESTS=1` opt-in.

## Worker migration fixture

`worker/testSupport/migrations.js` is now the single integration-test migration loader. It:

- discovers zero-padded `.sql` migrations from the real `migrations/` directory;
- sorts them in migration order;
- applies their SQL to each isolated SQLite fixture;
- eliminates hand-maintained migration arrays and copied schema fragments from Worker tests.

`worker/migrationFixture.test.js` proves that the current sequence reaches migration `0032` and creates representative late-schema tables including `user_blocks`, `app_store_transactions`, and `public_share_links`. The previously reported missing-`user_blocks` failure is therefore zero.

## iOS isolation changes

- Added `TasteMapRuntimeConfiguration` and an explicit `TasteMapRuntimeTier`.
- Added an in-memory `IsolatedAuthCredentialStore`; default tests never read or write the real Keychain.
- Added a fail-closed ephemeral `URLSession` using `TestNetworkBlockerURLProtocol` for non-network test tiers.
- Uses in-memory SwiftData and per-process temporary photo/outbox paths in test tiers.
- Suppresses account-deletion credential recovery, auth-scope restoration, foreground synchronization, photo transfer startup, and automatic sync in test tiers.
- Kept the normal application runtime unchanged.
- Marked UI launch tests with an explicit isolated UI runtime signal.
- Replaced the unit test that exercised the real Keychain with an equivalent credential-restoration test against the isolated credential abstraction. Real Keychain behavior remains covered by the separate real-device authentication acceptance work.

## Regression results

### Worker and Web

- Worker Vitest: **339 passed / 0 failed**, 49 files.
- Worker migration fixture regression: **passed**; `user_blocks` present.
- TypeScript project typecheck: **passed**.
- Worker typecheck (`tsconfig.worker.json`): **passed**.
- Vite production build: **passed**.
- Existing Vite warning: application chunk exceeds 500 kB. No new build failure or Task 03 regression.

### iOS unit and integration

- New runtime isolation tests: **6 passed / 0 failed**.
- Full serial unit run on the existing, historically used iPhone 17 Pro Simulator: **575 passed / 0 failed** (`20 XCTest + 555 Swift Testing`).
- Full serial unit run on a newly created clean iPhone 17 Pro Simulator: **575 passed / 0 failed** (`20 XCTest + 555 Swift Testing`).
- The clean temporary Simulator was shut down and deleted after the run.
- Clean and historical Simulator results are identical.
- Relevant serialization regression suites: **52 passed / 0 failed**.
- Explicit Development E2E tier against `https://api-dev.tastemap.cn`:
  - Restaurant/Visit push-pull round trip: **passed** in 14.318 seconds.
  - Two-client offline conflict and tombstone convergence: **passed** in 25.173 seconds.
  - Total: **2 passed / 0 failed**.

An initial full run with Xcode parallel test runners produced 570 passes, one no-signing Keychain-host failure, one timing assertion failure, and three runner-process crashes in otherwise independent file/render/retry suites. The Keychain dependency was removed from the unit tier as required, and the affected suites passed 52/52 when executed in the canonical serialized test host. Both complete clean and historical Simulator runs then passed 575/575. This was test-runner resource concurrency rather than a remaining product assertion failure; Task 03's deterministic acceptance command uses `-parallel-testing-enabled NO`.

No tests were reported as flaky after isolation and serialized acceptance. Guarded Development-only tests are not contacted by the default unit runtime; the two selected E2E cases were separately enabled and executed.

### UI and builds

- Selected UI path `testMapHomeLaunchesWithoutBlockingOnLocation`: **passed**.
- Selected UI path `testP3AProfileEditAndRestartPersistence`: **passed**.
- Selected UI total: **2 passed / 0 failed**.
- iOS Debug generic Simulator build: **passed**.
- iOS Release generic Simulator build: **passed**.

Simulator-only logs still contain unrelated system/resource diagnostics (MapKit location unavailable, app-group entitlement absent in unsigned test hosts, and AppIntents metadata notices). They did not fail tests or builds and were not introduced by this task.

## Files changed

### iOS application and tests

- `ios/TasteMap/TasteMap/App/TasteMapRuntimeConfiguration.swift`
- `ios/TasteMap/TasteMap/ContentView.swift`
- `ios/TasteMap/TasteMap/Services/NativeAuthServices.swift`
- `ios/TasteMap/TasteMap/TasteMapApp.swift`
- `ios/TasteMap/TasteMapTests/AuthSessionManagerTests.swift`
- `ios/TasteMap/TasteMapTests/TestRuntimeIsolationTests.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITests.swift`
- `ios/TasteMap/TasteMapUITests/TasteMapUITestsLaunchTests.swift`

### Worker tests

- `worker/testSupport/migrations.js`
- `worker/migrationFixture.test.js`
- `worker/appStoreCommerceV1.integration.test.ts`
- `worker/authV1.integration.test.js`
- `worker/communityV1.integration.test.js`
- `worker/developmentDemoAdminV1.integration.test.js`
- `worker/discoveryV1.integration.test.js`
- `worker/publicSharingV1.integration.test.js`
- `worker/releaseSafetyV1.integration.test.js`
- `worker/restaurantListsV1.integration.test.js`
- `worker/socialCollaborationV1.integration.test.js`
- `worker/socialV1.integration.test.js`
- `worker/syncV1.integration.test.js`

## Safety and scope

- SwiftData business schema: unchanged.
- Authentication protocol and Keychain implementation used by the real app: unchanged.
- Sync protocol, cursor, mutation, reconciliation, and retry semantics: unchanged.
- Formal migration SQL files: unchanged.
- Worker runtime behavior: unchanged; only integration fixture construction changed.
- Production: not accessed.
- Pre-existing Xcode project-file modification, stash, audit documents, workspace file, and unrelated reports: preserved and excluded from this task's commit.
