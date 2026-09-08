# Community city API — source-only vertical slice

## Result

Both formal `/api/v1/community/feed` scopes (`following`, `latest`) accept an
explicit `city` and filter authorized Restaurant cities **before** ordering and
`LIMIT`. Empty/omitted city retains all-city behavior; no GPS/profile-city
substitution or local-card filtering is introduced. `杭州`/`杭州市` and ASCII-case
aliases compare consistently, while meaningful `州`/`区` characters remain intact.

The response adds optional `city` as a normalized query echo. The Swift client
sends the explicit city and rejects a nonempty-city request when an old server
omits that echo or returns another city. It therefore fails honestly until this
backend capability is deployed rather than presenting unrestricted results as a
successful city search. Existing no-city calls and older response decoding remain
compatible.

Feed continuation cursors bind viewer ID, feed scope and normalized city as well
as timestamp/event position. Cross-city, all-city, cross-scope, cross-viewer and
profile-content cursors fail with HTTP 400 and require a fresh first page. Old
unbound feed cursors also require refresh after deployment. These cursors are
query-state validation, not authorization tokens; every request still reruns the
existing visibility, follow/friend, block, deletion and qualified-rating policy.
No material is cached or persisted by this addition.

## Exact city-only transplant scope

- New `worker/communityCityQuery.ts` owns city comparison, SQL comparison fragment
  and feed-only cursor encode/decode.
- `worker/communityV1.ts`: only the new helper import and the `readFeed` city
  validation, city predicate/binding before LIMIT, scoped cursor use and response
  echo. **Do not transplant its entire dirty diff**: that file also contains
  unrelated, older activity-photo/HOLD and Discovery eligibility changes.
- `src/contracts/communityContract.ts`: only optional `CommunityFeedPageV1.city`.
- `ios/.../Services/CommunityAPIClient.swift`: city-aware API plus the backward-
  compatible no-city overload and response verification.
- `ios/.../Models/Remote/CommunityV1Contracts.swift`: only optional
  `CommunityFeedPageV1.city`; preserve unrelated existing photo fields.
- Tests: new `worker/communityCityQuery.test.ts`, added city-specific cases in
  `worker/communityV1.integration.test.js`, and new
  `CommunityCityAPIClientTests.swift`.

The city implementation has no dependency on `loadActivityPhotoPool`, album
hydration, the public/friends cache change, Native session overlay, React page
projection or artwork. It is logically separable from the unpublished album
changes by these bounded hunks. An isolated production-base build/test has **not**
been run; selecting that exact base and verifying its patch remains a release
step. No full dirty Worker bundle is eligible for deployment from this report.

## Verification

- 36 JS tests pass: Community integration (21), city/cursor units (7), photo
  binary regressions (8).
- Worker TypeScript check passes.
- Swift parser accepts the API, DTO and new four-case URLSession test suite.
- Native tests are added but not executed here, avoiding the parent's shared
  Xcode/simulator integration run.
- Scoped diff whitespace check passes.

Cases cover two scopes, a city not previously present in the first page, 市 and
overseas case aliases, real continuation order/deduplication, unknown-city empty,
malformed/oversized inputs, cross-query cursor rejection, two-way blocks applied
between pages, private/profile visibility, friendship revocation and unfollow.

## Deliberate remaining boundary

No Worker deployment, DB migration, formal stage, simulator install or phone
sync was performed. The friends-album deployment HOLD is unchanged. This is not
five-tab Hybrid city completion: session-only selected-city projection, target
and image authorization, engagement hydration and UI wiring remain separate.
It does not overwrite shared Map recommendation placements or change any GPS,
Profile, photo, permission, route-owner or poster implementation.
