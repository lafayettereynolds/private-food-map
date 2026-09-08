# Complete rating filters — 2026-09-05

## Result and scope

Map/List minimum rating now offers clear plus every integer 1–10. Existing `>=` semantics remain; 10 means full score, not an impossible `>10`. Discovery also retains its existing 7.5 shortcut. Public evidence eligibility and stored ratings are unchanged. No private or real-device data was edited or installed.

## Shared consumer inventory

- React Browser / Capacitor Map and List: shared `MapFilterBar` in `MyMapBrowsePage`, shared `ratingFilterOptions` semantic primitive; existing sized native select and filter grammar retained.
- React Hybrid Discovery and Browser Community recommendation filters: shared thresholds/labels, no high-score-only local arrays.
- Native rollback Discovery: matching `TasteMapRatingFilterOptions`, with explicit conversion from visible ten-point score to existing five-point storage.
- Native rollback Map and the older Browser/full Map sheet use multi-select score bands covering the whole score range already. They have different range semantics and were preserved.
- No extension-specific minimum-rating picker found. No new renderer, route, provider, DTO, eligibility or account authority.

## Verification

- 86 TypeScript tests pass across rating options/real select SSR, Browser map query, Discovery policy, Hybrid Map and global Product contracts. Every integer threshold is applied inclusively, unrated excluded under a threshold, restored on clear, and total Restaurant scope counts unchanged.
- 32 Native MapBrowsingParity tests pass, including complete rating choices and legacy score conversion semantics: `/tmp/tastemap-rating-filter-native.xcresult`.
- Fixed QA UI test passes Map menu all ten scores, 1/10 selection and clear, List same menu and Discovery menu with 7.5 preserved: `/tmp/tastemap-rating-filter-ui-2.xcresult`.
- Initial UI attempt opened the system menu during first-paint updates and it disappeared. Final test waits for real annotations and initial paint before interacting; this is not evidence that the separate shell-refresh defect is fixed.
- Typecheck, Release local-resource purity, formal stage and built/installed byte-for-byte verification pass (16 files); installed executable exactly matches the built executable.

## Artifact and screenshots

- Branch `feature/hybrid-final-integration`, base HEAD `58bd556`, pre-existing dirty worktree preserved.
- Build `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Simulator `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`; bundle `com.lafayette.tastemap.qa`; React Hybrid + persistent Native MapKit; explicit rich QA fixture, not real restaurant evidence.
- Installed `/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/099E3D13-0ACC-455E-9807-1B92B3CDC6C3/TasteMap.app`.
- Map menu: `/tmp/tastemap-rating-filter-screens/1BF74CBD-0497-448A-B817-904263654DB0.png`.
- Full-score selection: `/tmp/tastemap-rating-filter-screens/8C1AA91B-836F-46A4-A7C0-836DCA8AF07B.png`.
- List menu: `/tmp/tastemap-rating-filter-screens/671207F6-F222-40D0-A6FB-EF7572FB3AAB.png`.
- Discovery menu: `/tmp/tastemap-rating-filter-screens/A7DE912D-6258-4399-B1C3-E8E92ED6D217.png`.

All four screenshots were visually inspected: clear ordered options, full-score selected state, same filter/menu treatment, preserved header/scopes/navigation. These fixture images validate controls only, not real restaurant/geographic data.

## Design System Compliance

- Core UI: PASS for the scoped filter correction; shared controls, native system menu, existing hit targets and sizing, no CSS/token scale fork.
- Food & Dining: unchanged, no image or marker-source changes.
- Canonical Page Templates: PASS for inspected Map/List/Discovery filter regions; route ownership unchanged.
- New duplicate/conflicting renderers: 0; introduced default-SwiftUI visual variants: 0.
- Remaining gaps: Browser live-provider visual acceptance and real-device interaction smoke not rerun. Separate search/location, inconsistent QA-city coordinates and shell refresh/reset problems remain open; this work does not claim to fix them.
