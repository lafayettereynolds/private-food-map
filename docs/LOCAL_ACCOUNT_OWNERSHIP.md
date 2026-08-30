# Taste Map local account ownership

This document records the release boundary enforced by the native iOS data layer.

## Entity ownership

| Entity | Ownership kind | Local boundary |
| --- | --- | --- |
| `Restaurant` | Current-user restaurant projection with stable Taste Map/provider identities | direct `ownerUserID` |
| `Visit` | Private current-user record | direct `ownerUserID`; restaurant must have the same owner |
| `Dish` | Private record inherited from its Visit/Restaurant | persisted `ownerUserID` for fail-closed queries; parents must match |
| `VisitDish` | Private relationship inherited from Visit/Dish | persisted `ownerUserID`; all parents must match |
| `PhotoAsset` | Private/user-published asset inherited from its parent or profile | persisted `ownerUserID`; local binary lifecycle is owner-scoped |
| `DiningCompanion` | Private address-book entry | existing direct `ownerUserId` |
| `RecommendationSource` | Private source directory entry | existing direct `ownerUserId` |
| `RestaurantList` / `RestaurantListItem` | Current-user list and membership | existing direct `ownerUserID` |
| `UserProfile` | Current-user profile projection | `tasteMapUserID` |
| `SyncMutation` / `SyncCheckpoint` | Per-account offline queue and cursor | direct `ownerUserID` |
| Social relationships, mutations, discovery/community/list caches | Per-viewer derived projection | existing `currentUserID` / `viewerUserID` |
| `CachedSocialProfile` | Public derived identity cache | shared, never treated as private business ownership |

## Signed-out and legacy rules

- `local` is an explicit signed-out guest workspace. When a real `tm_…` user signs in, that guest workspace may be claimed by that user.
- Rows introduced by an older schema receive `legacy-unscoped`. They are hidden from every product surface and excluded from sync/export.
- A quarantined row is assigned only from authoritative evidence: a decoded server contract with a matching user ID or a parent whose ownership is already proven.
- Unknown legacy rows are never assigned to the first account that signs in.

## Account switching and deletion

- Views may fetch a shared SwiftData container, but every product projection is built through the active `LocalAccountScope` and exact owner matching.
- Writes receive the authenticated Taste Map user ID. Apple subject, email and display name are never ownership inputs.
- Sync queue processing, cursors and photo transfer retries are scoped to the authenticated owner.
- Account deletion removes only the selected user's business rows, queue, checkpoint, viewer caches and photo files. Other local accounts, including unsynced rows and unique local originals, remain intact.

## Identity distinction

Restaurant provider identities remain place identity evidence. They do not grant ownership and do not replace the Taste Map user boundary. Two accounts can hold independent local projections of the same real-world place without sharing private Visit, note, rating, photo or list membership data.
