# Saved profile avatar blank — 906.33

## Root cause and scope

Native Profile editing saved and displayed the avatar correctly. The Native
profile DTO supplied an opaque avatar photo ID, but `projectBridgeProfile`
discarded its display source. `UserAvatar` then passed the ID to `SyncedImage`,
whose Browser Dexie/Drive resolver found no corresponding Browser photo and
returned null. Both Profile header and owner TasteFootprints share this path,
so both displayed an empty circle. This is distinct from Restaurant avatars and
the newly separated Restaurant content-image rules.

## Shared correction

- Native profile projection preserves the ID and adds its existing authenticated
  `tastemap-resource://photo/<encoded ID>/display` source. No raw file path,
  credential or additional API permission is exposed.
- The shared photo resolver does not re-query Native resource descriptors in the
  unrelated Browser photo namespace. Native's existing owner/deleted/binary
  checks remain authoritative. Browser photo-ID lookup is unchanged.
- UserAvatar supplies the existing selected preset during loading, absent bytes
  and image failure instead of an empty circle.

Same-semantic inventory: owner Profile header, owner TasteFootprints authors,
Browser Profile/public Profile/people rows, Friends, Browser Community, linked
companion avatars all use UserAvatar. Native profile editor and Native Profile
already read the owner photo directly and were not changed. Restaurant image
renderers, different public-author preset-only surfaces, extension UI and public
photo authorization are not repurposed by this correction.

## Validation and artifact

- 37 tests passed in photoAssets, TasteMapPlatform, RestaurantContentImage and
  RestaurantAvatar suites. Coverage includes three Native resource hosts,
  opaque ID encoding, no-avatar state, Browser lookup and inline-image behavior.
- Formal stage/build succeeded; 26 files match byte-for-byte in dist, formal
  staged resources and built .app.
- Branch `feature/hybrid-final-integration`, baseline
  `58bd556b8382734aeae1f08937ba649563682140`, existing dirty changes preserved.
- `TasteMap QA` / `DebugQA`, version 906.33;
  `/tmp/tastemap-analytics-results-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Exact artifact installed without uninstall on iPhone 17 Pro / iOS 26.5,
  simulator `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`, bundle
  `com.lafayette.tastemap.qa`. No launch arguments or custom environment;
  compile-selected hybridDevelopment / rich isolated QA fixtures.
- Actual flow: Profile → avatar editor → Photos → same built-in leaf image from
  the reported screenshot → Save → Profile. Photo appears in header, not only
  editor preview. Page-down to TasteFootprints shows the same leaf avatar in
  three records, including the reported Rainy Hotpot 1 and Wildfire Yakitori 1.
  Restaurant imagery, ratings, notes and private visibility stay intact.
- No real account, physical phone, production deployment or private DB action.

Evidence: `/tmp/tastemap-90633-tests.log`, `/tmp/tastemap-90633-stage.log`,
`/tmp/tastemap-90633-build.log`, `/tmp/tastemap-90633-profile-avatar.png`,
`/tmp/tastemap-90633-footprint-avatar.png`.

## Design System Compliance

Core UI: existing avatar size/crop/border and preset reused; no layout changes.
Food & Dining: Restaurant artwork and avatars unchanged.
Canonical Templates: Profile and activity information architecture preserved.
New duplicate components: 0. Default-SwiftUI visual regressions introduced: 0.
No new design-system gap; public-author preset-only migration and production
cross-device/avatar delivery remain separate acceptance scopes, not claimed here.
