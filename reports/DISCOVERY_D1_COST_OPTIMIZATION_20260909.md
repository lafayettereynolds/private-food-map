# Discovery D1 cost optimization — local candidate

> Historical pre-Paid evidence snapshot. The current acceptance decision is
> [Paid closure](DISCOVERY_D1_PAID_CLOSURE_20260909.md): the 5,000 candidate guard
> has been REMOVED, Development 0041 applied, real D1 measurements completed,
> and the universal 80% gate retired by explicit user decision. Sections below
> describe the earlier checkpoint, not current deployment/migration status.

## Acceptance boundary

Local implementation and regression PASS. Universal >=80% billed D1 rows-read
reduction is NOT PASS: remote measurements were not run, and a dense single-city
fixture still has substantial aggregation work. No Development/Production deploy
or migration, no phone build/install, no Sync retry, no data modification.
Paid-plan choice remains independent of this performance gate.

HEAD: 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8. Working tree already dirty; existing
changes retained. No new commit created, no unrelated changes staged or included.

## Implementation

- worker/discoveryCandidates.ts: independent city and owner candidate branches,
  deduplicated before expensive work. Keeps historical TRIM(city) behavior rather
  than rewriting user data. Visit-owner and Want-owner branches retain cross-city
  own records even when the referenced Restaurant has another owner.
- Candidate IDs are request-local, not cached globally or across authenticated
  requests. Existing row-level visibility/friend/block/moderation/deletion checks
  remain in the original readers; no access decision is memoized across requests.
- Candidate queries return at most 5,001 sentinel IDs. Above 5,000, return explicit
  DISCOVERY_CANDIDATE_CAPACITY HTTP 503 before ranking. This is an additional safety
  capacity boundary: it may reject a very large candidate scope that previously
  completed. It does not silently truncate or claim complete top-20 ranking.
  This boundary needs evaluation on actual city sizes before deployment.
- worker/discoveryVisitAggregates.ts: candidate IDs drive Restaurant/Visit joins;
  eligible and ordered data materialized within the SQL request. One ROW_NUMBER
  ordering replaces two: minimum qualified latest_position selects the identical
  latest qualified Visit (timestamp DESC, ID ASC), preserving counts, sums, rating,
  nil, zero, first time and actual evidence identity.
- worker/discoveryV1.ts: identity and Want queries start from candidate IDs;
  original final ranking, filters, alias semantics and pagination unchanged.
- worker/index.ts: only a typed Discovery candidate-capacity JSON boundary added.
  Existing unrelated dirty Referral/Auth changes were not authored by this task.
- TasteMapHybridRuntime.swift: canonical content.snapshot primes For You only,
  rather than For You + Same Taste + Trending. Existing selected-tab cityPage
  requests remain; no UI layout, route owner, renderer default or API redesign.
- Diagnostic guard and policy: 10,000 estimated reads/round, 1,000/query, local
  plan evidence, explicit override for broad/unknown/high-cost requests, actual
  read metadata accounting. This helper cannot intercept direct Wrangler calls
  and does not throttle Production traffic.

## Indexes (local migration 0041 only)

1. idx_restaurants_discovery_trimmed_city: (TRIM(city),id,user_id), active/non-test
   partial predicate. Matches existing whitespace-normalized city reads.
2. idx_visits_discovery_candidate: (restaurant_id,user_id,visibility,visited_at DESC,id),
   active/non-test partial predicate. Supports candidate-driven Visit history.
3. idx_wants_discovery_candidate: (restaurant_id,user_id,created_at), active/non-test
   partial predicate. Supports candidate-driven saves.

Existing owner indexes are reused for separate owner candidate branches. No new
identity index: restaurant_place_identities already has a restaurant index. Local
EXPLAIN showed planner choosing low-selectivity deleted_at for candidate branches
without hints; the candidate reader pins the expression/established owner indexes.
Therefore 0041 must exist before this Worker can be deployed. Do not blindly run
all pending migrations, particularly unrelated retention migration 0040.

No remote schema inspection or city-data scan was performed. Current persisted
city whitespace prevalence remains unknown; whitespace fixtures prove compatibility.

## Reproducible baseline

Two readers at HEAD are clean pre-task versions. Build helper freezes only those
two files from that revision while keeping the SAME fixture and remaining code on
both sides. Baseline schema applies all pre-0041 migrations; after includes 0041.
No current Production frontend or Worker identity is inferred from this benchmark.

Commands (Node runtime with node:sqlite):

```sh
node scripts/build-discovery-cost-benchmark.mjs /tmp/BEFORE.mjs 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8
node scripts/build-discovery-cost-benchmark.mjs /tmp/AFTER.mjs
node /tmp/BEFORE.mjs /absolute/existing/before-directory
node /tmp/AFTER.mjs /absolute/existing/after-directory --optimized
python3 scripts/measure-discovery-local-cost.py /absolute/existing/before-directory
python3 scripts/measure-discovery-local-cost.py /absolute/existing/after-directory
```

Add --dense to both executions for the second scenario. Evidence paths:
/tmp/tastemap-discovery-cost.Wx50fG/{before,after,dense-before,dense-after}.
Each has benchmark.json (SQL, binds of synthetic IDs only, plans, latency, response),
fixture.sqlite and local-cost.json. No real user payload or credential is used.

