# Final Privacy Consistency Audit — 2026-09-08

## Scope and evidence

Read-only audit of the current dirty working tree at `4d5fe935ff8658644ef2ecf3cfc872b87a9fcc50`, including iOS, Hybrid and Worker. No policy, permission, membership, database or App Store Connect changes were made. No D1 business queries, device installation, launch, cutover or upload.

A fresh generic-device **TasteMap / Release** build completed with `CODE_SIGNING_ALLOWED=NO`. This is an audit artifact, not the Private preview acceptance package or signed Final RC. Artifact: `build/FinalPrivacyAudit/Build/Products/Release-iphoneos/TasteMap.app`. Manifest hashes and effective plist keys are recorded in `build/FinalPrivacyAudit/privacy-artifact-evidence.json`.

Live `https://tastemap.cn/privacy.html` was fetched over HTTPS, rather than inferred from an old report. App Store Connect login succeeded, but the native browser observation tool subsequently returned an empty window and unavailable screenshots even after the user foregrounded Chrome. **The published App Privacy field values have not been read; their existing published/completed status is not being disputed.** No fabricated field difference is reported.

## Results

| Layer | Result |
|---|---|
| Privacy Manifest | PASS for current Release audit build |
| App Privacy | Published values not observable; comparison pending |
| Privacy Policy | NEEDS CHANGE |
| Info.plist permissions | PASS |
| MapKit handling | PASS for inspected code |
| Cloudflare handling | ISSUE: deletion/retention consistency |
| R2 handling | ISSUE: deletion completion boundary |
| Final privacy consistency | Not PASS; concrete issues below and ASC comparison outstanding |

## Concrete differences

1. Live policy section 5 still instructs the publisher to insert actual suppliers before launch. Worker/D1/R2 are already used. Replace the placeholder with the actual processing and recipients; this is a factual completion, not wording polish.
2. Live policy section 8 still asks the publisher to confirm/edit the account-deletion path before launch. The code already implements Settings/account deletion, fresh authentication, deletion jobs and retries. Publish the actual path and actual deletion behavior.
3. The policy covers account, location, visits, photos and public/friends content generally, but does not describe purchase/entitlement data processing: transaction/original transaction identifiers, app-account token/user linkage, product, environment, expiry/revocation and Apple verification/notifications. Gift/referral qualification and allocation also retain account-linked records. Add the actual scope; do not imply payment-card collection.
4. `worker/accountDeletionV1.ts:146` selects at most 1,000 pending objects; line 166 calls `finishDeletion` without checking whether more pending objects remain. More than 1,000 objects can leave R2 data while the job says completed. Since original and thumbnail are separate objects, this is not equivalent to 1,000 photos. This finding is static code evidence, not a claim that the current user's deletion was run or failed.
5. `worker/accountDeletionV1.ts:215` and `:216` retain visit/restaurant content with `deleted_at`; no production retention/purge implementation for those records was found. Clearing users/email/auth identities does not remove the retained locations/notes linked by user ID. The live policy's necessity/backup/retention wording does not establish a bounded lifecycle for this data. Define and implement the actual removal/anonymization lifecycle, keeping justified financial/security retention explicit. Do not claim that soft deletion is physical erasure.

## Data inventory for comparison with the published ASC fields

This is the code-derived inventory, **not a claim about ASC's current selections**. Tracking/ad targeting/data-broker use was not found in inspected first-party code.

| Category | Actual processing / linkage / purpose | Processor |
|---|---|---|
| Contact Info | Display name and Apple-provided email, linked; login/profile functionality. No phone/address-book permission found. | Apple authentication; Worker/D1 |
| Identifiers | Apple subject, Taste Map user ID, auth/session IDs, app-account token; linked; authentication, ownership, sync, entitlement. | Apple; Worker/D1 |
| Location | Current foreground location for map/search/distance; restaurant coordinates and city persist with owned records. Linked; functionality/personalization. No continuous background movement history found. | Apple MapKit; Worker/D1 |
| User Content | Restaurants, visits, ratings, notes, lists, comments, profile, moderation reports and explicitly shared import text/URL. Linked; functionality/personalization. Sharing a selected URL is not passive browsing-history collection. | Worker/D1 |
| Photos / Videos | Selected/captured photos, avatars, thumbnails; linked; functionality. No video workflow found. Re-encoded JPEG output does not copy original GPS metadata in the inspected importer. | Worker/R2 and D1 metadata |
| Contacts | Follow/friend/companion/source relationships constitute a social graph; linked; functionality/personalization. This does not mean reading the device address book. | Worker/D1 |
| Purchases | StoreKit transactions, original transaction IDs, product, entitlement dates/revocation, Gift/Referral grants/allocation. Linked; functionality and Premium personalization. No card details handled. | Apple; Worker/D1 |
| Usage Data | Recommendation preferences/events and social interactions; linked; functionality/personalization. No third-party advertising analytics SDK found. | Worker/D1 |
| Diagnostics | Local bounded device diagnostic file exists. Explicit Worker error logging emits type/status; development sync logs emit timing/counts. Cloudflare observability is enabled. Do not equate local diagnostics with developer collection; deployment-level invocation-log retention/fields need separate confirmation. | Local device; Cloudflare logs |
| Other Data | Anti-abuse public-share actor uses a hash of connecting IP. Treat hashing as pseudonymization, not proof of anonymity. Do not add an arbitrary Other Data field until ASC category/purpose applicability is checked. | Worker/D1 rate-limit processing |

