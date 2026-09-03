# Taste Map Hybrid iOS MapKit Integration

Date: 2026-09-03

Branch: `feature/hybrid-remaining-ui-batch`

Baseline before this correction: `15d5475f1ed6a628a8e6477f0012af3fb2331455`

Production accessed: **NO**

Batch 3 started: **NO**

## Final status

`REAL NATIVE MAPKIT INTERACTION = PASS (FIXED SIMULATOR)`

The iOS Hybrid My Map route no longer treats the Browser AMap JS renderer or a
Development AMap credential as its map engine. The Browser still uses its Web
provider. The formal Taste Map iOS target now keeps the shared React page chrome
and embeds the established persistent Native `RestaurantMapView` / `MKMapView`
as the map surface.

The remaining acceptance boundary is a real-iPhone smoke plus Lafayette's
explicit Product/route approval. Missing Development AMap Web configuration is
not an iOS or App Store Release blocker.

## Root-cause analysis

### 1. Commit that replaced the iOS MapKit surface

`a76e2da039e656f947562882a03a7fed71a043bc` —
`Migrate My Map and My List to shared React UI`

That commit introduced `MyMapBrowsePage.tsx` with a direct import of
`MapView.tsx`. `MapView.tsx` is the Browser AMap renderer. Because the same page
was mounted in the Capacitor host without an injected platform surface, iOS
started using AMap JS or its static fallback instead of the existing Native
MapKit presentation.

Supporting history:

- `8bffe37` added the owner-scoped `map.viewport` data bridge but did not define
  a platform-specific presentation-surface contract.
- `0cfc176` made the AMap fallback more honest and testable, but it remained a
  static React surface and could not pan or zoom.
- `a0ac67e` recorded Browser/fallback visual evidence as Phase 2B parity; that
  evidence did not prove a real iOS map engine.

### 2. Why One React UI became One Map Engine

The migration correctly required one React product UI, but omitted a renderer
injection boundary for the map slot. Page topology, scope tabs, filters, state,
Add CTA and navigation are product UI and belong in shared React. A map engine
is a platform capability. Directly importing the Browser renderer into the
shared page accidentally equated those two concerns.

The corrected rule is:

```text
Canonical React My Map / My List page
                 |
          injected MapSurface
           /             \
BrowserMapSurface     NativeMapSurface
Web map provider      TasteMapNative.v1
                            |
                    existing RestaurantMapView
                            |
                          MKMapView
```

### 3. Native code reused

The integration reuses the existing formal Map implementation rather than
creating another `MKMapView`:

- `Features/Map/ClusteredRestaurantMapView.swift`
  - `RestaurantMapView: UIViewRepresentable`
  - one `MKMapView`
  - pan/pinch/rotate gesture support
  - `showsUserLocation` and the established user-avatar annotation view
  - incremental Restaurant annotation diffing
  - no clustering
  - natural overlap and deterministic layer ordering
  - canonical Restaurant image loading
- `Features/Map/RestaurantMapPresentation.swift`
  - marker/camera/viewport policies
  - `selected → rating → visitCount → stable Restaurant ID`
- the existing owner-scoped `map.viewport` projection for filtered data
- the existing Native location service and current-user photo services.

`TasteMapHybridMapSurface.swift` contains the adapter/host only. Its source has
no `MKMapView(...)` constructor; it embeds `RestaurantMapView(...)`.

### 4. Persistent-shell embedding

`TasteMapHybridBridgeViewController` creates one
`TasteMapHybridMapSurfaceHost` for its lifetime. React reports the actual map
slot rectangle through `map.surface.update`. The host positions one persistent
`UIHostingController<RestaurantMapView>` over that rectangle and cuts out only
the small React-owned floating control rectangles so their original WebView hit
targets remain available.

The map-stage start is derived from the actual iOS safe-area-aware React header
height. This prevents the Native overlay from covering the compact FilterBar on
Dynamic Island devices; the UI regression asserts that the FilterBar both
exists and remains hittable above the MapKit surface.

Navigating to Restaurant Detail or List mode hides the surface instead of
destroying it. Returning reveals the same MapKit instance and preserves center,
zoom, bounds, selection and the shared React browse state. This is not a second
SwiftUI Map page and does not own the Header, scopes, FilterBar, Add CTA or
bottom navigation.

## Typed surface contract

The presentation-only `map.surface.update` request carries:

- an opaque request ID;
- visibility and map-slot geometry;
- React-control exclusion rectangles;
- scope, filters, sort and search state;
- a camera-fit identity;
- selected Restaurant identity;
- canonical marker/image descriptors;
- current-user avatar presentation identity.

