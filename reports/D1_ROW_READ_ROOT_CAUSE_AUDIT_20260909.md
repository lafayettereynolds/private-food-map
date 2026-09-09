# D1 Daily Row Read Root Cause Audit

## Outcome

Development Discovery is the dominant observed read consumer, not Production cron
or the protected 36-mutation recovery queue. Primary classification: BOTH —
repeated expensive queries. This conclusion does not establish the root cause of
the earlier authenticated Sync/Auth HTTP 500 responses.

Audit window: 2026-09-09 00:00:00–02:40:02 UTC (08:00–10:40 CST).
Only Cloudflare database inventory, GraphQL analytics, Worker schedules metadata,
existing local logs, source and local SQLite EXPLAIN were used. No remote business
SQL, deployment, index creation, data mutation, device launch or sync retry.

## Account-wide database usage

Account database listing returned exactly two databases; no other historical/test
database was returned. Metrics are adaptive Analytics, not a billing ledger.

|Database|ID|Rows read|% of observed account reads|Read queries|Rows written|Write queries|
|---|---|---:|---:|---:|---:|---:|
|food-map-db-development|b1ddde34-c459-49bb-b9d1-7a41303ccb2d|5,018,890|99.99936%|3,049|878|633|
|food-map-db|064f6607-5464-4530-bc58-5f7d1e02f09f|32|0.00064%|32|0|0|
|Total||5,018,922|100%|3,081|878|633|

Query Insights independently reports 5,922,271 reads for the top three Development
queries. This exceeds the overview total. Do not add these two datasets or assign
precise billing percentages from them. Both are adaptive datasets and their
aggregation/sampling/availability can differ; exact reconciliation was not obtained.
The dominant database and SQL family are nevertheless unambiguous in both views.

## Top 20 by cumulative reads and source mapping

All rows below are Development. Avg = sum/count (rather than the API's rounded
average). Full normalized SQL, writes, all three requested sorts (sum reads,
execution count, average reads), and all 20 local plans are in the private appendix:
`/tmp/tastemap-d1-audit.cwwth6/QUERY_INSIGHTS_APPENDIX.md`.
Insights truncates the first SQL at its final ORDER BY; the local EXPLAIN uses its
complete matching source template with the same city predicate.

|#|Query family / source (relative to repository)|Reads|Executions|Avg reads|Classification|
|---|---|---:|---:|---:|---|
|1|Visit CTE/window aggregation — worker/discoveryVisitAggregates.ts:101|3,569,676|192|18,592.06|BOTH|
|2|Want-to-go UNION — worker/discoveryV1.ts:377|1,536,734|214|7,181.00|BOTH|
|3|Place identities city/owner — worker/discoveryV1.ts:364|815,861|224|3,642.24|BOTH|
|4|Own restaurants — worker/discoveryV1.ts:373|3,305|119|27.77|NORMAL|
|5|Eligible photo pool — worker/discoveryV1.ts:408|3,212|322|9.98|HIGH FREQUENCY, small cost|
|6|Access session lookup — worker/authV1.ts:124|682|344|1.98|HIGH FREQUENCY, small cost|
|7|Preference events — worker/discoveryRecommendationFeedback.ts:8|675|75|9.00|NORMAL|
|8|Owner membership history — worker/index.ts:1863, shared entitlement dependency|580|290|2.00|HIGH FREQUENCY, small cost|
|9|Session last-used update — worker/authV1.ts:134|462|468|0.99|HIGH FREQUENCY, 462 writes|
|10|Three-table schema evidence — prior diagnostic sqlite_master query|304|1|304.00|NORMAL diagnostic|
|11|Pending rewards — worker/referralsV1.ts:37|245|245|1.00|HIGH FREQUENCY, small cost|
|12|Discovery quota lookup — worker/discoveryV1.ts:1137|230|230|1.00|NORMAL prerequisite|
|13|Referral qualification — worker/referralsV1.ts:22|208|26|8.00|NORMAL|
|14|Profile lookup — worker/profileV1.ts:44|176|176|1.00|NORMAL|
|15|Bounded restaurant ID evidence — prior targeted diagnosis SQL|164|4|41.00|NORMAL diagnostic|
|16|Bounded Visit ID evidence — prior targeted diagnosis SQL|152|4|38.00|NORMAL diagnostic|
|17|Discovery quota upsert — worker/discoveryV1.ts:1134|144|160|0.90|NORMAL prerequisite, 176 writes|
|18|Refresh photo IDs — worker/syncV1.ts:1450|80|16|5.00|NORMAL, 16 writes|
|19|Expire owner quota windows — worker/discoveryV1.ts:1129|73|73|1.00|NORMAL|
|20|Incremental sync change log — worker/syncV1.ts:324, sync pull|45|39|1.15|NORMAL|