Apple definitions used: https://developer.apple.com/app-store/app-privacy-details/ (including Contacts/social graph and Apple-only payment data) and https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype .

## Manifest and permissions

All four manifests are actually present in the new Release artifact: main app, Share Extension, Capacitor and Cordova. Main and extension hashes match the source manifests. SDK manifests declare no tracking/collection/required-reason APIs; no contradictory declaration was found.

Main required reasons: FileTimestamp `C617.1` for app-managed cache/temp file cleanup; UserDefaults `CA92.1` for app-owned settings. Both remain in actual use. No additional first-party uptime/disk-space/address-book required-reason usage was found in the inspected sources. Existing ten collected-data categories match the core inventory; don't rewrite the manifest speculatively for infrastructure logs.

Effective Release permissions are exactly:

- `NSLocationWhenInUseUsageDescription`: location manager requests When In Use; no Always or background-location key.
- `NSCameraUsageDescription`: user-initiated camera capture and camera authorization exist.
- `NSPhotoLibraryAddUsageDescription`: `AnalysisPosterServices` saves posters using PHPhotoLibrary `.addOnly`.
- PhotosPicker/PHPicker select media without full-library read permission. No `NSPhotoLibraryUsageDescription` is present or needed for these inspected paths.
- UNUSED PERMISSION KEYS: none found among these permissions.

## Provider and capability details

- MapKit is used for maps, place search and navigation, not just location display. Current coordinates may be supplied for searches/distance filters. Saved restaurant coordinates persist in sync/D1. The policy must not say that no location ever leaves the phone.
- iOS Hybrid delegates native acquisition/map capability to the native layer. AMap JS dependency also exists for Browser behavior; dependency presence alone is not evidence of an iOS AMap network call. Do not silently describe the entire Browser product as MapKit-only.
- R2 keys are owner/photo/variant scoped. Metadata contains `owner`, `photoId`, `variant`, `sha256`; HTTP caching is private/no-store. Reads enforce owner/visibility access; writes/deletes require ownership. Source controls do not independently prove the deployed bucket's public-development URL/custom-domain setting. No deployment setting was changed in this audit.
- Account deletion queues R2 objects and supports failures/retry, but has the completion bug above. Ordinary photo deletion requires a tombstone before object deletion.
- Apple sign-in verifies token claims and stores subject/email linkage. StoreKit server code verifies Apple-signed transactions and derives the transaction environment; credentials remain server-side. Notifications are verified and reconciled with account-linked purchase records.
- Gift/Referral implementation remains; hiding Referral UI does not erase already-held allocation/entitlement data or its privacy relevance.
- Share Extension enqueues explicitly shared text/URL in the App Group for the app; no independent network upload was found in the extension. Universal/public links use public-visibility projections, not unrestricted private record exposure.
- Blocking/reporting endpoints exist in `worker/moderationV1.ts`; comments and social graphs have visibility/ownership rules. The policy's generic social/security language covers the broad purpose, but the purchase/deletion/provider gaps above remain.
- No Firebase, Sentry, Mixpanel, Amplitude, IDFA or ATT integration found in inspected shipping first-party code. The app's dining “analytics” feature is not evidence of third-party analytics tracking.

## Files and ASC changes

Actually requiring correction: `worker/accountDeletionV1.ts` (R2 completion; D1 lifecycle), plus the website source that publishes `https://tastemap.cn/privacy.html`. No local `privacy.html` source was located in this repository/Projects filename search; do not edit an invented source or deploy from the fetched HTML.

No change presently indicated for Info.plist permission keys or existing manifests. No specific ASC field change is asserted before reading the actual published fields. Obtain the published App Privacy detail screenshot/export to complete that comparison; it does not require re-entering or re-publishing all fields.
