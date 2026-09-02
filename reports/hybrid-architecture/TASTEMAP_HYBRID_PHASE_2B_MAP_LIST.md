# Taste Map Hybrid Migration Phase 2B — My Map / My List

Date: 2026-09-02

Branch: `feature/hybrid-phase-2b-map-list`

Baseline: `659d5b87f0cd3ad798a2f7954dad27403c1c7de8`
Production accessed: **NO**

## Superseding real-map interaction status — 2026-09-03

`REAL AMAP INTERACTION = BLOCKED BY DEVELOPMENT AMAP CREDENTIAL`

The fixed-Simulator surface previously used for Phase 2B evidence is the explicit
`OfflineRestaurantMap` fallback, not a live `AMap.Map`. The fallback is a static
React projection and does not support pan, pinch zoom or changing geographic
bounds. Therefore the earlier **CONDITIONAL PASS** applies only to the Map/List
product shell, data, marker, state and navigation contracts. It must never be
interpreted as live-map interaction acceptance.

Batch 3 must not start until a Development Web（JS API）key and its matching
security code are injected through the ignored local configuration, followed by
the fixed-Simulator pan/pinch/viewport acceptance run. See
`TASTEMAP_HYBRID_MAP_REAL_INTERACTION_BLOCKER.md` for runtime evidence and the
non-secret configuration procedure.

## Executive answers

1. **Phase 2B PASS / FAIL:** **PRODUCT SHELL PASS / REAL AMAP INTERACTION BLOCKED**. All autonomous data/ownership, navigation, offline, Browser, state, build, test and Release-purity gates pass. The real map interaction contract does not pass because no Development Web Key/security code is configured; it was not faked with a Production credential.
2. **My Map 是否 Hybrid:** **YES — `HYBRID_INTEGRATED`**, not Hybrid-primary.
3. **My List 是否 Hybrid:** **YES — `HYBRID_INTEGRATED`**, sharing the same page/state/query as My Map.
4. **no-cluster 是否保持:** **YES**. No numeric cluster or Food/Dining count cluster exists at any zoom level.
5. **natural overlap 是否保持:** **YES**. Restaurants remain independent and may naturally overlap; no default offset, dispersion or spiderfy was introduced.
6. **selected → rating → visitCount → stable ID 是否保持:** **YES**, with deterministic nil-rating semantics and the user-location layer excluded from the comparator.
7. **Restaurant image priority 是否保持:** **YES**. Native provides one canonical safe descriptor; Marker/List use the same source identity and keep a Food/Dining fallback visible until a real image has actually loaded.
8. **user avatar location 是否保持:** **YES**. Location comes from the Native location service and renders as the current user's circular avatar/halo in a separate top layer.
9. **Map/List state 是否共享:** **YES**. Mode, scope, filters, sort, city, search, viewport and selection live in one canonical `MapBrowseState`.
10. **Restaurant Detail 是否走 Hybrid route:** **YES**. Marker/row → `#/restaurant/:id`; back returns to the persistent map route with selection/query state intact.
11. **Browser 是否未受损:** **YES**. Browser uses the same React/CSS through `TasteMapBrowserAdapter`; typecheck, 359 tests and production build pass.
12. **Offline 是否工作:** **YES**. The signed local bundle, owner-scoped Restaurant data, cached/local images, Map shell, List and local Restaurant Detail work. Missing AMap tiles degrade to a neutral local map rather than a white screen.
13. **性能是否存在 P0/P1:** **NO autonomous P0/P1 found**. No jank, freeze, WebContent crash or privacy/ownership issue occurred. Live AMap gesture performance remains pending Development key configuration and is not marked passed.
14. **内存是否出现持续增长:** **NO** in the fixed Debug Simulator sample. Warm-up/image caches increased WebContent once, then repeated mode/detail loops reached a plateau; a second five-detail loop changed WebContent by only about 0.5 MiB.
15. **Release purity 是否 CLEAN:** **YES**. The formal Release app and signed Web resources contain no Debug fixture, rich-demo identity, Development URL, local path, test account/header, Premium bypass, token/secret/private-key marker or remote `server.url`.
16. **Release default 是否仍为 Native:** **YES**.
17. **Native Map rollback 是否仍完整:** **YES**. No SwiftUI Map/List implementation was removed or replaced.
18. **下一阶段推荐迁什么:** **Do not start Batch 3.** Close the Development AMap/live gesture gate first. Previously migrated Batch 1/2 routes remain intact.

## Scope and architecture

Phase 2B adds only My Map and My List to the persistent Hybrid app shell:

