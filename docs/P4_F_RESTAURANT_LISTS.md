# P4-F Restaurant Lists

This document records the native iOS product, identity, sync, public API, permission, cache, migration, and acceptance contract for P4-F. P4-F adds the Restaurant List product only. It does not add collaboration, voting, official/AI lists, a global list square, list analytics, a poster, or P4-G restaurant roulette work.

## Web baseline audit

| Capability | Formal Web source | Web model/UI | Native state before P4-F | P4-F decision |
| --- | --- | --- | --- | --- |
| Own list overview and CRUD | `src/components/RestaurantListsPanel.tsx`, `src/db/restaurantLists.ts` | `restaurantLists`, title, description, visibility, ranked flag, cover mode | No native list domain | Migrate to SwiftData and Sync V1 |
| Title and description | Same | Trimmed title up to 60 Unicode characters; optional description up to 240 | Missing | Preserve the Web limits and allow duplicate titles |
| Visibility | Same plus Worker routes | `private`, `friends`, `public` | Missing | Enforce on Worker, never only in SwiftUI |
| Ranked/ordinary order | Same | Explicit item position and drag reorder | Missing | User order is authoritative; never auto-sort by rating/visits |
| List item note | Same | Optional item note up to 160 Unicode characters | Missing | Migrate as list-specific public metadata; never reuse `Visit.note` |
| Duplicate guard | `src/db/restaurantLists.ts` | Same Restaurant once per list | Missing | Enforce by Global Restaurant identity in Store and Worker |
| Cover | `RestaurantListsPanel.tsx` | Automatic preview or existing Photo as custom cover | Missing | Reuse P2 Photo metadata; no new upload pipeline or designer |
| Restaurant Detail entry | Web list panel/detail flow | Add an existing Restaurant to one or more lists | Missing | Add a lightweight multi-select sheet to the existing native detail |
| Public list read | Web stable list route and Profile integration | Public/friends/private read | No native DTO/query client | Add allowlisted summary/detail APIs and viewer-scoped cache |
| Public Profile entry | `ProfilePage` / list panel | A user's visible lists | Missing | Add paginated list summaries to the existing public Profile |
| Public list discovery | Not a formal standalone Web feature | No list square/search product | Missing | Do not invent a list square in P4-F |
| Collaboration/voting/official/AI | Not formally present | None | None | Explicitly deferred, not silently implemented |
| List poster | Not a formal requirement in the current product | Basic share metadata/link behavior | None | Use system share metadata only; no P4 poster scope expansion |

The Web UI and behavior were used only as the product baseline. P4-F does not modify the React/Web UI.

## Product invariants

- `WantToGo` is a user's Restaurant state. A `RestaurantListItem` is organization/ranking. They are independent.
- Adding a Restaurant to a list never creates or changes `WantToGo`, `Visit`, Dish, Photo, Companion, Recommendation Source, rating, or spend.
- Removing a list item deletes only the association. Deleting a list soft-deletes the list and its items; neither action deletes the Restaurant or user history.
- The same Global Restaurant may appear in different lists, but only once in one list.
- A search-only or public projection can be stored as a list item without manufacturing a full user-owned Restaurant row.
- User list titles need not be globally unique. Emoji and Unicode are allowed.

## Domain model

### `RestaurantList`

- Stable local `UUID id`; `remoteID` is the stable Sync entity ID.
- `ownerUserID`, trimmed `title`, optional-as-empty `listDescription`.
- `visibility`: `private | friends | public`.
- `isRanked`, `coverMode: automatic | custom`, optional `customCoverPhotoID`.
- `activeItemCount` and up to four preview projections are transactionally maintained summary data; list items remain the source of truth.
- `createdAt`, `updatedAt`, `deletedAt`, `serverVersion`, `lastSyncedAt`, `syncStatus`, and canonical `remoteRecordData` support additive local-first sync.

### `RestaurantListItem`

- Stable local `UUID id`; `remoteID` is the stable Sync entity ID.
- `ownerUserID`, local/remote list identity, stable owner Restaurant reference when available.
- `restaurantGlobalKey` is the duplicate and cross-surface identity. It is derived from the primary provider identity but is not the list item ID or a user-state row ID.
- `restaurantSnapshotData` contains only a public-safe place projection: Taste Map reference, provider identities, name/address/city/coordinates, marker Photo/merchant image references, and emoji.
- `position` is a non-negative explicit user order; `note` is list-specific and limited to 160 Unicode characters.
- Creation/update/delete/version/sync metadata mirrors the list entity.

