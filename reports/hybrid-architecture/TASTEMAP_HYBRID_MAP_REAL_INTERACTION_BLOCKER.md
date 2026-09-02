# Taste Map Hybrid Map — Real Interaction Blocker

Date: 2026-09-03

Branch: `feature/hybrid-remaining-ui-batch`

Fixed Simulator: iPhone 17 Pro, iOS 26.5

UDID: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

Production accessed: **NO**

## Final status

`REAL AMAP INTERACTION = BLOCKED BY DEVELOPMENT AMAP CREDENTIAL`

Batch 3 is not authorized to start while this gate is open.

## Runtime evidence

| Question | Observed answer |
| --- | --- |
| AMap JS SDK loaded? | **NO.** `VITE_AMAP_DEV_KEY` and the Development security code are both absent. |
| `AMap.Map` instance created? | **NO.** `MapView` returns `OfflineRestaurantMap` before executing `loadWebMapSdk()` or `new AMap.Map(...)`. |
| Visible roads/grid/background | **Static React fallback**, not AMap tiles. The visible grid is `.tm-offline-map .map-grid`. |
| Visible Restaurant markers | **React `<button>` elements** projected on the fallback surface, not `AMap.Marker` overlays. |
| Real `getZoom/getCenter/getBounds` at runtime | **NO.** Those methods exist only on the uncreated live `AMap.Map` instance. |
| Single-finger drag | **FAIL / unavailable on fallback.** |
| Pinch zoom | **FAIL / unavailable on fallback.** |
| Viewport query follows bounds | **FAIL / unavailable on fallback.** |

The fixed Simulator was launched from the current branch's Debug signed local
Hybrid bundle and navigated to My Map. A single-finger horizontal drag from the
middle of the viewport produced no map/marker displacement. The same central
400 × 400 map crop before and after the gesture has the identical SHA-256:

`4a68ec46e94cc08c59984f8625c4403f73fc6abdf79ea684edf3a541ff48fa63`

Evidence:

- `screenshots/map-interaction-blocker/fallback-before-pan.png`
- `screenshots/map-interaction-blocker/fallback-after-pan.png`
- `screenshots/map-interaction-blocker/fallback-before-pan-map-crop.png`
- `screenshots/map-interaction-blocker/fallback-after-pan-map-crop.png`

The complete screenshots differ only because an independent fresh-location
status message appeared after the gesture. The map viewport crop itself is
byte-identical.

## Root cause

`ROOT CAUSE = DEVELOPMENT AMAP CONFIG MISSING`

`src/services/amap.ts` selects Development values when the app environment is
not Production and requires both a key and security code. `isAmapConfigured`
is therefore false in the current `hybrid-debug` build. `src/components/MapView.tsx`
then intentionally returns the fallback immediately.

The current screen is not an AMap instance with a gesture bug. Consequently no
live AMap container exists on this runtime for an overlay, `pointer-events`,
WKWebView recognizer or z-index layer to intercept. Static source review found no
full-viewport interactive overlay over the live map branch: the inactive list
layer uses `pointer-events: none`; FilterBar, bottom navigation and Add CTA occupy
only their own bounds. These observations do not replace the required live-SDK
gesture run after credentials are configured.

## Honest runtime distinction

The canonical renderer now publishes a machine-readable DOM state:

- `data-map-runtime="fallback-static"` for the non-interactive fallback;
- `data-map-runtime="amap-loading"` while the SDK is loading;
- `data-map-runtime="amap-ready"` only after `AMap.Map` has been created.

The fallback accessibility label also explicitly says it is a static Restaurant
position preview that does not support pan or zoom. This prevents future visual
or automated acceptance from treating the fallback as a real map.

## Development-only configuration required from Lafayette

High-level AMap Console steps:

1. In a Development-only AMap application, add a key whose service platform is
   **Web端（JS API）**. Do not create an Android or iOS SDK key for this React map.
2. Obtain the matching `securityJsCode`. New JS API keys require their matching
   security code. The key and code must come from the same Development entry.
3. The Capacitor shell uses the signed local origin `capacitor://localhost`
   (`iosScheme = capacitor`, `hostname = localhost`). Configure the Development
   key's permitted host/domain for `localhost` as supported by the AMap Console,
   and verify that the SDK returns neither `INVALID_USER_DOMAIN` nor
   `INVALID_USER_SCODE` in this shell.
4. Put the values only in the already ignored local file at repository root:

   ```dotenv
   VITE_AMAP_DEV_KEY=<Development Web JS API key>
   VITE_AMAP_DEV_SECURITY_KEY=<matching Development securityJsCode>
   ```

   File: `.env.hybrid-debug.local`

5. Never commit that file. Never use `VITE_AMAP_PROD_*` values, a Production key,
   or a Production security code for this acceptance run.

The local check prints only `CONFIGURED`/`MISSING`, never values:

```sh
pnpm hybrid:check:amap-development
```

The official AMap JS API 2.0 documentation requires a Web（JS API）key and its
matching security code and recommends `@amap/amap-jsapi-loader` for loading:

- <https://lbs.amap.com/api/javascript-api-v2/prerequisites>
- <https://lbs.amap.com/api/javascript-api-v2/guide/abc/load>
- <https://lbs.amap.com/api/javascript-api-v2/guide/abc/jscode>

## Required acceptance after configuration

All checks must use the fixed Simulator and one live `amap-ready` instance:

1. Record center, zoom and bounds before interaction.
2. Pan left, right, up and down; center and bounds must change.
3. Pinch zoom in and out; zoom and bounds must change.
4. Continue mixed pan/pinch interaction for 30 seconds without a frozen surface.
5. Confirm viewport requests follow the new live bounds.
6. Confirm Restaurant markers move with AMap tiles and remain independently clickable.
7. Open a marker's canonical Restaurant Detail, go back and verify the previous viewport.
8. Switch Map → List → Map and verify the same viewport/filter/scope state.
9. Verify Add CTA, FilterBar and bottom navigation do not consume gestures outside their own hit boxes.
10. Re-run the no-cluster/natural-overlap/z-order/image-priority contract suite.

Only after these checks produce actual before/after center, zoom and bounds evidence
may the status change to `REAL AMAP INTERACTION = PASS`.

## Preserved contracts

No Marker behavior was changed while diagnosing this blocker:

- no numeric or Food-count cluster;
- natural Restaurant overlap;
- `selected → rating → visitCount → stable Restaurant ID`;
- real Restaurant image priority;
- separate current-user avatar location marker;
- no default offset, dispersion or spiderfy.

No Production, Worker, D1, R2, SwiftData, SyncEngine, StoreKit, signing, capability
or App Store state was accessed or changed.
