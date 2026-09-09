# Discovery D1 optimization — Paid closure

## Decision and boundaries

DISCOVERY D1 OPTIMIZATION: CLOSED.
DISCOVERY PERFORMANCE: PASS FOR TESTFLIGHT (scoped optimization gate).
The user-approved gate requires a clear real read reduction, not universal 80%.
Workers Paid: ACTIVE per account owner's confirmation. Subscription API inspection
was denied (403); billing subscription was not independently verified by this task.
Development queries now succeed. This does not establish historical Sync 500 cause.

Production: NOT MODIFIED. No Worker deployment (Development or Production), no
phone install, Sync retry, mutation queue change, renderer switch, Final RC or
TestFlight upload. This is not a claim that optimized Worker code is already live.

Source HEAD: 9859b8cbc99e65984c8cfd935b2ec82a4e2be2a8 plus scoped uncommitted
optimization changes. Other pre-existing dirty files preserved; no commit created.

## Candidate cap: REMOVED

The newly introduced 5,000 cap and its 503 error handler are removed. Candidate
selection returns the full deduplicated UNION without LIMIT; ranking remains
downstream and unchanged. No early top-N, private shared cache or permission bypass.
The >5,000 test compares every returned ID to the full expected set, uniqueness,
and absence of LIMIT. Existing unrelated aggregate/photo safety contracts are not
changed by this closure. No new feature flag or production capacity default.

DISCOVERY CORRECTNESS: UNCHANGED.

## Development 0041 migration: PASS

Target: food-map-db-development / b1ddde34-c459-49bb-b9d1-7a41303ccb2d only.
Before: migration ledger contained 40 entries through the two 0038 migrations;
the three new index names did not exist. Existing city/Visit/Want indexes have
different expressions, order or partial predicates, not duplicate definitions.
Only 0041 was executed; other pending migrations were deliberately not applied.

Verified sqlite_master definitions for:

- idx_restaurants_discovery_trimmed_city
- idx_visits_discovery_candidate
- idx_wants_discovery_candidate

All statements use CREATE INDEX IF NOT EXISTS. After successful creation and
verification, only 0041 was added to d1_migrations using ON CONFLICT DO NOTHING.
Repeating all three statements returned changed_db=false, rows_written=0.
The sequential procedure is restart-safe, not claimed to be one atomic migration.
No Restaurant, Visit or WantToGo content INSERT/UPDATE/DELETE was executed.
Index creation changes database index pages; it is not a user-data mutation.

Deployment dependency: optimized readers reference these indexes explicitly;
0041 must exist in any environment before deploying those readers. Production
has NOT been migrated, and Production deployment remains out of scope.

## Bounded real Development D1 A/B

Two complete For You handler executions, one before migration using the two
pre-optimization readers at HEAD, one after migration using current readers.
Same existing owner, Hangzhou scope, limit=20, fixed ranking clock, current live
Development data. No synthetic user/account/Restaurant/Visit creation.
The handler ran locally with its D1 adapter executing actual SQL via authenticated
Cloudflare management API. Every query records D1 meta.rows_read and duration.
This bypasses neither SQL visibility predicates nor ranking; it does not test
HTTP authentication middleware or claim an optimized endpoint deployment.
Normal handler quota accounting wrote two refresh events; no business entities
or phone mutations were touched. Hard diagnostic bounds: 25 SQL statements and
200,000 observed reads per handler, two handlers only; this was an explicit
bounded exception to the default diagnostic budget to measure the known baseline.

| Measurement | Historical Insights avg | Real before | Real after |
|---|---:|---:|---:|
| Visit aggregate | ~18,592 | 18,596 | 445 |
| WantToGo | ~7,181 | 7,183 | 59 |
| Place Identity | ~3,642 | 3,646 | 112 |
| Entire For You handler | not comparable | 29,476 | 1,002 |
| D1 SQL duration sum | not recorded | 49.5975 ms | 18.1586 ms |

Total read reduction: **96.6006%**, including new candidate selection reads
(109 + 113 + 113). Before/after SQL counts: 11 / 14. More cheap SQL statements
do not imply more HTTP Discovery refreshes. Historical Insights averages are
context only; the percentage uses the matched current real handler totals.
Two handlers consumed 30,478 reads total, not an unbounded scan or load test.

Database latency improved in this single sample. Management-API round trips and
local adapter overhead are not Worker request latency; no device p95, sustained
load or global billing forecast is claimed. Dense-city further optimization is
post-TestFlight work, not a remaining 80% blocker.

## Response and permission evidence

Real response SHA-256 identical:
d1504660221e0b9d4a83b20f9575e70f03e3cfa25c0c2c45b2b997ce814dc4a5.
This account/scope returned zero cards on both sides, so it alone cannot establish
nonempty ranking correctness. Separate exact full-response comparisons after cap
removal passed for For You, Same Taste, Trending and Latest in BOTH multi-city
and dense single-city fixtures. Multi-city results include 12/12/20/20 cards.
Existing owner/visibility/block/deletion/Premium/photo eligibility suites pass,
including permission changes across consecutive requests without long-lived cache.