### Public cache

`CachedPublicRestaurantList` and `CachedPublicRestaurantListItem` are keyed by `viewerUserID + listID (+ itemID)`. They are not added to personal Sync V1. Logout purges them. A refresh that receives forbidden/not-found immediately invalidates the cached list and items.

## Global Restaurant identity

List membership references `restaurantGlobalKey` plus a provider-neutral `placeIdentities[]` snapshot. Apple Maps-only, AMap-only, manual, and other provider identities work without `amapPoiId`. Search, WantToGo, Discovery, Community, Restaurant Detail, and Public List converge on the same global key. A public-list Restaurant uses the existing shared Restaurant destination; selecting “加入想吃” creates only the viewer's user state through `LocalDiscoveryStore`.

## Local-first and ordering

Every own-list operation writes SwiftData first and enqueues a durable mutation. Network failure never reverses the local change. App termination leaves the queue and order intact.

For the currently expected 10–100 item lists, reorder uses deterministic contiguous integer positions `0...n-1`. SwiftUI commits once after the drag completes; it does not send network mutations for every pixel. Only items whose stored positions changed are queued. Sorting always uses `(position, createdAt, id)` as a deterministic fallback.

List metadata and items have independent versions. A rename and a disjoint item update may therefore proceed independently. Two stale edits to the same list/item use existing server-version optimistic concurrency and return a conflict; device time never decides the winner. P4-F deliberately does not introduce a CRDT. Concurrent reorder is item-level and deterministic, but may require a later user reorder when two devices changed overlapping items.

Push dependency order is:

```text
RestaurantList upsert -> RestaurantListItem upsert
RestaurantListItem delete -> RestaurantList delete
```

List items carry a valid Global Restaurant projection, so list-only places do not depend on manufacturing a user Restaurant state.

## Sync V1

`restaurantList` and `restaurantListItem` are additive Sync V1 entity types; API and schema versions remain `1`.

- Push decodes the formal list/item JSON contracts, ignores client authorization claims, validates parent ownership, list visibility fields, custom cover ownership/visibility, identity consistency, and duplicate global identity.
- Pull returns `restaurantLists`, `restaurantListItems`, and tombstones through the authenticated user's existing incremental revision cursor.
- The D1 mutation receipt remains idempotent across response loss/retry.
- Deleting a list creates the list tombstone plus deterministic item tombstones. Stale clients cannot revive either.
- Public lists use query APIs rather than entering another user's personal Sync cursor.

## Public query API and permissions

Endpoints:

- `GET /api/v1/lists/users/:userId?cursor=&limit=` returns paginated visible summaries.
- `GET /api/v1/lists/:listId?cursor=&limit=` returns paginated ordered detail items.

Authorization uses the Worker session actor. Client `userId`/`ownerUserId` is never authoritative. Owners can read every own list; accepted friends can read `friends`; strangers can read only `public`. Only owners may create, edit, reorder, remove, or delete. Direct IDs and forged entity IDs do not bypass checks.

DTOs are explicit allowlists:

- `PublicListSummaryDTO`: list display fields, count, up to four Restaurant previews, public owner projection, updated time.
- `PublicListDetailDTO`: summary, paginated ordered `PublicListItemDTO`, cursor, generation time.
- `PublicListItemDTO`: item ID/position/list note and the public-safe Restaurant place projection.

The response cannot include Visit notes, private ratings, spend, companions, recommendation sources, raw sync records, auth data, storage secrets, or private Photo keys. List item notes are included because the audited Web product treats them as list copy visible at the list's own visibility level; they are not Visit notes.

## UI and sharing