SQLite VM instructions are an executed-work proxy, NOT rows_read, returned rows,
or a billing estimate. The local Miniflare D1 probe did not initialize successfully
and was stopped; no rows_read value was fabricated. Exact remote D1 cost is NOT YET.

## Scenario A — many irrelevant-city records

4,040 Restaurants / 20,200 Visits; 40 target-city Restaurants, overlapping provider
identities and varied ratings, whitespace cities, own history and other owners.
All four response objects compare equal before/after at the same frozen clock;
For You 12 cards, Same Taste 12, Trending 20, Latest 20 (first page).

|Mode|SQL before → after|VM instructions before → after|Reduction|Single local latency before → after|
|---|---:|---:|---:|---:|
|For You|12 → 16|4,056,132 → 143,660|96.46%|54.34 → 24.06 ms|
|Same Taste|12 → 16|4,053,216 → 141,002|96.52%|36.78 → 5.93 ms|
|Trending|11 → 15|4,052,637 → 140,345|96.54%|36.38 → 5.07 ms|
|Latest (unchanged reader)|13 → 13|1,475,398 → 1,475,541|effectively unchanged|11.65 → 11.62 ms|

Latencies are one local process sample, not network latency or a p95 benchmark.
Minor unchanged-Latest VM differences arise with the additional schema/index plan,
not a changed Latest implementation. More statements are now cheap candidate reads.

|Core query|Before VM instructions|After VM instructions|Reduction|
|---|---:|---:|---:|
|City Visit aggregate|1,902,847|65,835|96.54%|
|Related-owner Visit aggregate|1,983,832|66,442|96.65%|
|Want-to-go|89,672|2,167|97.58%|
|Place Identity|77,067|1,405|98.18%|

Three-mode old refresh: 35 SQL / 12,161,985 VM instructions. New canonical refresh:
one For You request, 16 SQL / 143,660 VM instructions. Hidden tabs load on demand.
Requests per canonical refresh: 3 → 1 (66.7% fewer). Visiting all tabs still causes
their separate authorized requests; do not claim one endpoint supplies all modes.

## Scenario B — dense same-city data (important remaining bottleneck)

440 Restaurants / 2,200 Visits, all same city. All four response objects still
compare equal. Candidate formation cannot discard relevant restaurants safely.

|Mode|VM before|VM after|Reduction|
|---|---:|---:|---:|
|For You|2,349,381|1,560,143|33.59%|
|Same Taste|2,346,465|1,557,485|33.62%|
|Trending|2,345,886|1,556,828|33.64%|

Single-request latency improves only modestly here (~66.1→60.6 ms first For You;
~35.3→29.9 ms Same Taste; ~34.2→28.9 ms Trending). The default three-to-one request
reduction helps total opening cost, but single-query 80% is NOT met by this proxy.
Do not substitute scenario A as universal evidence.

Remaining work: full relevant history is still required for exact similarity,
rating averages and rank; one window and group-by still need temporary B-trees.
Further large reductions for dense cities require a separately measured exact
summary/read-model strategy with mutation/permission invalidation, or a proven
ranking bound. Arbitrary early top-N would violate the preserved product contract.
No permanent or cross-user cache was introduced to conceal this limitation.

## Tests and release boundaries

- Full source suite: 177 files / 1,513 tests PASS; 0 fail/skip/todo reported.
- Discovery, membership, privacy, account isolation, Photo eligibility, Gift and
  Referral existing suites remain in that full run. Four new cost/candidate tests
  plus three diagnostic-budget tests; migration test now asserts all three indexes.
- tsc -b and Worker tsc --noEmit PASS.
- Full Web production build PASS into private temporary output (no dist/staged
  asset overwrite). Existing chunk-size advisory remains.
- Native changed file syntax parse PASS. No signed native build/device behavioral
  acceptance claimed for the changed fetch schedule.
- git diff --check PASS.

Design System: existing Core controls, Food visuals, page templates unchanged.
No UI visual acceptance was performed or needed to claim a local SQL result.
Renderer ownership and HYBRID_PRIMARY untouched; no Final RC/TestFlight.

## Final status

BASELINE / OPTIMIZED D1 ROWS READ: exact values UNMEASURED; historical baseline
Insights remains ~18,592 / 7,181 / 3,642 per core query, not this fixture's meter.
LOCAL READ-WORK REDUCTION: ~96.5% cross-city, ~33.6% dense city.
80% UNIVERSAL / REMOTE READ GATE: NOT MET / NOT YET VERIFIED.
REQUESTS PER DEFAULT DISCOVERY REFRESH: 3 → 1.
PRIVACY / PERMISSION REGRESSION: none observed in automation and exact comparisons.
DISCOVERY TESTS: PASS.
FULL WEB/WORKER AUTOMATION: PASS.
D1 FREE AFTER OPTIMIZATION: BORDERLINE; do not promise dense-city sufficiency.
PAID STILL RECOMMENDED: YES, independently of the outstanding optimization gate.
COMMIT: no new commit; HEAD above plus scoped working-tree changes.
PRODUCTION: NOT MODIFIED.
