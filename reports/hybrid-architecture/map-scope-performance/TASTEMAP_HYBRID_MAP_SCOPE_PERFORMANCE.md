# Taste Map — Hybrid Map Scope Interaction Performance + Icon Closure

Date: 2026-09-03

Branch: `feature/hybrid-remaining-ui-batch`
Fixed Simulator: iPhone 17 Pro, iOS 26.5, `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

## Outcome

The `去过 / 想吃 / 推荐` scope interaction no longer waits for an arbitrary debounce, a Native bridge response, Restaurant projection, Marker construction, or image loading before the selected state changes. The three scopes now use one shared semantic icon-and-text primary-tab implementation in Browser and Capacitor.

The real AMap runtime remains a separate explicit gate: `VITE_AMAP_DEV_KEY` and `VITE_AMAP_DEV_SECURITY_CODE/KEY` are missing. Therefore the fixed Simulator currently renders the honest static fallback surface. The performance work is complete, but this report does **not** claim real AMap pan/pinch or a live AMap instance.

## Root-cause inventory

| Area | Before | Evidence | Closure |
| --- | --- | --- | --- |
| Artificial delay | Every populated viewport request waited 180 ms | Previous `MyMapBrowsePage` request effect used `setTimeout(..., viewport ? 180 : 0)` | Delay removed |
| Native projection | Every `map.viewport` rebuilt all owner-scoped Restaurant/Visit/Photo DTOs | `scopedRestaurants()` fetched and projected the complete graph on every request | Owner-scoped projection snapshot; every write invalidates it |
| Presentation projection | Each switch re-projected bridge Restaurants, image descriptors and options | Request path always started from zero | Bounded owner/data/filter/bounds snapshot cache; SwiftData remains authoritative |
| Camera behavior | Scope was part of `cameraFitKey` | `cameraFitKey = scope + filters + search` | Scope removed from camera-fit identity; filters/search may still intentionally refit |
| Marker lifecycle | Restaurant effect removed every Marker in cleanup and recreated all Marker DOM/images | Previous `MapView` effect returned a full Marker teardown on every data change | Stable-ID add/remove/change/reuse reconciliation; inactive pool capped at 500 |
| Image work | Recreated Marker DOM re-ran image resolution | New image element per full Marker rebuild | Bounded source cache, retained Marker/image identity, immediate fallback |
| Stale responses | One latest request ID existed, but scope invalidation waited for the next effect | Older response could remain live between tap and effect | Tap invalidates immediately; request and response IDs must both match |
| UI feedback | Selected state and data work were coupled inside the same React update path | User-observed lag plus the fixed request delay | Scope dispatch is urgent; content changes use cached urgent data or a transition |
| Fixture validity | Hybrid debug fixture had 3 visited / 2 Want-to-Go Restaurants | Fixed-Simulator baseline | Debug-only deterministic fixture expanded to 90 visited / 25 Want-to-Go / 275 Visits / 18 recommendations |

The Map component itself was mounted with an empty-dependency effect before this task, so the SDK instance was not deliberately destroyed by a scope update. The real regression was camera refitting plus full Marker teardown/reconstruction. Runtime AMap identity still requires the Development credential gate to be cleared before it can be measured against the live SDK.

## Measurement definitions

- **selected:** click handler timestamp → selected scope painted on the next visual frame.
- **data ready:** click → valid newest-scope response or presentation snapshot available.
- **content:** click → new scope item tree committed and one animation frame completed.
- **images stable:** click → every currently rendered canonical Restaurant image is complete, or immediate fallback is active.
- **bridge:** time spent awaiting `TasteMapNative.v1 map.viewport`; cache hits record zero because no bridge request is made.

Instrumentation is compiled for development / `hybrid-debug` only. The DOM diagnostics sink and Native log summarizer are absent from the Release bundle.

## Fixed-Simulator result — 20 complete cycles / 60 transitions

Dataset: 90 visited Restaurants, 25 Want-to-Go Restaurants, 18 deterministic Debug-only recommendations, 275 Visits.

| Metric | Median | P95 | Worst |
| --- | ---: | ---: | ---: |
| Selected visual | 15 ms | 36 ms | 40 ms |
| Data ready | 0 ms | 1 ms | 20 ms |
| Content committed | 15 ms | 36 ms | 40 ms |
| Images stable | 15 ms | 37 ms | 41 ms |
| Native bridge across all transitions | 0 ms | 0 ms | 14 ms |

Per-scope selected/content evidence:

| Destination | Items | Selected median / P95 / worst | Content median / P95 / worst |
| --- | ---: | --- | --- |
| Want-to-Go | 25 | 15 / 20 / 36 ms | 15 / 20 / 36 ms |
| Recommended | 18 | 12 / 14 / 16 ms | 13 / 14 / 16 ms |
| Visited | 90 | 33 / 39 / 40 ms | 33 / 39 / 40 ms |

- 58 of 60 transitions reused a valid presentation snapshot.
- The two first uncached Native scope requests were approximately 9 ms and 14 ms.
- No stale response replaced the final selected scope.
- The final scope was `visited` with 90 Restaurants.
- After one warm-up run, the WebContent RSS changed from roughly 99.1 MB to 98.5 MB after another 20-cycle run; App RSS changed by roughly 0.3 MB. It plateaued rather than growing linearly.
- No WebView reload occurred. The same process and route remained active.

Because AMap is not configured, live `AMap.Map` creation/reconciliation counters are zero on this Simulator. Static fallback markers updated correctly; live SDK identity, center, zoom and bounds must be re-run after Lafayette supplies the Development-only AMap values.

## Browser result — same React component, 20 complete cycles / 60 transitions

| Metric | Median | P95 | Worst |
| --- | ---: | ---: | ---: |
| Selected visual | 13.3 ms | 15.0 ms | 40.8 ms |
| Data ready | 0.1 ms | 0.4 ms | 7.6 ms |
| Content committed | 13.4 ms | 15.1 ms | 41.1 ms |
| Images stable | 13.4 ms | 15.1 ms | 41.2 ms |

- 58 of 60 transitions were cache hits.
- Browser adapter projection worst observed was 1.0 ms.
- Browser and Capacitor use `TasteMapPrimaryTabBar`; icons and labels are supplied by one `mapScopeTabs` definition.
- The earlier artificial 180 ms delay was shared code, so the regression affected Browser too. Native DTO/serialization work was the additional Capacitor-only cost.

## Product, icon and accessibility contract

- `去过`: `Footprints` icon + text.
- `想吃`: `Bookmark` icon + text.
- `推荐`: `Star` icon + text.
- All use the same Lucide line-icon family, 16 pt visual size, baseline, gap, selected color and underline.
- All remain first-level primary tabs, not FilterChips and not thick pills.
- Each is a real `button` with a minimum 44 pt hit target.
- `role=tab`, `aria-selected`, and the Chinese label expose the combined control; the decorative SVG is `aria-hidden`.

## Machine-verifiable contracts

- selected state dispatch is not inside or after the data Promise;
- scope is excluded from camera-fit identity;
- snapshot key includes owner, owner-data version, scope, filters, sort, search, bounds, mode and current location;
- cache is bounded and clears on owner/data/auth/location/lifecycle changes;
- request gate rejects an old request ID or mismatched response ID;
- Marker reconciliation classifies stable IDs as added/removed/changed/reused;
- unchanged Marker/image identity is retained;
- Marker pool and image-source cache are bounded;
- shared tab contract requires three icons, labels, selection semantics and no `适合你` regression;
- Native tests assert one owner-scoped projection build across multiple scope reads and the 90/25/275 fixture scale.

No brittle CI contract asserts an exact millisecond threshold.

## Evidence

- `simulator/visited-scope-icon.png`
- `simulator/want-scope-icon.png`
- `simulator/recommended-scope-icon.png`
- `simulator/scope-switch-20-cycles-compact.m4v`
- Native unified-log record: `TasteMapMapScopeDiagnostics` with 60 records and the aggregate table above.

## Validation

- TypeScript project typecheck: PASS.
- Vitest full suite: 57 files / 398 tests PASS.
- Hybrid Native Swift package: 6 tests PASS.
- Hybrid Debug Vite bundle: PASS.
- Fixed-Simulator Debug build/install/launch: PASS.
- Hybrid Release Vite bundle: PASS.
- Hybrid Release Simulator build: PASS.
- Hybrid Generic Device Release build: PASS using the already-resolved local Capacitor package checkout after GitHub fetch failed.
- Focused Release scan: PASS; no scope diagnostics, DOM diagnostics ID, rich fixture, Debug owner, Development URL, or Debug route marker was present.
- Repository-wide ESLint is not a clean gate because it scans generated `build/` frameworks and has pre-existing unrelated errors. The files changed by this task typecheck and their targeted/full tests pass.

## Remaining external gate

`REAL AMAP INTERACTION = BLOCKED BY DEVELOPMENT AMAP CREDENTIAL`

Missing, without values being printed:

- `VITE_AMAP_DEV_KEY`
- `VITE_AMAP_DEV_SECURITY_CODE` or `VITE_AMAP_DEV_SECURITY_KEY`

They belong only in ignored `.env.hybrid-debug.local`. Production credentials must not be used. Until this is configured and real pan/pinch/center/zoom/bounds/viewport restoration are re-run on the fixed Simulator, Batch 3 remains blocked.
