# Discovery city search — shared UI source integration

## Scope

The five Hybrid tabs (`following`, `for_you`, `similar_taste`, `latest`, `trending`) now request the explicitly selected city through the additive `discovery.cityPage` contract. The previously loaded local `content.snapshot` is not treated as the city's complete result set. Clearing the city restores that unchanged default snapshot, without altering My Map or GPS.

The shared `TasteMapCitySearch` accepts arbitrary names, exposes loaded-city suggestions and an explicit reset, and normalizes NFKC/whitespace and optional Chinese `市` aliases only in query labels. The city is preserved when switching tabs. The dialog is portaled to the body so the horizontal filter strip does not clip it. The legacy Browser Community page reuses this input, but its older data API is not equivalent to the formal Native city-page capability.

## Query and display safeguards

- New city/tab requests immediately hide the previous query's items.
- The session-only controller checks authenticated ownership before and after async work, drops superseded replies and invalidates on authentication events.
- Continuation requires the accepted opaque cursor and snapshot, bound to the same mode/city/window; producer responses contain cumulative items.
- Cross-snapshot results are rejected. Failed append preserves only the same owner's accepted page; failed refresh/replacement cannot revive an earlier city's items.
- Loading, empty, failure/retry, loaded count and continuation are separate states. A complete query is described as loaded, not as every row being visible after rating filters.
- Unknown/unavailable engagement does not display fake zero-like/comment counts. Restaurant and image target authorization is the Native city producer's responsibility.
- The existing recommendation preference-readiness and excluded-Restaurant chain also applies to city `for_you` results.

## Browser boundary

The formal Browser adapter deliberately throws `capability_unavailable` for city pages. Its local social mutations cannot be used as proof of real server identity or interaction success. This limitation is explicit rather than silently filtering the local snapshot.

## Verification at source handoff

`vitest` passed 34 cases across `discoveryCityQuerySession.test.ts`, `TasteMapCitySearch.test.tsx`, `restaurantCity.test.ts` and `DiscoveryPage.test.ts`. The cases cover all five modes, arbitrary/alias city names, pagination, stale replies, reset, account replacement, cross-query/snapshot rejection and the Browser fail-closed boundary. Selected-file `git diff --check` passed.

The shared TS interface and Native producer are owned by the parallel Native integration task; full app type-check, staged bundle, physical-device interaction and production API availability are separate integration gates. This report does not claim a deployed Worker or installed-device acceptance. No Worker was deployed and no resources were staged or installed by this UI task.
