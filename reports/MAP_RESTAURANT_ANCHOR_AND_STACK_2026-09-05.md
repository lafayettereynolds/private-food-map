# Restaurant map anchors and real-image stacks — 2026-09-05

## Controlling request

The latest instructions supersede the earlier city-count experiment:

- Display all distinct Restaurant coordinates throughout city browsing, including dense areas. Natural image overlap is allowed.
- Higher finite ratings are in front. Recommendation rank, visit count and stable ID break ties; selection temporarily raises a marker without changing a regional representative.
- Never display numeric aggregation circles or quantity badges on map markers.
- At much wider scale, progressively retain an actual representative Restaurant, at that Restaurant's real coordinate.
- Exact-coordinate stacks must show actual member images, not concentric outline plates or copies of the front image. All records remain available in the member list.
- Keep the geographic anchor stable during zoom. Update the currently used simulator only; do not update the physical iPhone.

## Implementation and consumer inventory

- Native owner: `RestaurantMapView` / `RestaurantMarkerAnnotationView`. Shared by the Hybrid MapKit surface, Native Map rollback and public maps.
- Browser owner: shared `MapView` / `mapMarkerPriority`, also used by anonymous/static fallback and public map consumers. Capacitor retains the formal shared React page and member sheet with a typed native group-selection event.
- The annotation/hit box is fixed at 44 pt, with zero center offset. The normal visible outer circle is 28–32 pt. Only centered inner contents change size; stored coordinates and MapKit annotation centers are never moved to free slots.
- City spans through 0.8 degrees retain distinct locations. Regional consolidation ramps between 0.8 and 2.4 degrees. These are zoom controls, not inferred administrative boundaries.
- Only exact coordinate equality creates a city stack. Nearby but distinct locations remain independently drawn at their own coordinates.
- A same-coordinate composite has its highest-priority member at the geographic anchor and at most two actual member images behind it. Back-layer content offsets are fixed at `(-10, -8)` and `(8, -10)`; independent annotations are not displaced. Each layer retains its own image/fallback and rating ring.
- All images use the existing Restaurant image policy and cached loader. Back-member tasks have separate host/member keys; identity, image resolution and generation guard both successful and failed asynchronous completions.
- Hidden annotations and internal image layers are excluded from duplicate accessibility identities. The visible stack's action opens the complete real member list.

## Simulator delivery

- User-visible device: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405` (iPhone 17 Pro, iOS 26.5).
- Scheme/configuration: `TasteMap QA` / `DebugQA`; installed bundle `com.lafayette.tastemap.qa` (味图测试), version 1.0 (1).
- Build: `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Formal React assets: `index-kUFHLReJ.js`, `index-njSCZla4.css`. Staged, built and installed resources were compared byte-for-byte (16 files).
- Final installed Native debug library also matches the built library: SHA-256 `1c81fd617c13755809746439daf4c941774890d81b28939c3b2de7da447e6244`. This checks the Swift implementation, not merely the unchanged app launcher or version string.
- Actual running QA screenshot: `/tmp/tastemap-real-restaurant-stack-live-20260905.png`. It shows existing QA data, not a mockup or edits to production records.
- No physical-device install, account mutation, production-data change, app deletion or repository commit was performed.

## Verification

- Browser/shared map and platform/product contract tests: 89 focused tests passed; TypeScript check and `git diff --check` passed.
- Native map unit suite: 30 tests passed, including actual distinct stack images, image reuse/generation, high-score order, fixed front-circle geometry and reversible regional grouping.
- Dedicated isolated simulator: `5C24CBC2-5E24-4D82-B7DD-FB815DD7A60A`. It does not replace or control the user's visible simulator.
- Final real MapKit regression: **30 Native unit tests and 2 UI tests passed** in `/tmp/tastemap-map-anchor-tests/FinalMapGeometry-20260905-1838.xcresult` (log `/tmp/tastemap-map-anchor-tests-final-geometry-20260905-1838.log`). The DEBUG-only dense-fixture accessibility target is clear and non-interactive; it only bounds input away from the overlaid navigation. Both tests require actual MapKit viewport changes and measure the rendered front-circle center against projection of its stored coordinate. They do not set camera values to simulate successful gestures.
- Regional pinch test passed (110.903 s): actual latitude span `0.045896 → 3.652485 → 0.066674`; four distinct city coordinates became one real representative and restored the same four IDs. All stages retained all 18 Restaurant members (not 36 Visits). Maximum sampled, settled front-circle error: **0.425 pt**.
- Local pinch/pan/member-list test passed (59.633 s): actual pinch-close/open returned to street span `0.008706`; pan preserved IDs, coordinates and members. Tapping the stack opened its real complete member chooser and returned to Map. Maximum sampled, settled front-circle error: **0.4321 pt** (pan: **0.3603 pt**).
- Earlier unsuccessful UI runs are not passes: a full-map pinch hit bottom navigation, and later runs exposed duplicate accessibility identities for internal/hidden layers. Those identities were corrected; geometry tolerances were not widened.

## Design System Compliance

- **Core UI:** existing marker sizes, selection increments and same-coordinate layer offsets are owned by `TasteMapDesignTokens`; existing page chrome, filters, bottom navigation and roulette dock are preserved.
- **Food & Dining visuals:** real member visuals reuse the existing image-priority policy, own rating ring and category fallback. No synthetic front-image copies, fake quantity graphics or empty backplates remain.
- **Canonical templates:** city map, regional view and complete member chooser retain the shared map/page structure. Canonical product, architecture and map-layout documents were updated to the latest instruction rather than keeping the discarded count rule active.
- **Duplicates/defaults:** Native back layers reuse the same Restaurant renderer. Browser live and static maps share image semantics. Native rollback/public fallback uses a system action sheet for member selection; its separate visual parity was not manually accepted in this run.
- **Remaining verification limits:** no physical-device validation was requested or performed; Browser AMap runtime and the full Release app binary were not exercised in this focused simulator run. The formal bundled-UI Release-purity check passed. The UI tests send real continuous pinch gestures and inspect geometry at settled stages; their numerical error bound is not a frame-by-frame guarantee throughout finger motion. Visual acceptance remains with Lafayette on the updated simulator.