Native reports:

- `map.viewport.changed` with actual center, zoom and bounds after MapKit
  settles a camera change;
- `map.restaurant.selected` after Native annotation selection/deselection.

The surface contract contains no token, Keychain value, SwiftData object,
persistence write authority, AMap credential or provider secret. Owner-scoped
data selection remains in the existing Native query service.

## Preserved Product contracts

- Every Restaurant remains an independent annotation at every zoom level.
- No numeric cluster and no Food-count cluster.
- Natural overlap; no default offset, dispersion or spiderfy.
- Layering remains `selected → rating → visitCount → stable Restaurant ID`.
- Current-user avatar location marker is separate from Restaurant ordering.
- Restaurant imagery remains current-user real photo → legal public/cached
  photo → legal provider image → Food & Dining fallback.
- Map and List share one scope/filter/sort/search state.
- React continues to own `我的地图 / 我的列表`, `去过 / 想吃 / 推荐`, the
  compact FilterBar, `添加餐厅` and `地图 / 发现 / 我的` navigation.
- Browser continues to use the Web renderer; Browser build and tests pass.

## Fixed-Simulator runtime evidence

Device: iPhone 17 Pro, iOS 26.5

UDID: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

The formal `ios/TasteMap/TasteMap.xcodeproj` target was built and launched with
the Debug-only Hybrid development runtime and deterministic Rich Visual QA
state. It was not the earlier isolated Capacitor POC target.

Measured MapKit viewport values:

| State | Center | Span |
| --- | --- | --- |
| Initial | `30.279370, 120.161540` | `0.131557, 0.101898` |
| After single-finger pan | `30.279370, 120.217395` | `0.131557, 0.101898` |
| After pinch zoom | `30.279471, 120.217355` | `0.101491, 0.101741` |

This proves that the Native center, span/bounds and derived zoom changed. The
interaction test then selected a real Native annotation, opened canonical
Hybrid Restaurant Detail, returned, switched Map → List → Map and verified the
same zoomed viewport was preserved.

The user avatar location annotation was present. On maps rendered in mainland
China, MapKit may visibly show Gaode/高德 attribution under Apple's MapKit
service terms; this does not mean the app is running the AMap JavaScript SDK.

### Gesture/performance run

A sustained automated run performed six alternating pan gestures, pinch-in and
pinch-out on the same native map surface. The application remained foreground
and the map remained hittable.

- measured clock interval: `13.817358 s`
- peak physical memory: `41,519.312 kB`
- reported physical-memory metric: `1,359.872 kB`
- crash/freeze: none

## Automated validation

| Gate | Result |
| --- | --- |
| TypeScript/Vitest full suite | **PASS** — 57 files, 401 tests |
| Native bridge Swift package | **PASS** — 7 tests |
| Map presentation/F2A suites | **PASS** — 2 suites, 21 tests, including 1,000 Restaurants / 10,000 Visits |
| Native MapKit FilterBar/pan/pinch/selection/detail/back/Map-List UI test | **PASS** |
| Hybrid Map/List scope and detail-state UI test | **PASS** |
| Sustained gesture clock/memory UI test | **PASS** |
| Browser TypeScript check + Vite production build | **PASS** |
| Formal Hybrid local bundle build/stage | **PASS** |
| Debug Simulator build | **PASS** |
| Release Simulator build | **PASS** |
| Generic iOS Device Release build, unsigned | **PASS** |
| Formal Release App binary/resource purity scan | **PASS** — 36 App files, 16 signed Web files |

The Release scan found no Debug switch/fixture, Development URL, source-machine
path, private-key marker, secret, test identity or credential surface in the
signed React bundle. Release remains `NATIVE_PRIMARY`; this integration does
not promote Hybrid to the production owner.

## Visual evidence

Settled Native MapKit surface:

![Native MapKit settled](screenshots/06-mapkit-final-with-filters.png)

The screenshot shows the safe-area-aware React title/scopes/compact FilterBar
surrounding Native MapKit tiles, independent Native Restaurant annotations and
the Native user location marker.
The interaction pass is established by the machine-recorded viewport changes,
not by the screenshot alone.

## Remaining manual gate

Before any `HYBRID_PRIMARY` route switch, Lafayette must perform the same pan,
pinch, marker, Restaurant Detail/back, Map/List and user-location smoke on a
real iPhone. No AMap Web key or `securityJsCode` is required for that iOS smoke.

Batch 3 remains intentionally not started.
