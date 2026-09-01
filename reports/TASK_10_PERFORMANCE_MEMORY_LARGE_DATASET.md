# Taste Map — Task 10 Performance and Large Dataset Report

## Outcome

Task 10 hardens the large local-library paths without changing Product IA and without reintroducing Restaurant clusters. The fixed Simulator remains in DEBUG-only Rich Visual QA mode after the final Debug install.

## Dataset coverage

The new combined regression constructs and processes:

- 1,000 Restaurants;
- 10,000 Visits;
- 5,000 Dishes;
- 2,000 Photo metadata records;
- mixed ratings, nil ratings, spend, cities, dining modes, companions, recommendation sources, search text, visited and Want-to-Go states.

Existing regressions additionally cover large Lists/analytics, 10,000-record legacy import/decode/merge, large Backup v1 export, On This Day, monthly/annual analysis, companion/source analysis, and local photo behavior.

## Map: independent markers and viewport work

### Before

- Every SwiftUI update reconciled the complete marker collection with `MKMapView`, even when most Restaurants were outside the visible map.
- Selection reconciliation scanned every active annotation.
- Image tasks remained tied to the full annotation set until a scope/filter change removed them.
- Exact-coordinate collision dispersion was already deterministic and no MapKit clustering identifier was used.

### After

- `RestaurantMapViewportPolicy` returns only the padded visible region plus any currently selected Restaurant.
- A pan/zoom performs one incremental reconciliation after MapKit settles the region.
- Offscreen annotations and image tasks are removed; MapKit continues to reuse lightweight `MKAnnotationView` instances.
- Selection updates touch only the previous and next selected annotation.
- Antimeridian distance is handled explicitly.
- Every returned annotation keeps its original Restaurant UUID. No aggregate/count annotation type exists, `clusteringIdentifier` remains `nil`, and numeric cluster UI was not added.
- Coincident Restaurants continue to receive deterministic individual offsets.

Measured pure viewport selection for 1,000 markers: approximately 0.007–0.011 seconds in the Simulator test runtime.

## Map/List/Search/Filters

### Before

Cuisine tags were decoded from `remoteRecordData` repeatedly during filter resolution and again while deriving filter options. Repeated chip changes therefore repeated JSON work across the complete collection.

### After

Restaurant tags are decoded once while building the shared `RestaurantBrowseSnapshot` and retained in `RestaurantBrowseItem`. Map, List, search, sorting, and all compact filters still consume the same shared projection.

Results:

- existing 1,000 Restaurant / 10,000 Visit combined filter regression: 0.421 seconds;
- new complete 1,000 / 10,000 / 5,000 / 2,000 projection, filtering, and search: 0.481–0.719 seconds across repeated runs;
- 1,000 marker presentation build: 0.020 seconds.

The timing limits remain deliberately broad enough for CI/Simulator variance while still detecting an O(n²) or repeated-decode regression.

## Photos and memory

- `PhotoTransferCoordinator` now uses a thread-safe `NSCache` for transient image source data with a 192-item / 32 MiB budget. `NSCache` can purge under system memory pressure.
- The persistent local original/display/thumbnail boundary is unchanged; the memory cache is not a second storage system.
- A manual `purgeTransientImageDataCache()` hook is available for explicit memory-pressure integration.
- The Map merchant-image loader now uses an LRU cache bounded to 64 entries and 24 MiB rather than a count-only dictionary that could retain up to hundreds of MiB of large responses.
- Single merchant responses remain capped at 8 MiB, HTTPS/mime/status validation remains intact, and in-flight request coalescing remains intact.
- Real Restaurant image priority is unchanged: real user/public/provider imagery is resolved before Food/Dining fallback.

## Analytics and posters

`AnalysisPosterRenderer` now wraps each render in an autorelease scope. A dedicated regression rendered all five families twice—10 total 1080×1920 images:

- 我的口味档案;
- 最佳饭搭子;
- 谁最会种草;
- 本月回顾;
- 年度回顾.

Ten renders completed in approximately 0.51 seconds in the Simulator unit-test host. The renderer and resolved image dictionaries are released at the end of each iteration; no long-lived global poster image cache was added.

## Import and backup

Existing large-data paths were rerun after the performance changes:

- legacy v4 10,000 Visit / 5,000 embedded Dish decode;
- Import preflight;
- Import merge planning;
- Backup v1 export including 2,000 Photo metadata scale;
- local photo download/cache lifecycle.

All passed. Import semantics, transaction behavior, ownership, and Backup contracts were not changed.

## Automated memory observation

The targeted 172-test performance/regression process reported:

- maximum resident set size: 293,076,992 bytes;
- peak memory footprint: 192,136,320 bytes;
- swaps: 0.

This number includes `xcodebuild`, the Simulator test host, XCTest/Swift Testing, and all selected suites. It is not presented as a real-device Instruments measurement. No scripted true-device Allocations/Time Profiler run was performed in this autonomous task.

## Tests and builds

| Check | Result |
|---|---|
| Task 10 + Map + F2B core suites | PASS — 37 tests |
| Analytics/Poster/Photo/Import/Backup regressions | PASS — 172 tests |
| Five poster families × 2 | PASS — 10 images |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Fixed Simulator install/launch | PASS |
| Numeric Restaurant clusters | ABSENT |
| Production access | NONE |

Logs:

- `/tmp/tastemap-task10-core-tests.log`
- `/tmp/tastemap-task10-poster-tests.log`
- `/tmp/tastemap-task10-regression-tests.log`
- `/tmp/tastemap-task10-debug-build-pre.log`
- `/tmp/tastemap-task10-release-build.log`

Visual checkpoint:

- [Rich independent-marker Map](remaining-09-14-assets/task-10/rich-map-performance-after.png)

## Remaining real-device validation

The final iPhone smoke should still observe sustained pan/zoom, marker selection, coincident-marker access, memory warnings, and repeated poster export. Simulator metrics cannot substitute for real-device Time Profiler/Allocations, and this report does not claim otherwise.