```text
MyMapBrowsePage + MapView (shared React/CSS)
                 │
        one canonical MapBrowseState
                 │
          TasteMapPlatform.map
                 │
  BrowserAdapter       NativeAdapter
       │                    │
  IndexedDB        TasteMapNative.v1 map.viewport
                            │
             owner-scoped Native Map DTO service
                            │
               SwiftData / images / location
```

The bridge call is batched and viewport-aware. Requests include bounds, zoom, scope, filters, sort, search and request ID. The response returns lean presentation DTOs with stable Restaurant ID, coordinate, rating, visit count, scope/status semantics and a safe image descriptor. SwiftData objects and absolute local paths never cross the bridge. Request identity/stale-response protection prevents an older viewport response from replacing a newer query.

Discovery, Community, Add Restaurant, Nearby, Visit, Lists, Roulette, Analytics, Premium and Settings remain Native-primary and were not migrated.

## Product contract checklist

| Contract | Result | Evidence |
| --- | --- | --- |
| “我的地图” title | PASS | Shared React page and fixed-Simulator screenshot |
| “我的列表” title | PASS | Same page after mode switch |
| title + switch icon centered as one group | PASS | CSS layout + 402 pt iPhone evidence |
| scopes are exactly 去过 / 想吃 / 推荐 | PASS | Browser/iOS screenshots and UI path |
| one shared FilterBar | PASS | Same state/component in Map and List |
| no cluster at any zoom | PASS | Marker renderer and contract tests |
| natural overlap | PASS | Dense dataset evidence; no default offset/spiderfy/dispersion |
| selected priority | PASS | Selection screenshot and comparator tests |
| rating priority | PASS | Deterministic marker comparator tests |
| visit-count tie-break | PASS | Deterministic marker comparator tests |
| stable-ID final tie-break | PASS | Deterministic marker comparator tests |
| real-image priority | PASS | Native image descriptor policy; loading fallback hardening |
| user avatar location | PASS | Native location DTO/event and screenshot |
| Map/List state preservation | PASS | new UI regression plus 10-cycle manual exercise |
| Restaurant Detail Hybrid route | PASS | UI regression and five repeated round trips |

## Data, ownership, image and location

- `map.viewport` reads only the current authenticated `tm_` owner's Restaurants and relationships.
- The Rich Visual QA dataset exercises 90 visited Restaurants, 25 want-to-go Restaurants, dense and sparse areas, mixed ratings and real/fallback imagery. It exists only in the Debug fixture path.
- Marker and list image descriptors share the same canonical source identity. The visual fallback remains visible while an image is pending and is replaced only after a successful `load`, preventing blank circles/rows without overriding a real image.
- Local user photos use an allowlisted `tastemap-resource://` scheme handler; React receives no absolute path.
- `location.current` and throttled `location.changed` expose only latitude, longitude, horizontal accuracy, timestamp and authorization state. Map camera/city center is never presented as user location.
- The user avatar marker is visually and semantically separate from Restaurant markers and has a higher independent layer.

## Browser and offline behavior

Browser and Capacitor render the same `MyMapBrowsePage`, `MapView`, CSS and filter controls. Only the adapter/data source differs. Browser production build remains valid and restaurant row navigation remains canonical.

The current Development environment has no configured AMap Web Key/security code. The tested behavior is therefore the intentional offline/provider-unavailable state:

- local bundle starts without a UI server;
- the neutral local map is visible instead of a blank WebView;
- independent Restaurant markers remain selectable;
- cached/local Restaurant images and honest Food/Dining fallbacks render;
- Map/List, scopes, filters and Restaurant Detail continue to work;
- an honest message explains that city-center tiles cannot currently refresh.

`map-after-pan-zoom.png` records stability after a gesture on this offline degradation surface. It is **not** evidence of live AMap pan/zoom responsiveness. That acceptance requires Lafayette's Development AMap configuration and must not reuse or expose a Production credential.

## Fixed-Simulator performance baseline

Device: iPhone 17 Pro, iOS 26.5

UDID: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

Build: Debug, local signed Hybrid resources, deterministic Rich Visual QA user
Measurement: host `ps` RSS; Debug Simulator only, not a Release-device claim.

