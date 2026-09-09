# Personal Restaurant aggregate precision — independent product fix

Branch: `fix/personal-rating-precision`; base `9859b8c` (Hybrid integration).
This is production application source, not a screenshot-only implementation.
The dirty integration checkout and screenshot checkout were not modified.
No deployment, Production data access, Release build, installation or screenshot
capture was performed. Existing staged UI resources are not rebuilt in this
source/test checkpoint; installed-app acceptance is not claimed. The user's
explicit instruction is to commit/report the independent algorithm fix first.

## Metric boundary and implementation inventory

| Code/path | Metric and behavior | Disposition |
|---|---|---|
| `src/contracts/syncV1.ts`, `Models/Visit.swift`, `StarRating.tsx`, `AddVisitModal.tsx` | Raw single Visit: 0.5–5 half-stars; native and sync validation | Unchanged |
| `src/services/restaurantSummaryProjection.ts` | Owner Restaurant summary: wrong five-star intermediate rounding | Uses `projectPersonalRestaurantRating`; precise mean and final ten-point rounding |
| `src/services/ratingConfidence.ts` / `RestaurantSocialStatsPanel.tsx` | Same-owner personal Detail rating, already final-scale rounding | Reuses the same numerical helper; unchanged sample/owner/deletion rules |
| `Hybrid/TasteMapHybridBridgeService.swift`, `restaurantDTO` | Owner SwiftData → Hybrid Restaurant DTO; wrong intermediate rounding | Uses `PersonalRestaurantRating.project` |
| Native `RestaurantDetailPresentation.swift`, `RestaurantBrowsePresentation.swift`, `RestaurantRouletteEngine.swift`, `SocialViews.swift` | Personal/fetched-profile Visit means | Already exact means; no algorithm edits |
| Native `RestaurantScoreColorPolicy.swift` | Converts supplied five-star mean to final ten-point score/color | Already final-scale rounding, no intermediate mean rounding |
| `src/services/publicProfile.ts`, `socialApi.ts` | Visible profile/identity-merged Restaurant means | Already exact means then ×2; visibility/dedup/sort unchanged |
| `src/services/analyticsReportData.ts`, `analyticsEvidenceRules.ts`, `analyticsSocialReport.ts`, `profileInsights.ts`, `companionInsights.ts` | Scoped Restaurant means or separately scoped analytics | Exact arithmetic inputs; final formatting only, no early rounding introduced |
| Native `MonthlyRecapAnalyzer`, `AnnualRecapAnalyzer`, `DiningCompanionAnalyzer`, `TasteProfileAnalyzer` | Period/companion/taste-scoped means | Exact means already; preserve independent cohort and ranking |
| `recommendationSourceInsights.ts`, Native `RecommendationSourceAnalyzer` | First-experience evidence, not lifetime personal Restaurant mean | Unchanged |
| Worker `discoveryVisitAggregates.ts` (`tasteSignalsFromDiscoveryAggregates`) / `tasteSimilarity.ts` | Owner Restaurant means used as similarity/recommendation signals | `ratingSum / ratingCount * 2`, unrounded; keep precise ranking |
| Worker `discoveryVisitAggregates.ts` (`ratingFromDiscoveryAggregates`), `discoveryV1.ts`, `index.ts` public helpers | Public/friend/similar cohorts, independent-user weighting, sample thresholds | Independent public contract; unchanged |
| Worker `communityV1.ts` | Public profile-wide mean, not personal per-Restaurant score | Unchanged |
| Worker `restaurantListsV1.ts` | Authorized list record projection, no duplicate personal-score arithmetic | Unchanged |
| `src/db/restaurants.ts`, discovery qualified-evidence and liked rules | Legacy preference thresholds / eligibility | Unchanged |
| `starToTenScore`, Visit history/Activity badges, `reviewService.ts` | Concrete Visit score, not Restaurant mean | Unchanged |

## Downstream consumer check

- Restaurant Detail's personal score uses `ratingConfidence` and the shared helper;
  its public references retain their original independent source.
- Browser map/card/RestaurantList and Hybrid DTO/list rating consume the corrected
  summary. `TasteMapBridgeProjection` forwards `averageRating`/`scoreOutOfTen`;
  Native `listViewerRating` forwards the DTO, not a second rounded average.