Default canonical content refresh: 3 mode requests -> **1 For You request**.
Other selected tabs retain explicit page loading. Contract test proves this source
schedule; no new installed-device network evidence is claimed in this SQL task.

## Automation and evidence

177 source test files / **1513 tests PASS**, 0 fail, 0 skip, 0 todo.
TypeScript application build check and Worker noEmit: PASS.
Nonempty exact benchmark parity: 8/8 mode/scenario comparisons PASS.
Source suite command: vitest run --exclude '**/.private/**'. This excludes local
archived deployment copies, not shipping tests. An initial broad filename match
also discovered a stale migration test in .private/privacy-production-candidate;
that archive was left untouched. No source test was deleted, skipped or weakened.

Private raw evidence: /tmp/tastemap-discovery-closure.cBCLaC (directory mode 700,
real account/SQL parameter evidence files mode 600; not in Git). Includes Dev
preflight, index application/repeat metadata, real-before/after JSON, safe summary,
test log, temporary benchmark harness and output. No tokens stored in reports.
Earlier synthetic benchmark evidence remains /tmp/tastemap-discovery-cost.Wx50fG.

## Final state

WORKERS PAID: ACTIVE (owner confirmed)
CANDIDATE HARD LIMIT: REMOVED
DEV 0041 MIGRATION: PASS
DEFAULT DISCOVERY REQUESTS: BEFORE 3 / AFTER 1 (source contract)
REAL D1 TOTAL REDUCTION: 96.60%
LATENCY: database-side single-sample improvement; deployed endpoint p95 not measured
DISCOVERY RESULT PARITY: PASS (real empty response + nonempty exact fixtures)
PERMISSION / PRIVACY: PASS (regression suite; no policy changes)
FULL AUTOMATION: PASS
DISCOVERY D1 OPTIMIZATION: CLOSED
DISCOVERY PERFORMANCE: PASS FOR TESTFLIGHT
MIGRATION NUMBER COLLISION: OPEN — RESOLVE DURING FINAL INTEGRATION
PRODUCTION: NOT MODIFIED

POST-TESTFLIGHT PERFORMANCE BACKLOG:
Dense same-city optimization / production observability.
Observe representative dense-city endpoint latency and rows_read after separately
authorized rollout. Keep the existing ~33.6% dense-fixture work reduction as an
optimization opportunity, not a release blocker. Consider further work only when
real operational measurements justify it; no materialized recommendation tables,
shared private cache or algorithm redesign is part of this task.

## Final Integration blocker: migration number collision

Recorded by explicit owner instruction on 2026-09-09. Discovery performance work
is closed; do not extend this task to resolve the collision on independent branches.

- Current integration/Discovery migration:
  `0041_discovery_candidate_indexes.sql`, already applied to Development D1.
- Independent Photo Delete branch migration (reported by the owner):
  `0041_photo_deletion_fences.sql`.
- Both must not retain number 0041 in the final integrated migration sequence.
  This is an OPEN Final Integration/deployment sequencing blocker, not a reversal
  of the accepted Discovery performance result.

### Required integration and deployment plan

When Photo Delete is integrated into `feature/hybrid-final-integration`:

1. Read the actual final integration migration history and target-environment
   migration ledger. Check all occupied numbers after 0040, including concurrent
   work; do not assume that 0042 is available now or at integration time.
2. Preserve the executed Discovery migration filename and Development ledger
   identity `0041_discovery_candidate_indexes.sql`. Do not rename its applied
   history, remove its ledger entry, or rerun its already-applied indexes.
3. Verify the other migration has not entered the target environment, then assign
   that unapplied migration the next legal unused number (0042 only if free).
   If the actual ledger contradicts that premise, stop and reconcile deployment
   history rather than rewriting an already-applied migration identity.
4. Update the migration filename, registry/runner if present, fixtures, migration
   tests, documentation and deployment plan together in the integration change.
5. Before Production deployment, prove the integrated migration sequence is
   unique, continuous and conflict-free and that the runner skips the already
   applied Discovery migration in Development. Check the complete historical
   sequence too: the current repository has legacy duplicate 0036/0038 prefixes
   and no 0039 file; do not silently renumber applied history or claim a global
   sequence PASS without reconciling those historical facts.
6. Production remains NOT MODIFIED by this task. Any future Production migration
   requires its own target-ledger preflight and separately authorized deployment;
   Development application is not evidence of Production application.

This recording change renames no migration, changes no runner/test/business code,
and executes no local or remote migration. Existing 1513/1513 test evidence above
is retained; no new automation run is claimed for this documentation-only update.