- “我的” exposes one “我的榜单” entry. The overview loads summaries, supports title search, create/open/delete, and does not load every item.
- List detail uses Restaurant imagery, subtle Top 3/rank typography, existing placeholders, item notes, add/remove, Edit-mode drag reorder, settings, visibility, and cover selection.
- Empty lists retain a visible add action.
- Restaurant Detail provides a lightweight “加入榜单” sheet with existing lists, multiple selection, and new-list flow.
- Public Profile displays paginated visible summaries. Public detail reuses the existing shared Restaurant detail and viewer WantToGo flow.
- Public lists expose system `ShareLink` metadata. Private/friends lists do not expose a public share action. No share poster is implemented because the audited product did not formally require one.

## Cover behavior

Automatic cover uses the first available valid Restaurant preview Photo/merchant image, falling back through up to four previews and then the existing food placeholder. Custom cover may select an existing Photo already owned and allowed by the P2 Photo pipeline. P4-F adds no Photo upload path and stores no storage secret.

## Performance

- Own overview reads `activeItemCount` and at most four preview projections per list.
- Public summary uses one window-function item query for all lists on the page, avoiding N+1 detail requests.
- Public list items and Profile summaries are cursor-paginated.
- The 100 lists × 50 items acceptance fixture confirms the overview does not hydrate 5,000 detail records.

## D1 migration `0028_restaurant_lists_v1.sql`

The migration incrementally upgrades the Web `restaurant_lists` and `restaurant_list_items` tables. It does not rebuild the database, rewrite Restaurant/Visit IDs, or alter Visit relationships.

- Adds server version/mutation/summary columns to lists.
- Adds owner, Global Restaurant key, public-safe snapshot, and version/mutation columns to items.
- Backfills item owners from their existing parent and identity from the existing primary place identity, falling back to a stable manual identity without changing Restaurant IDs.
- Preserves every existing list/item and recalculates active counts.
- Adds owner/visibility/update, list/position, and Global identity lookup indexes.
- Creates V6 change-log and receipt tables by copying every prior V5 revision/receipt at the same revision, then writes list/list-item bootstrap events.

A database-level partial unique constraint was intentionally not added because unknown legacy duplicate rows could make an incremental migration fail. Active duplicates are blocked by the Worker inside D1 serialization and by the local Store. A future maintenance migration may add a unique constraint only after a read-only legacy duplicate preflight and explicit cleanup plan.

`0028` was applied only to `food-map-db-development`. Production was neither queried nor migrated. Isolated Development test data was tombstoned and the final read-only cleanup check found zero active P4-F lists/items bearing the test markers.

## Acceptance coverage

The required scenarios are grouped into maintainable tests rather than one test per assertion:

- Contract tests: Unicode/trim/limits, duplicate titles, nullable Photo fields, Apple Maps-only identity, required primary identity, identity mismatch rejection, positions, tombstones, Sync envelope, and absence of WantToGo/private Visit inference.
- Worker integration: offline-style create/pull/idempotency, duplicate guard/cross-list allowance, independent metadata/item versions and stale conflict, owner isolation/forgery/direct ID, public/friends/private authorization and revocation, ordered allowlisted DTO/photo/pagination, cascade tombstones/no revival, and 100×50 summary performance.
- Native domain tests: create/rename/description/visibility/duplicate titles, identity and duplicate rules, shared list-only places, remove/delete semantics, reorder and durable queue, Store restart, parent/child dependency order, fresh-client hydration, viewer cache isolation, and 100×50 overview behavior.
- Native UI E2E: owner create/add five/reorder/edit/remove/public/share/restart; public Profile/detail/Restaurant navigation/WantToGo/restart/private revocation.
- Real Development E2E: isolated A/B users, Apple Maps-only items, incremental cursor, idempotent retry, fresh same-user pull, reorder, public pagination/DTO, B WantToGo using the same global identity, forged write denial, public-to-private revocation, cascade tombstones, and stale revival denial.

The two Simulator UI scenarios save XCTest attachments for visual review. Seventeen Preview variants cover the requested empty/small/large/ranked/photo/long-text/visibility/reorder/small-screen/large-type states.

## Known boundaries

- No global public-list search/square because it does not formally exist in the audited Web product.
- No collaborative editing, votes, official/AI lists, analytics, poster, or custom cover designer.
- Friends-only authorization uses the existing accepted-friend relationship. It does not introduce a new sharing graph.
- A legacy database unique constraint is deferred until duplicate preflight; runtime duplicate prevention is enforced now.
- P4-G is not started.
