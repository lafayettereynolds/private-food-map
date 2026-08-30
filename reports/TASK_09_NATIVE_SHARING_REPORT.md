# Taste Map Task 09 Acceptance Report

## Scope

Task 09 completes native inbound sharing through an iOS Share Extension and privacy-safe outbound public sharing for Restaurant, Profile, and public Restaurant List content. The implementation is based on `main` after Task 08 and does not include Production changes.

## Git baseline

- Branch: `main`
- Baseline commit: `acccb8025cb0cc3425cf0634cdf4e75493d22474`
- Baseline message: `Implement StoreKit premium commerce`
- Required Task 09 commit message: `Complete native sharing integration`

## Native Share Extension

- Added the `TasteMapShareExtension` application-extension target to the existing Xcode project.
- Extension bundle identifier: `com.lafayette.tastemap.ShareExtension`.
- Existing Team ID and automatic signing configuration are preserved.
- The extension activates only for URL and text input; unsupported attachment types are not declared.
- The extension never reads or stores Taste Map access/refresh tokens.
- Shared input is written to an App Group pending-import queue and is consumed only by the main app.
- Pending imports are bounded to 32 KB, expire after seven days, are written atomically, and use a deterministic SHA-256 identifier to reject duplicate/replayed submissions.
- The main app routes pending input through the existing restaurant acquisition/search flow. It consumes the pending record only after a successful Want to Go or Visit action.
- Malformed URLs, non-HTTPS URLs, expired records, missing files, and path traversal attempts are rejected safely.

## Public sharing

- Added an authenticated `POST /api/v1/public-shares` endpoint that creates or returns a stable, opaque public URL.
- Added an anonymous `GET /api/public/shares/:shareID` endpoint that returns a strict public projection.
- Public share IDs are 24 random bytes encoded as 32-character base64url strings. Internal owner IDs, entity IDs, sync DTOs, Apple/AMap provider identities, and private fields are never returned.
- Restaurant sharing requires a public owner profile and at least one active public Visit.
- Profile sharing requires a public profile.
- List sharing requires both a public list and public owner profile. Only safe public list fields and safe restaurant snapshots are projected.
- Privacy/deletion eligibility is checked on every public read. Making content private or deleting it causes the existing URL to stop returning the content without rotating or guessing IDs.
- Owner identity is always derived from Worker authentication; a forged client `userId` or another user's entity ID cannot authorize sharing.
- Native Restaurant, Profile, and public List screens use the same public sharing service and the system share sheet/copy-link actions.
- The Web app now renders the public landing route from the same allowlisted anonymous contract.

## Associated Domains and Universal Links

- Development associated domain: `applinks:api-dev.tastemap.cn?mode=developer`.
- Development AASA response contains `7G5J9MJX88.com.lafayette.tastemap` and `/share/*`.
- Valid public URLs are routed to the native public landing view; malformed share paths are ignored.
- Production domain/capability configuration remains a Task 12 Release Gate.

## D1 migration

- Added incremental migration `0031_public_sharing.sql`.
- Creates `public_share_links` with stable share ID, authenticated owner, entity type/entity reference, timestamps, and revocation metadata.
- Adds unique ownership/entity and public lookup indexes.
- Migration is additive and preserves all pre-existing data.
- Applied only to isolated Development D1 `food-map-db-development` after a read-only migration preflight.
- Production D1 was not queried, migrated, or modified.

## Development E2E

Against `https://api-dev.tastemap.cn` and Development D1:

- Apple Maps-only Restaurant plus public Visit: passed.
- Stable/idempotent public Restaurant link creation: passed.
- Anonymous strict Restaurant projection: passed.
- Public Profile sharing: passed.
- Public List sharing: passed.
- Dynamic privacy revocation: passed.
- Forged cross-user ownership request: denied as expected.
- Isolated test records were cleaned using tombstones; test profiles were returned to private.
- Development Worker deployment verified at version `527d96fb-9876-4ef1-ad3a-284cb16977e5`.

## Automated tests and builds

- `pnpm run test:task09`: passed.
  - Incremental migration test: passed.
  - Worker public sharing integration: 6/6 passed.
- `TASTEMAP_API_DEV_BASE_URL=https://api-dev.tastemap.cn pnpm run test:task09:development`: passed.
- `pnpm run typecheck`: passed.
- `pnpm run build`: passed. The existing Vite large-chunk advisory remains and was not introduced as a build failure.
- iOS `Task09PendingImportTests`: passed for duplicate, expiry, malformed input, and safe queue behavior.
- iOS `Task09PublicSharingTests`: passed for contract decoding, route validation, create/read behavior, and failure handling.
- iOS Debug Simulator build: passed.
- iOS Release Simulator build: passed.
- Share Extension embedded-binary validation: passed in both Debug and Release builds.
- Share Extension and app entitlements/Info.plist files: `plutil` validation passed.

## Privacy and security boundaries

- No Cloudflare, D1, R2, Apple, or authentication secret was added to the iOS app or Git.
- No authentication credential is shared with the extension.
- Anonymous APIs use a strict allowlist and public rate limiting.
- A public URL does not grant access when the underlying visibility becomes non-public or the entity is deleted.
- Friends-only content is not made available through an anonymous public URL.
- Production Worker, D1, R2, migrations, and secrets were not accessed or modified.

## Manual / Release Gates

The following checks require an installed, properly provisioned build and are not reported as completed by simulator automation:

- Confirm the Taste Map extension appears in the physical iPhone system share sheet.
- Share a real Apple Maps place and a restaurant webpage into Taste Map.
- Confirm physical-device App Group transfer and user confirmation UI.
- Open a public link on device and confirm Universal Link routing to the app.
- Refresh Apple provisioning profiles for the new App Group/Share Extension/Associated Domains capabilities if Xcode requests it.
- Configure and validate the final Production sharing domain/AASA/capabilities in Task 12 after explicit Production approval.

## Result

Task 09 code and Development validation are complete. The remaining device and Production-domain checks are explicit Release Gates and do not block continuing to Task 10.