Ranks 8/20 use dynamic table names in their source templates. Diagnostic ranks
10/15/16 are from the previous bounded recovery audit,
not an application endpoint. Their combined visible cost is 620 reads; this is not
a complete account-wide diagnostic total.

## Why Discovery is expensive

`worker/discoveryV1.ts:164` calls readDiscoveryData before ranking/pagination.
`readDiscoveryData` at :338 reads city Visit aggregates and may run a second
candidate-owner aggregate at :342, then loads identities/wants/photos. A page size
of 20 does not bound rows scanned before ranking. SQL LIMIT after aggregation does
not prevent the preceding work.

`ios/TasteMap/TasteMap/Hybrid/TasteMapHybridRuntime.swift:244` concurrently refreshes
for_you, similar_taste and trending. Each server request repeats the underlying
read model. This is a concrete amplification opportunity, not proof every observed
request originated from build 2026090902. The current coordinator has 30-second
success reuse, in-flight reuse for non-forced refresh and 60–900 second error
cooldown; there is no evidence here of a tight unconditional polling loop.

Local EXPLAIN with all current migrations succeeds for all 20 SQLs:

- #1 searches idx_visits_deleted_at, then PK/index joins; GROUP BY, both window
  orderings and final ordering use temporary B-trees; scans intermediate results.
- #2 searches idx_restaurants_deleted_at, then restaurant_id join to wants and
  profile PK; block checks use indexes. It does not narrow by the city index first.
- #3 searches idx_restaurants_deleted_at, joins identities by restaurant_id,
  scans json_each and uses a temporary B-tree for DISTINCT.

INDEX USED: YES in these local plans, but low-selectivity deleted_at lookup can
still traverse nearly every active record. It is incorrect to say all JOIN indexes
are missing. Production/Development physical index parity was not queried remotely.
Local fixture has complete schema but no production cardinality/statistics;
therefore these plans are structural evidence, not a production cost benchmark.

### Existing versus proposed indexes

Existing 0025 indexes cover restaurants(city,id,user_id), visits visibility/time
and owner/time, want-to-go time/restaurant/owner, and identity lookup. Existing
block pair and moderation indexes also participate in plans.

Candidate improvements, NOT applied and NOT proven remotely absent:

1. Active real restaurant expression index on TRIM(city), id, user_id with the
   exact deleted_at / COALESCE(is_test_data,0)=0 predicate, or a separately reviewed
   canonical normalized city field. Plain city index does not directly match TRIM.
2. Active real Visits (restaurant_id,user_id,visibility,visited_at DESC,id), after
   rewriting city candidates to drive joins. Do not merely add another owner index.
3. Active real wants (restaurant_id,user_id,created_at) to support candidate joins.
4. Split moderation OR into separately indexed content-type/content-ID EXISTS
   branches if representative plans show benefit; current status-led lookup does
   not fully exploit all keys through the OR.

Split city and self-owner eligibility into deduplicated branches before joining;
preserve owner visibility, friends, blocks, reports, account deletion and exact
rating semantics. No arbitrary history truncation or cross-user shared cache.

## Cron D1 budget

Cloudflare schedules API enumerated all three Workers:
fancy-fog-1341: none; private-food-map-development: none;
private-food-map: */5 * * * *.

|Job|Frequency|Observed reads/run|Estimated reads/day|
|---|---|---:|---:|
|Production settleAllPremiumRewards, worker/referralsV1.ts:82|5 min / 288 daily|1 (32 queries, 32 reads)|288 at current empty/small pending state|
|Development scheduled jobs|No configured schedule|0|0|
|Account deletion retry, current source worker/index.ts:644|5 min only if PRIVACY_RETENTION_ENABLED=true|Not measured|Unknown if activated|
|Privacy retention, current source worker/index.ts:647|18:00 UTC only if same flag=true|Not measured|Unknown if activated|

Today Production Insights contains only the pending-reward sweep (32 reads), so
there is no observed large retention/cleanup contribution in this window. Current
source gated jobs are not proof they are deployed/enabled. Future pending rewards
growth can increase sweep cost; LIMIT 500 bounds output, not all scanning.

## Sync / device evidence

Existing tail contains 10 auth/refresh and
1 sync/push, all HTTP 500, over 310.749 seconds. Exact epoch interval:
1788919340648–1788919651397 milliseconds = 2026-09-09 02:02:20.648–02:07:31.397 UTC.
This is a short captured slice, NOT today's total endpoint counts. No complete
historical request-path dataset was available in this audit. Query executions
cannot safely be substituted for endpoint counts.