| Checkpoint | App RSS | WebContent RSS | Observation |
| --- | ---: | ---: | --- |
| Before Map route (Profile open, 8 s settled) | 460,368 KiB | 213,504 KiB | Cold Debug/Rich fixture baseline |
| Map opened (5 s settled, 90 visited dataset) | 488,688 KiB | 305,088 KiB | Map and thumbnail warm-up |
| 30 s after gesture/image loading | 458,272 KiB | 266,832 KiB | Both lower than immediate Map sample |
| Map ↔ List repeated 10 cycles | 291,168 KiB | 308,848 KiB | Persistent shell/state; no reload/crash |
| Restaurant Detail → Back ×5, 10 s settled | 288,144 KiB | 341,664 KiB | Detail/image cache warmed |
| A second Detail → Back ×5, 10 s settled | 288,128 KiB | 342,208 KiB | +544 KiB WebContent; plateau, not one-way runaway |

The different App RSS level after the first warm-up reflects normal Debug Simulator reclamation; no process restart occurred. These values must not be presented as real-device or Release benchmarks.

## Rendering responsiveness

| Interaction | Result |
| --- | --- |
| Cold Debug automation launch to map switch available | about 6.6 s including XCUITest launch/bootstrap overhead |
| Scope switch | about 0.3 s in UI automation |
| Map/List switch | about 0.3 s in UI automation |
| Restaurant Detail transition | within the 1.1 s UI polling interval |
| Back and state restoration | within the 1.1 s UI polling interval |
| Pan/zoom on live AMap tiles | **PENDING DEVELOPMENT AMAP CONFIGURATION** |
| Crash/freeze/jank during repeated state/route loops | none observed |

## Automated verification

| Verification | Result |
| --- | --- |
| TypeScript typecheck | PASS |
| Web/Vitest suite | PASS — 54 files, 359 tests |
| Swift bridge package | PASS — 5 tests |
| Full iOS unit/integration suite | PASS — 656 tests, 0 failures |
| Phase 2A Profile/Restaurant UI regression | PASS |
| Phase 2B Map/List/scope/detail-state UI regression | PASS |
| Browser Hybrid production build | PASS |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Generic iOS Device Release build | PASS |
| Formal Hybrid local-bundle verification | PASS |
| Release app + signed Web resource scan | CLEAN |

Latest full iOS result bundle:

`/Users/lafayette/Library/Developer/Xcode/DerivedData/TasteMap-ehexmkejrugfpkfzwgvxmtqcmsyf/Logs/Test/Test-TasteMap-2026.09.02_16-31-54-+0800.xcresult`

Latest Phase 2B UI result bundle:

`/Users/lafayette/Projects/private-food-map-hybrid-phase-2b/build/phase2b-ui-test/Logs/Test/Test-TasteMap-2026.09.02_17-14-09-+0800.xcresult`

## Screenshot evidence

All files are real Browser or fixed-Simulator renders; none is an AI mockup.

- [My Map visited — Browser vs iOS](screenshots/phase-2b/map-visited-browser-vs-ios.png)
- [My Map want-to-go — Browser vs iOS](screenshots/phase-2b/map-want-browser-vs-ios.png)
- [My Map recommended — Browser vs iOS](screenshots/phase-2b/map-recommended-browser-vs-ios.png)
- [My List — Browser vs iOS](screenshots/phase-2b/my-list-browser-vs-ios.png)
- [Dense natural overlap](screenshots/phase-2b/dense-overlap.png)
- [Sparse map](screenshots/phase-2b/sparse-map.png)
- [Selected Restaurant](screenshots/phase-2b/selected-restaurant.png)
- [Current-user avatar marker](screenshots/phase-2b/user-location-avatar.png)
- [Offline degradation after gesture](screenshots/phase-2b/map-after-pan-zoom.png)

## Release and rollback boundary

- Release runtime remains `NATIVE_PRIMARY` and opens the existing SwiftUI app.
- Debug Hybrid mode/default route/fixture are compile/runtime isolated and excluded from the formal Release resources.
- Current SwiftUI Map/List are unchanged and remain the rollback implementation.
- No Bundle ID, Team, signing, entitlement, capability, SwiftData schema, SyncEngine, Worker, D1, R2, StoreKit, App Icon or Production state changed.
- Phase 2B does not authorize `HYBRID_PRIMARY` and does not start Discovery migration.

## Remaining gates

1. Configure a Development-only AMap Web Key/security code through the existing secret/configuration path, then verify SDK loading, gestures, attribution, pan/zoom responsiveness and viewport cancellation in the fixed Simulator and real iPhone. Do not put the values in Git or reuse a Production secret.
2. Lafayette visually accepts Browser/iOS Map/List screenshots on the fixed Simulator.
3. Real iPhone smoke for touch gestures, location/avatar accuracy, memory and Hybrid detail/back behavior.
4. A separate explicit decision is required before changing My Map / My List from `HYBRID_INTEGRATED` to `HYBRID_PRIMARY`.

Phase 2B stops here.
