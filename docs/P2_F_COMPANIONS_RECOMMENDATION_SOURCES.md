# P2-F dining companions and recommendation sources

## Web audit and product semantics

P2-F uses the existing React/Web domain as the semantic baseline. It does not reinterpret free-text people as contacts or friends, and it does not turn a recommendation into a social relationship.

| Product concept | Web field / code | Web shape | P2-F native and sync decision |
| --- | --- | --- | --- |
| People at one meal | `Visit.companions` | `string[]` snapshots | Keep multiple user-entered display names per Visit |
| Stable people references | `Visit.companionIds` | `string[]` | Reference private `DiningCompanion` identities in the same order |
| Reusable people directory | `DiningCompanion` in `src/types/index.ts`, IndexedDB and Worker | owner-scoped record; optional `linkedUserId` | SwiftData entity + Sync V1 `companion`; no Contacts access and no friendship requirement |
| Recommendation kind | `Visit.recommendationSourceType` | `friend/xiaohongshu/douyin/dianping/blogger/self/other` | Same enum values; optional |
| Recommendation name | `Visit.recommendationSourceText` | free text | Preserve as a historical Visit snapshot |
| Recommended-by user | `Visit.recommendationSourceUserId` | nullable Taste Map user reference | Optional link only; never inferred from a typed name |
| Stable source reference | absent in legacy Web | none | Add private `RecommendationSource` identity and `Visit.recommendationSourceId` while retaining all legacy fields |
| Shared meal | `Visit.sharedMealId` | nullable | Contract preserved; no shared-meal or social UI added in P2-F |

Web analytics currently treats the earliest source-bearing Visit for a Restaurant as that Restaurant's acquisition source. P2-F preserves this behavior by keeping recommendation source data on each independent Visit. It does not move source ownership to Restaurant and does not change analytics UI.

## Identity and normalization

`DiningCompanion.id` and `RecommendationSource.id` are stable Taste Map UUID/string identities. A display name is user-controlled presentation data and can be renamed without changing the identity or historical Visit linkage.

Private-directory matching uses Unicode NFKC normalization, trims the edges, and collapses whitespace. It deliberately remains case-sensitive: `Alex` and `alex` are not silently merged. An exact normalized duplicate under one authenticated owner is reused locally and rejected as a conflict by Worker if two devices race to create it. No fuzzy merge is attempted because merging two real people is more damaging than leaving an explicit duplicate for future user review.

Each Visit stores both IDs and snapshots. Current detail UI resolves an active directory name by ID and falls back to the Visit snapshot when the directory entry is unavailable or tombstoned. Renames therefore appear consistently while old records remain readable after deletion.

## JSON contract

All directory fields are explicit; TypeScript and Swift do not guess omission semantics.

### `DiningCompanionSyncContractV1`

| Field | Contract |
| --- | --- |
| `schemaVersion` | required literal `1` |
| `id`, `userId`, `displayName` | required non-empty strings; `userId` has no authorization power |
| `linkedTasteMapUserId` | required, nullable string |
| `createdAt`, `updatedAt` | required ISO timestamps |
| `deletedAt` | required, nullable ISO timestamp; network deletion normally travels as a mutation tombstone |

### `RecommendationSourceSyncContractV1`

It has the same required identity/owner/timestamp/nullability fields plus required `sourceType`, one of `friend`, `xiaohongshu`, `douyin`, `dianping`, `blogger`, `self`, or `other`.

### Visit projection

Every new Visit payload explicitly sends `companions: string[]`, `companionIds: string[]`, nullable `recommendationSourceId`, nullable `recommendationSourceType`, nullable `recommendationSourceUserId`, nullable `recommendationSourceText`, and nullable `sharedMealId`. Legacy payloads that omit them decode as empty arrays or `null`. Non-empty `companionIds` must be parallel with snapshots.

## Local-first behavior

Creating, editing, associating, and removing a companion/source completes in SwiftData first. Directory mutations are durable in the same SwiftData store and are queued before Visit mutations, so a Visit cannot reach Worker before its private parent identities. App termination does not remove the queue. Cloud failure never makes local Visit save fail.

Removing a companion or source from one Visit only clears that association. It does not delete the directory record or touch another Visit. Explicit directory deletion is soft-delete/tombstone once the record has a server version; a never-uploaded record and its queued mutations can be removed locally.

## Sync, authorization, and conflicts

Sync V1 adds `companion` and `recommendationSource` entity types and returns owner-scoped `companions` and `recommendationSources` arrays. Mutation IDs retain server-side idempotency. `baseVersion/serverVersion` remains the conflict authority; device time is not Last Write Wins. Tombstoned entities reject stale upserts and cannot be revived by an older device.

Worker always derives the owner from the authenticated session/development test identity, overwrites payload `userId`, and verifies that a Visit references only the authenticated user's active Restaurant, companions, and recommendation source. Another user cannot read an owner's private directory, take over an entity ID, or attach it to a Visit. Optional linked Taste Map user IDs remain relationship metadata and are not authorization.

## D1 migration 0021

Migration `0021_companions_recommendation_sources_sync.sql` is additive:

- retains the existing Web `dining_companions` table and adds normalized lookup, version, and last-mutation metadata;
- creates owner-scoped `recommendation_sources`;
- adds nullable `visits.recommendation_source_id` while keeping all legacy Visit source columns;
- copies V3 revisions and idempotency receipts into V4 ledgers whose entity checks include the two new entity types;
- bootstraps existing companion rows into the incremental change log without rewriting or relinking Visit data.

The D1 migration intentionally does not bulk-convert or link legacy recommendation free text: equal text is not proof of a single real-world source. Existing `companions_json`, `companion_ids_json`, recommendation fields, Restaurant/Visit IDs, and Visit/Restaurant relationships remain intact.

On a fresh native pull, a legacy Visit whose browser-owned companion directory was never stored in D1 is materialized into the local private directory from its stable ID/name snapshots. Legacy non-empty recommendation source text is likewise materialized locally with its existing type. These compatibility entries enter the ordinary offline mutation queue; no migration rewrites the original Visit or guesses links between unrelated legacy names.

## Migration risks and rollout

Before applying 0021, Development preflight checks pending migrations, blank IDs/names, normalized duplicates, existing Visit arrays, and source-bearing Visits. A deployment with duplicate normalized names remains readable; Worker prevents new ambiguous records, but automated merging is forbidden. Legacy rows with only source text remain unlinked until an explicit future reconciliation flow.

Apply 0021 to the isolated Development D1 before deploying the Worker version that reads V4 ledgers. Production D1 and Production Worker are outside P2-F scope and must not be queried, migrated, written, or deployed.

## UI scope

The Visit editor supports zero or multiple companions and zero or one recommendation source. Users can search, reuse, or add their own names; recent/frequent records sort first. All controls are optional, a minimal Visit still saves, no Contacts permission is requested, and no friendship is created. Restaurant Detail shows the information only when present. P2-F does not add analytics, profile, community, or P2-G UI.
