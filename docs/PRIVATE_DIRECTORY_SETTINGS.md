# Private directory settings — 2026-09-08

Status: implemented locally; not deployed or accepted as production-ready.

## Entry and semantics

Settings → 私人资料 → 饭搭子与推荐来源. This follows membership/referral sections and does not change the current NATIVE_PRIMARY route ownership. Browser/Capacitor use `TasteMapDirectoryPage`; the production Native/rollback entry uses `PrivateDirectorySettingsView`.

- A companion can request a link to a mutual-follow friend. The existing companion-link service requires recipient acceptance; reject, cancel and unlink reuse that service. Existing accepted friendship relationships remain supported by the server. Blocks are checked before either relationship path.
- A recommendation source can be privately attributed to a discoverable public user or mutual-follow friend; self-attribution, inaccessible users and blocks are rejected. This is not a public endorsement or permission to read the linked user's private data.
- Either kind can upload/remove a private custom avatar. The settings directory renders it; this change does not replace account Profile avatars, public avatars or poster/export imagery. Other historical analysis renderers are not migrated to these private images in this change.
- Existing records must be synced first. The new management operations require authentication and network access. Binding does not automatically copy, merge or publish Visit records.

## Data and APIs

Migration `0036_private_directory_profiles.sql` creates owner/kind/entity-scoped `private_directory_profiles` and payload-free `private_directory_audit`. Avatars are bounded, square JPEG thumbnails in private metadata, not public Photo pool objects. Avatar URLs require the owner's authenticated session and return `private, no-store`.

`GET/POST /api/v1/directory` reads/manages the current owner's directory. Source binding updates the existing `recommendation_sources.linked_user_id`, server version and `sync_change_log_v6`; it does not rewrite historical Visits. Companion requests remain in the existing consent/audit system. Avatar/source changes append action/owner/entity/target/time audit rows, without image bytes in audit output.

The typed bridge adds `directory.dashboard`, `directory.searchUsers`, `directory.mutate`, and `directory.respond`. Native photo selection returns an opaque pending ID; resizing, authenticated upload and image reads stay in Native. React never receives a raw file path, original image or credential. Avatar revision is retained in the resource URL so replacing an image invalidates its presentation identity.

## Verification and outstanding acceptance

- Focused server and Native-adapter tests: 31 passed, including mutual-follow consent, owner-isolated image reads/writes, source link/unlink + sync log, self/private-user rejection, payload limits, avatar removal and opaque photo IDs.
- Settings contract selection: 4 passed, 30 unrelated cases intentionally skipped.
- Full global Hybrid contract run: 76 passed / 2 failed. Failures refer to existing Discovery filter-sheet and city-change source expectations in files not modified by this feature. The earlier broader remaining-UI run also had unrelated Discovery/analytics expectation failures; it is not a clean full-suite acceptance.
- Debug and final Release Simulator compilation passed. `hybrid:stage:formal` and staged/built verification passed with 26 byte-identical Web files. Formal Release purity passed: 50 app files, no debug fixture/switch, development URL, local path/secret or React credential surface.
- Installed artifact: `/tmp/tastemap-directory-build/Build/Products/Release-iphonesimulator/TasteMap.app`, bundle `com.lafayette.tastemap`. Source: dirty `feature/hybrid-final-integration` at base commit `58bd556`. Fixed iPhone 17 Pro Simulator `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`, iOS 26.5; ordinary Release launch without fixture arguments or environment overrides. Renderer is the NATIVE_PRIMARY SwiftUI route, not a Hybrid screenshot.
- Visually verified Profile → Settings → private directory → Back using the installed Release app. Account, Premium, referral, new private-directory and data/backup groups remain ordered; guest state shows login required and no other owner's records. This verifies entry/back/guest rendering only, not the authenticated populated page or Browser/Capacitor acceptance.
- No remote migration, Worker deployment, production account mutation, App Store change or StoreKit product creation was performed.
- Real authenticated two-account image upload, acceptance, relaunch/cross-device persistence and Browser/Capacitor populated-state visual QA remain required after an isolated development deployment. Do not deploy the entire dirty working tree merely to activate this feature.

## Design-system compliance

Core: reuse shared back/header/Settings entry components, existing colors, 44-point hit targets and Native spacing/avatar tokens. Food & Dining: not applicable to private person/source initials; no decorative food imagery added. Canonical template: compact Settings management groups, preserving account/membership/referral ordering. React is shared between Browser and Capacitor; Native remains the explicitly retained production/rollback renderer, not a new Hybrid fork. Native list defaults and populated-state geometry still need the authenticated visual acceptance above.

## Main implementation files

- `worker/privateDirectoryV1.ts`, `worker/index.ts`, `worker/socialCollaborationV1.ts`
- `migrations/0036_private_directory_profiles.sql`
- `src/contracts/privateDirectoryV1.ts`, `src/services/privateDirectoryBrowser.ts`
- `src/components/TasteMapDirectoryPage.tsx`, `src/components/TasteMapPremiumSettingsPages.tsx`
- `src/platform/TasteMapPlatform.ts`, both platform adapters, `src/hybrid/app/HybridAppShell.tsx`
- `ios/TasteMap/TasteMap/Services/PrivateDirectoryService.swift`
- `ios/TasteMap/TasteMap/Features/Settings/PrivateDirectorySettingsView.swift`, `TasteMapSettingsView.swift`
- Native Hybrid contract/dispatcher/runtime and `Features/Profile/SocialCollaborationViews.swift`
- Shared CSS, focused server/platform tests, Settings information-architecture expectation, formal bundled resources.
