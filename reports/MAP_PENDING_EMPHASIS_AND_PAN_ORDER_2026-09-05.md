# Pending map emphasis and pure-pan overlap correction — 2026-09-05

## Scope and result

Two user requests are covered: make Want to Go / Recommended Restaurant circles more noticeable without enlarging Visited, and stop pure pan from swapping the front Restaurant image. Fixed Simulator QA has passed both final UI tests. No real-device installation, account-data rewrite, backend change, primary-route switch or map-engine replacement occurred.

## Implementation and consumer inventory

- Shared Native `TasteMapDesignTokens.MapRestaurantMarker` adds 4 points for both pending statuses. `RestaurantMapMarkerMetrics` keeps visited inner 24–28 points, pending inner 28–32, white ring 2 per side and root/hit box 44. Pending selected outer diameter is at most 40. Distance no longer reduces pending emphasis; GPS absence behaves identically.
- Shared Browser `MapView` uses one unvisited semantic helper, including live provider markers, static fallback and real back members. Existing visited CSS size 32/36 is unchanged; pending adds 4. Root anchor is fixed 44. Ring, opacity, photo/fallback identity, coordinates and grouping remain unchanged.
- Native consumers: `MapHomeView` (Native primary/rollback), `TasteMapHybridMapSurface` (formal Hybrid MapKit), `SocialViews` public-map content; all consume the same `RestaurantMapView` and annotation renderer.
- Browser consumers: `BrowserMapSurface`, existing `App` map, `ProfilePage` public map and static fallback; all consume the same `MapView` renderer. No extension-specific Restaurant annotation renderer was found. Current-user location has a separate pointer-anchor policy and was not resized.
- MapKit layer fix: ranked Restaurant order is passed through distinct `zPriority` values in the 100–900 interval; selected uses 950; location uses `.max`. Reuse resets priorities before applying the next Restaurant's rank. No competing direct annotation-root `layer.zPosition` writes are used during ordering. Local back-member layers retain their existing negative stacking positions.

## Root-cause evidence

Before this change, Restaurant order only wrote `view.layer.zPosition`; all MapKit z priorities remained system defaults. Source identities and the real stack-member comparator were already deterministic. Runtime probes confirmed MapKit independently overwrites the actual layer z positions while arranging annotations (e.g. declared priority 478.947 was composited at layer 900.497). Supplying unique system priorities makes those system-generated layer positions preserve the canonical relative order, instead of fighting them with a second manual ordering pass.

The screenshots supplied by the user show a top-image swap, not proof of changed stored coordinates. This correction specifically addresses that observed overlap failure; it does not claim to fix the separate whole-shell refresh/rebootstrap flash or every map gesture-performance issue.

## Verification

- 78 TypeScript tests pass across `mapMarkers`, `MapView`, Hybrid map product contract and global product contract. Tests cover both pending states, real stack layers, no GPS shrink, selected emphasis, fixed anchor, existing grouping/priority semantics and forbidden manual ordering.
- 31 Native tests pass in `MapBrowsingParityTests`: `/tmp/tastemap-stable-map-compositor-native.xcresult`.
- Final fixed-QA UI result: `/tmp/tastemap-stable-map-compositor-qa-final.xcresult` — 2 tests pass.
  - `testHybridNativeMapOverlapOrderSurvivesPurePans`: four real back-and-forth drags; four distinct coordinates retain the same leading member, actual member/image-generation identities and distinct priorities; actual composited order remains consistent with those priorities.
  - `testHybridPendingMapMarkersAreLargerAndStayCentered`: visited → wanted → recommended → visited; real pinch open/close and pan in both pending scopes. The 44-point root does not change, scope switches do not fit the camera, and visited sizing remains unchanged.
- 111 runtime circle measurements, maximum projection error 0.445 pt. Pending normal outer diameters in the tested city views were 33.820–34.022 pt, four points above the baseline at equivalent zoom. Runtime size tolerance is 0.25 pt because the AX viewport and layer are sampled on separate frames and the renderer has an existing 0.15-point size-update threshold; coordinate tolerance remains 1 pt.
- `pnpm run typecheck`, `git diff --check`, formal-stage Release resource checks pass. The formal bundle has 16 files; dist → staged → built → installed resource checks all pass byte-for-byte, and installed executable compares exactly to the tested QA executable.
- Browser shared-code/SSR contracts pass. A temporary direct Hybrid Browser preview reached the existing Native-only MapSurface handoff and could not perform a Web-provider visual review; it is not counted as Browser map runtime acceptance and no unrelated route change was made. That temporary tab/server was closed.

## Artifact identity

- Repository: `feature/hybrid-final-integration`, base HEAD `58bd556`, existing dirty worktree preserved.
- Built: `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Fixed Simulator: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`; bundle `com.lafayette.tastemap.qa` (`味图测试`).
- Installed: `/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/A48A2307-5353-4321-BD10-A40755F267D6/TasteMap.app`.
- Signed local web: `index-BvP9CW32.js`, `index-BCsR7---.css`.
- Renderer: React Hybrid chrome + persistent Native MapKit, never Native rollback or a Web static map.
- UI tests explicitly launch rich/dense-mall isolated fixtures and `TASTEMAP_MAP_GEOMETRY_QA=1`; instrumentation is DEBUG-only. After testing, QA was reopened with only `TASTEMAP_CORE_PARITY_INITIAL_TAB=map`, restoring its default rich fixture and removing diagnostic geometry mode. The normal Hybrid launch still opened Profile (that environment hint is not the Hybrid route authority); this was visually checked and is not presented as a map checkpoint. No fixture screenshot represents private account data.

## Runtime screenshots

- Before pure pan: `/tmp/tastemap-map-pending-layer-screens/2659A3FF-1014-4EE4-95F9-5BA61B424F93.png`.
- After four pans: `/tmp/tastemap-map-pending-layer-screens/2ABEBFCA-C16F-4F29-B8A4-14CC43C65C40.png`.
- Wanted enlarged: `/tmp/tastemap-map-pending-layer-screens/E776B91E-C16F-49DF-9097-928BDB299046.png`.
- Recommended enlarged: `/tmp/tastemap-map-pending-layer-screens/4645EBBF-C387-4013-8CAC-5ACAFAE5ADAD.png`.
- Normal QA reopen screenshot (Profile, not map acceptance): `/tmp/tastemap-map-final-open.png`.

All four acceptance screenshots were visually inspected. The dense overlap retains the same front food image after return pans; the two pending scopes retain their neutral dashed shell with more prominent circles. Header, scope order/count semantics, filters, Add CTA and three-item navigation are preserved.

## Design System Compliance

- Core UI: PASS for this scoped correction — shared sizing token, fixed anchor/hit frame, no new page-local scale.
- Food & Dining: PASS for unchanged source/ring semantics — real owner image or canonical fallback, real back members; no quantity marker or fabricated aggregate.
- Canonical template: PASS for inspected Simulator surfaces — existing map chrome and route ownership preserved.
- Added duplicate/conflicting renderers: 0; default-SwiftUI visual regressions introduced: 0.
- Remaining gaps: full Browser provider visual acceptance, real-device gesture smoke, general sustained gesture-smoothness gate and independent shell refresh/reset defect remain open. This report does not promote any route to Hybrid Primary or claim global product acceptance.