- For You/personal prediction consumes corrected summary evidence where it already
  did; weights, ranked evidence, matched-user and liked definitions are unchanged.
- Same Taste retains Worker exact sum/count signals. Activity cards continue to
  show the concrete Visit, never a fallback Restaurant score.
- Taste Profile/month/year/companion analysis computes scoped exact raw means;
  posters (`analysisShare`, `analyticsReportShare`, native analysis poster views)
  consume those results and format them, not a five-star-rounded summary.
- Exact mean consumers keep precision. Display-score consumers naturally see the
  corrected final tenth; no ranking based on exact input was converted to rounded
  input. Existing explicit legacy `Restaurant.overallRating` precedence in the
  Browser summary is preserved, not rewritten or used for Demo overrides.

## Arithmetic and regression evidence

Raw half-star sums are exactly representable. TypeScript rounds the final rational
number using integer tenth-score units and quotient/remainder; Swift uses the
existing Foundation Decimal `.plain` (positive half-up) convention. Neither
rounds the five-star mean. No epsilon, raw-value rounding or schema change.

Shared fixture `hybrid/fixtures/personal-rating-precision.json` is exercised by the
real Browser summary and the real Native Hybrid service over isolated SwiftData:

| Legal raw Visits | Final ten-point output |
|---|---:|
| 4.5 | 9.0 |
| 4.0, 4.5 | 8.5 |
| eight 4.5, one 5.0 | 9.1 |
| 4.0, 4.5, 4.5 | 8.7 |
| four 4.5, one 4.0 | 8.8 |
| 4.5, 4.5, 5.0 | 9.3 |
| seventeen 4.5, three 5.0 (9.15 tie) | 9.2 |

Also tested: empty/unrated, minimum/maximum, deleted Visits, foreign owner,
foreign Restaurant, deleted Restaurant, unchanged source data, unrounded ranking
inputs, preserved explicit legacy override and rejection of illegal raw 4.55/8.8/9.1.
Native tests reopen an on-disk local store and a fresh bridge service. Worker
local SQLite push → pull → replay → pull retains all nine raw ratings, returns
9.1 through the real selector, has no duplicate Visits, and exposes none to a
second owner. No network service or real user was used.

- TypeScript application and Worker typechecks: PASS.
- Swift package: 42 tests PASS (actual Bridge including shared precision cases).
- Focused numerical/confidence/Worker Sync run: 51 tests PASS.
- Full JavaScript suite: 1493 PASS, 3 failed assertions; one additional test file
  cannot parse. All pre-existing failures reproduced with the original base
  implementation: two `HybridQACompanionContract` expectations, one
  `SettingsInteractionContract` privacy-copy expectation, and syntax corruption
  at `worker/authV1.integration.test.js:195`. Not a clean full-suite PASS.
- New regressions against the same baseline: 0 observed.

## Demo follow-up

Read-only evaluation of the existing legal Demo adapter records through this
formal selector yields 栖禾小馆: nine Visits, mean 4.555555555555555, output **9.1**;
椿见食堂: eight Visits, mean 4.375, output **8.8**. No aggregate assignment or Demo
Visit rewrite was used for this check. Screenshot branch integration, authenticated
isolated seed and eight real runtime captures are the next phase, not claimed done.

## Acceptance

RAW VISIT CONTRACT: 0.5–5.0 / step 0.5 — UNCHANGED
USER-FACING VISIT INPUT: UNCHANGED
PERSONAL AGGREGATE: precise mean → ×2 → final round 1 decimal
PERSONAL RATING OUTPUT PRECISION: 0.1 on ten-point display scale
CAN DISPLAY 9.1 / 8.7 / 8.8 / 9.3: YES
BROWSER / NATIVE PARITY: PASS (source/service regression, not installed-app QA)
SYNC CONTRACT CHANGED: NO
DB MIGRATION: NONE
USER DATA REWRITE: NONE
NEW REGRESSIONS: 0 observed against baseline

Design-system scope: numerical projection only. Core controls, Food/Dining visuals
and canonical page layout are unchanged. Browser personal-summary/detail arithmetic
now has one shared numerical owner; Native implementation is verified against the
same fixture. No new UI component, default-SwiftUI layout or screenshot renderer.
