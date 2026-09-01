# Task 13 — Privacy, Security, UGC, and Release Configuration

Date: 2026-09-01

Branch: `fix/product-ux-correction-8-tasks`

Production access: **none**

## Outcome

Autonomous code closure is complete. The main app and Share Extension now carry explicit, factual privacy manifests; the data-collection inventory is documented; UGC and account-deletion boundaries are covered by automated regressions; Production legal configuration continues to fail closed; DEBUG-only credential, fixture, and Premium implementations are compile-time excluded; and a signed Development archive passes the release binary scan.

No Production Worker, D1, R2, StoreKit product, App Store Connect record, real account, or real user data was accessed or changed.

## Privacy manifests and Required Reason APIs

### Main app

`TasteMap/PrivacyInfo.xcprivacy` declares:

- tracking: false;
- tracking domains: none;
- linked/app-functionality collection: Name, Email Address, User ID, Purchase History, Photos or Videos, and Other User Content;
- Required Reason API: File Timestamp with reason `C617.1`.

The file-timestamp declaration matches bounded cleanup of app-created backup and poster files. No `UserDefaults`, system-uptime, or disk-space Required Reason API call was found in the main or extension source.

### Share Extension

`TasteMapShareExtension/PrivacyInfo.xcprivacy` now explicitly declares no tracking, no data collection, and no Required Reason API access. The archive contains a separate privacy manifest in both the main app and extension bundles.

### Permissions

The target declares only the permissions its current code requests:

- Location When In Use: map position and nearby restaurant search.
- Photos add-only: explicit saving of generated analysis posters.

`PhotosPicker` handles user-selected photo input without broad library-read permission. No camera, microphone, contacts, tracking, notifications, or always-location usage description is present.

## Data collection map

The code-fact inventory is maintained in [`docs/TASTEMAP_DATA_COLLECTION_MAP.md`](../docs/TASTEMAP_DATA_COLLECTION_MAP.md). It covers authentication identity, Taste Map user ID, profile, restaurant/visit/dish records, transient location use, photos, social graph, UGC, lists/shares, purchases, diagnostics, and the absence of advertising analytics/device identifiers.

This inventory is evidence for—but not an automatic substitute for—Lafayette's final App Store Connect privacy answers and legal review.

## UGC closure

Verified in Worker code and automated tests:

| Capability | Verification |
|---|---|
| Report Visit content | authenticated reporter; reportable public/friends content; cannot report own content; idempotency fingerprint |
| Report comment | target must exist and not be deleted; cannot report own comment |
| Report user | target user must exist and not be deleted; cannot report self |
| Block/unblock | authenticated server identity; cannot block self; idempotent soft state |
| Relationship cleanup | blocking tombstones mutual follows and removes friendship |
| Feed suppression | blocked users are filtered in both directions |
| Comment suppression | blocked authors are filtered; blocked content cannot be read or mutated |
| Search/profile suppression | blocked users disappear from search and direct profile/content reads fail closed |
| Delete own comment | only the author can tombstone; non-owner receives not-found |
| Delete own Visit/content | existing owner-scoped local delete produces a sync tombstone; Worker sync authorization uses authenticated owner |
| Visibility | private content is never interactive; friends/public access follows profile and friendship state |
| Rate limits | dedicated server buckets for likes, reads, comment create/delete, reports, and blocks |

The Task 13 regression adds explicit Visit + comment + user report coverage and proves all three records remain scoped to the authenticated reporter even when a client supplies a decorative `userId` field.

Operational moderation owner, SLA, appeal workflow, and support contact remain Manual Release Gates; none were invented in code.

## Account deletion closure

Automated, in-memory D1/R2 verification covers:

- preview and deletion derive the target exclusively from the authenticated current user;
- a forged payload `userId` cannot delete another user;
- public shares and user-owned/derived social and business state are tombstoned or anonymized;
- auth identities are removed and sessions are revoked;
- R2 object deletion is durable and retryable;
- opaque status token is stored only as a server hash;
- identical confirm requests are idempotent;
- failed object cleanup resumes from its job without deleting another user's data;
- iOS local cleanup removes only the current account's SwiftData rows, mutation queue, checkpoint, caches, and owned photo files.

No destructive real-account smoke was performed.

## Release configuration

- Privacy, Terms, and Support URLs are centralized in `ReleaseConfiguration`.
- Only HTTPS URLs without embedded credentials are accepted.
- Missing Production URLs produce explicit validation issues and no visible fake links.
- Debug remains startable without legal URLs.
- The exact Development Worker hostname was removed from a Release-compiled forbidden-host check; generic `dev.` / `-dev.` rejection preserves fail-closed QR behavior without embedding the Development endpoint.
- `DevelopmentPremiumOverride` and its policy are now enclosed by `#if DEBUG`, matching all runtime entry points.

## Automated verification

### Worker / Web

- Release safety migration: PASS.
- Worker suites: **38/38 PASS** across release safety, Community, social collaboration, social, and auth.
- TypeScript application + Worker typecheck: PASS.
- Vite production build: PASS. Existing non-blocking chunk-size warning remains.

### iOS tests

- Task 13 privacy/security/release tests: **4/4 PASS**.
- Release Safety: **4/4 PASS**.
- Settings Foundation: **14/14 PASS**.
- Local multi-account isolation: **6/6 PASS**.
- Premium entitlement foundation: **12/12 PASS**.
- Combined selected run: **40/40 PASS**.
- Share-poster Release configuration regression: **3/3 PASS**.
- Final Task 11 + Task 13 rerun: **7/7 PASS**.

### Builds and archive

- Debug, fixed iPhone Simulator: PASS.
- Release, fixed iPhone Simulator: PASS after the final Release-host cleanup.
- Generic physical-device Release: PASS as part of archive compilation.
- Signed archive: PASS at `/tmp/TasteMapTask13Final.xcarchive`.
- Archive signature: valid, main app + Share Extension embedded validation PASS.

The current archive uses the available Apple Development signing identity/profile and therefore contains `get-task-allow = true`. Distribution signing remains a later manual release gate; Team, Bundle IDs, entitlements, and signing configuration were not changed.

## Release binary purity scan

Scanned the archived main app and Share Extension. The following are absent:

- Visual QA/UI-test/test-tier launch keys;
- `IsolatedAuthCredentialStore`;
- `TestNetworkBlockerURLProtocol`;
- `TasteMapUITestFixtures` and `TasteMapVisualQAFixtures` runtime types;
- `DevelopmentPremiumOverride`;
- fake StoreKit product IDs and `.storekit` fixtures;
- Development Worker URL and development-test auth marker;
- test-user header;
- `.p8` and private-key markers;
- Cloudflare/R2/App Store Connect secret markers.

Both privacy manifests are present in their correct bundle roots.

## Manual Release Gates

1. Configure verified Production Privacy Policy, Terms of Service, and Support HTTPS URLs.
2. Assign a moderation owner, response SLA, appeal route, and support channel.
3. Complete App Store Connect privacy answers from the factual data map with legal review.
4. Re-archive with the final Distribution signing/profile when available.
5. Perform non-destructive real-device UGC/report/block/account-deletion-preview smoke; do not confirm a real account deletion merely for release testing.

## Severity

- P0: 0
- P1: 0
- P2: 4 external/manual release gates above
- P3: 0

Task 13 is complete and can proceed to Task 14 autonomous Release Candidate audit.
