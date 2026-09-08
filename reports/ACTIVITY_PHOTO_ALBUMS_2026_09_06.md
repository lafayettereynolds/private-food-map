# Activity photo albums — 2026-09-06

## Outcome and scope

Local implementation and isolated Hybrid layout acceptance PASS. Production rollout is HOLD; this report does not accept the complete live feed, real-device delivery, friends-session content or all earlier product tasks.

- Same Taste now uses the shared activity-card media variant, as Following/Latest do. For You/Trending hero semantics are unchanged.
- One square; two equal squares in one row; four in 2×2; three and five-plus in three columns. The initial nine-photo limit is display-only with an expand-all action.
- Browser, Native Codable/cache and Hybrid DTO preserve actual Visit albums and ID-only photos. A populated album does not borrow photos from another Visit/author. No export rights are added.
- Free Visit allowance is 2, Premium remains 20. Old 3/20-photo records survive unrelated edits. Browser save, Native save and Worker source have quota guards; Worker was not deployed.
- Native rollback shares the existing media presentation and read-only full-screen album. No new page renderer or route ownership was introduced.

## Verification

- Full JavaScript: 114 files / 942 tests PASS, `/tmp/tastemap-activity-full-js-final.log`.
- Real Browser editor + adapter + isolated IndexedDB probe: free 3 selected → 2 saved; direct third-photo bypass rejected; Premium 21 selected → 20 saved; old 3/20-photo notes edits retain photos. Script: `hybrid/scripts/check-visit-photo-entitlement.mjs`.
- Browser actual HybridDiscoveryPage: 48 layout cases PASS, 375/402 widths × light/dark × 1/2/4/5/6/7 × Same Taste/Latest. Twenty-photo expand/collapse and restaurant navigation callback also PASS. Script: `hybrid/scripts/check-activity-media-layout.mjs`; results `/tmp/tastemap-activity-media-layout-result.json`.
- Swift bridge package: 40 tests PASS, `/tmp/tastemap-activity-core-swift.log`.
- Xcode Debug: 39 native tests across Premium entitlement, Hybrid writes and public-footprint/photo projection PASS. Full Simulator UI test `testHybridActivityAlbumsKeepTwoAndLargerPhotoLayoutsConsistent` PASS: each 1/2/4/5/6/7-photo card in both feeds is scrolled into view and count/square geometry/two-photo same-row/cross-feed sizes verified. Result `/tmp/tastemap-activity-albums-debug-retry.xcresult`.
- All ten 2/4/5/6/7-photo Simulator screenshots were visually reviewed, not just inferred from test success. Twelve screenshots including single-photo controls: `/tmp/tastemap-activity-albums-accepted/manifest.json`.
- Release build and purity scan PASS: 40 app files, 18 signed Web files. No debug fixture, development URL or test switch in Release. Release app: `/tmp/tastemap-gps-coordinate-release/Build/Products/Release-iphoneos/TasteMap.app`.

## Runtime artifact identity

- Branch `feature/hybrid-final-integration`, base HEAD `58bd556b8382734aeae1f08937ba649563682140`, existing dirty integration tree preserved; no commit/reset.
- Formal `pnpm run hybrid:stage:formal` PASS; dist/staged/built/installed 18 Web resources match byte-for-byte.
- Fixed Simulator `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`, iPhone 17 Pro / iOS 26.5.
- UI tests use Debug, `--tastemap-hybrid-development`, `TASTEMAP_VISUAL_QA_MODE=rich`: React Hybrid, not Native rollback. DebugQA lacks test-target configurations, so two initial DebugQA test attempts failed configuration/linking; no tests were accepted from those attempts.
- User-facing QA restored after tests: `com.lafayette.tastemap.qa`, version `906.18`, built `/tmp/tastemap-activity-albums-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`; installed `/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/0AD5FB1C-AFDD-48DA-BE9E-F8FCF462BAC2/TasteMap.app`.
- QA launch: `TASTEMAP_VISUAL_QA_MODE=rich`, `TASTEMAP_CORE_PARITY_INITIAL_TAB=discovery`, no saved data erased. The seventh QA image is explicitly labeled `QA PHOTO 7`; test images never entered real records.
- No real-device install in this task; earlier phone build remains separate and is not multi-photo acceptance evidence.

## Design System Compliance

- Core UI: common activity-frame/gallery tokens, square aspect, existing card regions/actions retained. Food visuals: typed source descriptors and existing canonical Native loader; no page-local provider-photo or export fallback. Canonical template: Same Taste/Following/Latest activity layout, system recommendation hero unchanged.
- React and Native rollback share their respective semantic primitives rather than adding per-feed variants. Native uses the existing read-only gallery, not default-SwiftUI replacement cards.
- Remaining pre-existing visual gaps observed: reason truncation, left/right action visual-weight mismatch, and content painting beneath the status bar on long scrolls are not fixed or accepted by this photo-layout task.

## Explicit open issues / deployment HOLD

1. New Worker response has not been deployed: live Same Taste may still lack `activity.photos`, live Latest still has the old four-photo cap. Do not claim live 5/6/7-photo acceptance from fixtures.
2. A public Visit containing friend-visible photos correctly gets friends cache scope for that friend. Hybrid currently reads persisted content without an owner/session-scoped transient friends overlay; LocalDiscoveryStore/LocalCommunityStore intentionally do not persist friends content. Deploying the new mixed-visibility response before adding that overlay could hide the entire card. Keep Worker deployment HOLD; never mark friends content public as a workaround.
3. Separate unfinished `discovery.page` session snapshots are not yet included in Native resource authorization/interaction handling. New city/page photo IDs can be rejected when absent from old persisted caches. Normal Browser Hybrid feed producer and real city/cursor UI remain open.
4. Independent read-only security finding: `photoBinaryV1.readablePhoto` does not fully check bidirectional blocks, actioned moderation or deleted Restaurants. New feed metadata is filtered, but already-known IDs/old caches need separate binary-denial regression and fix. No claim of complete revocation acceptance.

The treasure-chest candidate remains paused/default off. This task does not close GPS, analytics, profile, recommendation explanation or other backlog items by implication.
