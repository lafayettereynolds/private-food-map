# Taste Map Final Release Fixes — Task 01 Acceptance

## Result

PASS. The iOS local data layer now has an explicit Taste Map account boundary for core business records, sync state, photos, projections, analytics, and account deletion. No Production service was accessed or modified.

## Ownership model

| Entity | Ownership rule |
| --- | --- |
| `Restaurant` | Direct `ownerUserID`; provider identities remain provider-neutral external identities, not owners. |
| `Visit` | Direct `ownerUserID`, validated against the owned Restaurant. |
| `Dish` | Direct `ownerUserID`, inherited and validated from its Visit/Restaurant graph. |
| `VisitDish` | Direct `ownerUserID`, inherited and validated from its Visit/Dish graph. |
| `PhotoAsset` | Direct `ownerUserID`, inherited and validated from its Restaurant/Visit/Dish or Profile graph. |
| `DiningCompanion` | Existing direct `ownerUserId`. |
| `RecommendationSource` | Existing direct `ownerUserId`. |
| `RestaurantList` / `RestaurantListItem` | Existing direct `ownerUserID`. |
| `UserProfile` | Existing direct `tasteMapUserID`. |
| `SyncMutation` | Direct `ownerUserID`; queues are account-scoped. |
| `SyncCheckpoint` | Direct `ownerUserID`; cursor scope is `owner|sync-v1`. |
| Social / Discovery / Community caches | Existing viewer/current-user projection key. Public shared identities remain derived cache only. |

## Runtime behavior

- Authentication restoration enters a non-readable `restoring` scope until the Keychain session is resolved.
- Signed-out writes use the explicit installation-local guest owner `local`.
- Authenticated writes use the Worker-issued stable `tm_...` Taste Map user ID.
- On sign-in, explicit guest rows can be claimed by that user. Legacy rows with reliable server or parent evidence can be mapped. Ambiguous legacy rows remain quarantined as `legacy-unscoped` and are neither displayed nor uploaded.
- Map, list, search, Restaurant Detail, Visit editor, Profile, analytics, On This Day, Roulette, Discovery, Community, companion/source pickers, backup export/import, photo transfer, and sync paths apply the active account boundary.
- Restaurant provider IDs remain external identities and are never used as account identity.

## Account deletion boundary

`LocalAccountDataPurger` deletes only the confirmed current Taste Map user's:

- Restaurant / Visit / Dish / VisitDish / PhotoAsset rows;
- local photo files referenced by those owned PhotoAsset rows;
- companion/source/profile/list rows;
- sync mutations and sync checkpoint;
- current-viewer social, discovery, community, and public-list caches.

Rows, unique local photos, queues, and checkpoints owned by another local account survive. The container is not wiped.

## Sync and tombstones

- `SyncEngine`, `SyncCoordinator`, `SwiftDataSyncQueue`, and `PhotoTransferCoordinator` operate with one explicit owner.
- Pull records must match the active owner; mismatched records fail closed.
- Local identifiers can coexist across account projections without provider-specific ownership assumptions.
- Tombstones and mutation coalescing are queue-owner scoped. Deleting one account's projection cannot delete or resurrect another account's projection.

## Automated verification

- New `LocalMultiAccountIsolationTests`: 6/6 passed.
  - A → B → A projection isolation for Map/List/Profile/Search and child graphs.
  - authenticated write ownership and mutation isolation.
  - current-account-only deletion including photo files, queue, and checkpoint.
  - evidence-based migration plus quarantine.
  - restart persistence.
  - account-scoped tombstone behavior.
- Full iOS unit suite: 540 tests in 54 suites passed.
- Related backup export/import, Restaurant/Visit/Dish/Photo, Profile, list, and sync regression suites passed.
- Debug iOS Simulator build passed.
- Release iOS Simulator build passed.

## Safety verification

- Bundle Identifier unchanged: `com.lafayette.tastemap`.
- Team, signing, capabilities, App Icon, Worker, D1, migrations, contracts, and Production unchanged.
- No real user data was read, migrated, deleted, or uploaded by tests.
- Tests used isolated in-memory or temporary SwiftData stores and an in-memory photo-file double.

## Git

- Intended commit: `Fix local multi-account data isolation`
- This report belongs to that same independent Task 01 commit.
