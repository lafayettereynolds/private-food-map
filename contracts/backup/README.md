# Taste Map Backup v1 Contract

`backup.v1.schema.json` is the normative cross-platform shape for future iOS/Web exports. It is a new lineage identified by:

- `format = "com.tastemap.backup"`
- `schemaVersion = 1`

The current Dexie dump (`app = "Taste Map"`, `version = 4`) is a separate `legacy-web-v4` lineage. A larger legacy version number does not mean it is a newer revision of Backup v1.

## Authority boundary

Every entity `id` is a stable backup identity used to keep references inside the document. It is not a provider ID, authenticated owner, server ownership proof, or permission to overwrite a server row.

Backup v1 intentionally has no `ownerUserId`, `userId`, remote ID, server version, auth identity, session, social acceptance, role, membership, entitlement, StoreKit authority, sync state, provider credential, or local file path. Import assigns new IDs unless a Worker later proves an ID belongs to the currently authenticated `tm_...` user. Restore may preserve an ID only after that proof.

`sharedMealReferenceHint` is the only social reference hint. It cannot recreate membership/acceptance and must be discarded unless a future authenticated server preflight confirms the current user still owns that relationship. Dining Companion and Recommendation Source do not carry linked Taste Map user IDs.

The current `DiningCompanion` business model has only a user-authored display name (no companion type, notes, or tags), so v1 preserves `id`, `displayName`, and timestamps instead of inventing fields. `RecommendationSource` separately preserves its existing user-authored `displayName` and `sourceType`.

Restaurant IDs remain Taste Map IDs. AMap, Apple Maps, manual, and other identities live only in `placeIdentities[]`; exactly one is primary. No cross-provider probable match may auto-merge without user confirmation.

Restaurant-specific visibility does not exist in the current P0 Restaurant model/contract. Backup v1 therefore does not invent one. Existing user-controlled visibility is retained where it actually exists: Visit, Photo, Profile, and Restaurant List.

## Required, nullable, and absent

All entity keys in the schema are required. A field whose business value may be empty is encoded as an explicit JSON `null`; omission is not a default. Fields excluded for security are absent, not optional. Unknown v1 fields are rejected by `additionalProperties: false` before DTO decoding.

Deleted records are not duplicated in `entities`. They are represented only as minimal tombstones containing `entityType`, `id`, and `deletedAt`. A tombstone is negative evidence for merge/restore; it is never remote-delete authorization.

## Decimal and time

All money is a JSON string matching `^(0|[1-9][0-9]{0,15})\.[0-9]{2}$`, for example `"128.50"`. Money is never a JSON number and never passes through a binary floating-point DTO.

All dates are absolute UTC instants with exactly millisecond precision: `YYYY-MM-DDTHH:mm:ss.SSSZ`. Backup v1 does not infer or add an original timezone.

## Photo v1

`scope.includesPhotoBinaries` is permanently `false` for schemaVersion 1. Photo records contain metadata and one typed parent reference only. They never include binary, sandbox/cache/temp paths, upload state, retry state, Google account/file IDs, R2 keys, provider credentials, or signed URLs. Consequently, the JSON file alone cannot guarantee recovery of original photos.

## Canonicalization and integrity

The canonicalization identifier is `tastemap-backup-v1`.

Before hashing:

1. The `integrity` object is omitted. Every other top-level field is covered, including `exportId` and `exportedAt`.
2. JSON object keys are emitted in ascending ASCII key order. Contract keys are ASCII.
3. Entity arrays are ordered by stable `id`, except `restaurantListItems`, which are ordered by `(listId, position, id)` to preserve business order.
4. Tombstones are ordered by `(entityType, id)`.
5. `placeIdentities` are ordered by `(provider, externalId)`.
6. Unordered string sets (`tags`, tag groups, dining occasions, Companion references) are ordered by their UTF-8 bytes and contain no duplicates.
7. List item arrays and any explicitly ordered arrays retain their specified business order.
8. Object key ordering is recursive; array order is preserved. Strings use standard JSON escaping without optional `/` escaping and UTF-8. Finite numbers use the `JSON.stringify`/ECMAScript shortest round-trip spelling: negative zero becomes `0`, decimal notation is used from `1e-6` (inclusive) to `1e21` (exclusive), and normalized exponent notation is used outside that range. Exact integers must remain within JSON's interoperable safe-integer range; money remains a decimal string.

The digest is lowercase SHA-256 over the UTF-8 bytes of that canonical JSON and is written to `integrity.digest`. SHA-256 detects accidental content changes only. It is not encryption, a signature, proof of who created the file, proof of account ownership, or proof for Legacy Claim.

For identical user business data, the business arrays and records must canonicalize identically. `exportId`, `exportedAt`, and therefore the final digest are expected to change between separate exports.

## Golden fixtures

The `fixtures/` directory contains:

1. full envelope;
2. minimal envelope;
3. nil-heavy Visit;
4. provider-neutral Restaurant with multiple identities;
5. Apple Maps-only Restaurant;
6. AMap-only Restaurant;
7. manual Restaurant;
8. minimal tombstone;
9. Dish + VisitDish;
10. metadata-only Photo;
11. Dining Companion;
12. Recommendation Source;
13. sanitized Profile;
14. List + ordered items;
15. legacy Web v4 lineage fixture;
16. a table-driven forbidden-field security fixture.

F1-B1 defines DTOs and validates fixtures only. It does not implement exporter, importer, restore, dry-run, merge, Worker routes, D1 migrations, photo packages, or encryption.