SyncCoordinator retry scheduling is exponential from 5 seconds to a 60-second cap;
this can sustain failing requests while running, but the captured device was stopped.
Visible incremental change-log cost is only 45 reads / 39 queries. Auth access
lookup is 682 reads. Neither is the million-row dominant family in Insights.
No attribution of all Discovery calls to this phone or to another task is made.

## Order-of-magnitude budget and options

Current overview burn rate if sustained without quota: about 45.2M reads/day
(5.019M over 2.667 hours). This is an extrapolation, not actual daily consumption.
Three heavy SQL averages total roughly 29,415 reads per read-model load; assume
30,000 reads/request for planning, excluding a possible second aggregate pass.

Plan A: share/deduplicate authorized read-model work across the three modes;
candidate-first SQL and predicate-aligned indexes; cache only with owner, scope,
permissions and invalidation correctness; do not bypass moderation. Target >=80%
less work/request plus avoiding up to 2/3 duplicated mode reads. Combined ideal
reduction ~93%, giving ~3M reads/day at today's extrapolated request pattern.
This is an engineering target, NOT measured savings or a deployed fix.

Plan B: remote Dev E2E only, local full-fixture diagnostics. Before each remote
diagnostic require query identity, local EXPLAIN and conservative scanned-row bound.
Proposed per-round budget 10,000 rows, individual query 1,000; unknown bounds stop
for approval. LIMIT alone is not a bound. Log D1 meta.rows_read cumulatively and
stop before the next query at the budget; it cannot cancel an expensive first query.
Analytics APIs are preferred. Distinct Dev/Prod databases still share account quota.
No policy file or enforcement code was changed in this audit.

Planning model after optimization: every user active daily, 5 uncached read-model
loads/user/day, 5,000 reads/load, plus 10,000 daily maintenance reads; 30 days/month.
Does not account for data-volume growth, writes or all non-Discovery endpoints.

|Users|Current 30k reads/load/day|Target reads/day|Target reads/month|
|---|---:|---:|---:|
|100|15.01M|2.51M|75.3M|
|1,000|150.01M|25.01M|750.3M|
|10,000|1.50001B|250.01M|7.5003B|

Free after fix: BORDERLINE for current development; not a robust production plan
at 1,000+ daily active users under these assumptions. Actual DAU, city cardinality,
cache hit rate and history growth must replace these illustrative assumptions.

Plan C: recommend Workers Paid alongside optimization, not instead of it. Official
pricing checked: $5/month minimum Workers subscription, first 25B D1 reads/month
included, then $0.001/million. Under the target scenarios above, incremental D1
read charge is $0; total invoice is NOT guaranteed $5 because writes, storage,
Worker request/CPU, R2 and other account usage have separate limits/prices.

Sources: https://developers.cloudflare.com/d1/platform/pricing/ and
https://developers.cloudflare.com/workers/platform/pricing/ . No subscription change.

## Final status / next actions

D1 DAILY LIMIT: 5,000,000 rows read/day, account-level.
TODAY TOTAL ROWS READ: 5,018,922 in overview as of 02:40 UTC.
TOP CONSUMING DATABASE: food-map-db-development.
TOP CONSUMING QUERY: Discovery eligible Visit CTE/window aggregate.
TOP QUERY TOTAL READS: 3,569,676 (Insights).
TOP QUERY EXECUTIONS: 192 (Insights).
PRIMARY TYPE: BOTH.
CRON CONTRIBUTION: 32 observed Production reads; not primary cause.
SYNC CONTRIBUTION: small in visible query families; full endpoint totals unknown.
DIAGNOSTIC CONTRIBUTION: at least 620 in explicitly matched top-20 diagnostics;
not an exhaustive category total.
BUG / QUERY OPTIMIZATION REQUIRED: YES.
ESTIMATED READS AFTER OPTIMIZATION: ~3M/day engineering target under same current
request pattern, not benchmarked.
FREE PLAN SUFFICIENT AFTER FIX: BORDERLINE development; NO guarantee at scale.
WORKERS PAID RECOMMENDATION: YES, while fixing Discovery amplification.
PRODUCTION MODIFIED: NO.

Next: authorize a separately scoped Discovery optimization with representative
local fixtures and measured read budget; decide Paid upgrade independently;
then resume isolated Development Auth/Sync fixture diagnosis. Keep the 36 original
device mutations untouched until safe fixture verification passes.
