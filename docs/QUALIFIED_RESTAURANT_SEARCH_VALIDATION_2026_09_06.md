# Full restaurant name plus neighbourhood — service validation

Date: 2026-09-06. This is an evidence report, not a replacement for product rules or installed-artifact acceptance.

## User case

Input remains `Da Andrea Greenwich Village`, city remains `纽约`. Users do not have to shorten the name, change the city spelling, or look up an address elsewhere.

## Implementation

The existing worldwide search owner first attempts the full query. If the overseas provider returns no relevant restaurant, it tries at most three business-name / place-name splits. A split is accepted only when the provider independently resolves an exact place name in the selected city and returns exact business-name restaurant candidates in that same city. Results are ordered by proximity to that place anchor. Original provider names, addresses, locality and identifiers remain unchanged; no merchant-specific address or inferred neighbourhood is saved.

Query-time `resolvedSearchQuery` provenance allows the existing native acquisition and Hybrid relevance gates to accept that verified query without requiring a provider locality label to equal the user's neighbourhood spelling. It is not a persisted Restaurant field. Other-city businesses and wrong-city / non-place anchors are rejected. A provider timeout retains the independent Apple Maps fallback. Cancellation propagates without starting another provider search.

## Actual network result

An opt-in Swift integration test invoked the actual `WorldwideRestaurantSearchService` with the original input and live Open-Meteo / Photon network requests. The Apple Maps fallback spy was not called. In 3.941 seconds the service returned:

1. `osm:n:2569050392` — Da Andrea — `35 West 13th Street · Union Square · Manhattan · New York · NY · United States · 10011`.
2. Da Andrea — `160 8th Avenue · Chelsea District · Manhattan · New York · NY · United States · 10011`.

The desired branch is first. The provider's actual `Union Square` locality is preserved, not rewritten to Greenwich Village. Same-name branches remain distinguishable by their real addresses.

## Verification

Command (explicit network opt-in; otherwise the live test is disabled):

```sh
TEST_RUNNER_TASTEMAP_LIVE_SEARCH=1 xcodebuild \
  -project ios/TasteMap/TasteMap.xcodeproj \
  -scheme TasteMap -configuration Debug \
  -destination 'platform=iOS Simulator,id=E4F3EED9-89D8-405C-B4CB-7CA816CE3405' \
  -derivedDataPath /tmp/tastemap-search-delete-tests \
  -only-testing:TasteMapTests/RestaurantAcquisitionTests test
```

Result: **47 tests passed**, including live-provider success, the real two-branch/locality mismatch response, wrong-city anchors, non-place anchors, wrong-city businesses, unrelated queries, timeout fallback, cancellation and existing acquisition regression cases.

Evidence:

- `/tmp/tastemap-qualified-search-tests.log`
- `/tmp/tastemap-search-delete-tests/Logs/Test/Test-TasteMap-2026.09.06_22-16-52-+0800.xcresult`

## Acceptance boundary

Service / real-network validation is PASS. This subtask did not stage, install, or visually accept a new Hybrid app on the user's phone. The parent task must build and verify the formal artifact, install the exact private and QA builds as authorized, and inspect the original search input in the intended Hybrid renderer before claiming phone acceptance. No real user restaurants, photos or visits were mutated by these tests.
