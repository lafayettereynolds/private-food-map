# 数据模块：先讲一个重点，再按兴趣深入

## Final status: implementation saved; final artifact BLOCKED

The initially staged short-home implementation passed the checks below. Later,
concurrent edits changed `HybridDiscoveryPage.tsx` into an uncompilable intermediate
state (unresolved filter controls/state/types), and independently changed
`analyticsTasteReport.ts` at 19:09:23 from a three-rated-Visit gate to five rated
Restaurants with changed cuisine scoring semantics. These overlapping changes are
preserved, not reverted or silently approved. The current Browser acceptance
fixture no longer reaches the new high-score gate and requires reconciliation
against the final approved analyzer, not weakened assertions.

Final west-cuisine artwork mapping and cuisine distribution bars are saved in
source but NOT installed: the final formal-stage run stopped at the unrelated
Discovery compile errors. The installed QA app is the previously verified
short-home baseline, not proof of the latest source. Final artifact gate therefore
remains FAIL / STALE ARTIFACT pending a single coordinated source owner and rebuild.
No physical iPhone or production update occurred.

The isolated native touch run DID pass all five homes, scrolling to the complete
analysis CTA, original-record access and return, retaining 15 screenshots in
`/tmp/tastemap-story-homes-touch-v2-20260907.xcresult`. This run used the earlier
verified bundle before the final artwork/chart and concurrent analyzer edits.
Monthly and Source were honest empty/insufficient-sample states in the native
rich fixture; their populated layouts were covered in the Browser cases.
The earlier failed touch run was a test query error: WebKit exposed aria-pressed
controls as Switches rather than Buttons. Correcting the query produced PASS.

## Scope and implementation

Latest Lafayette five-phone reference governs the five DATA homes. The previously
approved Taste poster is not redesigned. Browser and formal iOS Hybrid use
`TasteMapAnalyticsPage → AnalyticsReportDataView`, backed by the same immutable-in-use
`buildAnalyticsReport` snapshot as poster/share. No routes, entitlements, production
data or physical-iPhone installation are changed.

- Taste: factual headline; frequency/rated lenses; one data-linked illustration;
  at most four cuisine values; compact reliable habits; one finding; detail CTA.
- Monthly: one exploration/revisit story, scoped Restaurant memory collage,
  Visits/Restaurants/first-recorded Restaurants/repeat Visits, one Restaurant.
- Annual: actual covered-month range, memory collage, four annual facts, one
  most-frequent Restaurant labelled by its calculation rather than "最爱".
- Companion: selected person, explicitly owner-authored average score, shared
  Visits/Restaurants/first-owner-experience-with-person/shared repeat Visits,
  up to three repeated or once-recorded Restaurant memories with honest labels.
- Source: qualified top-three sources, high-score numerator/denominator, no food
  hero or negative list on home, a verified high-score Restaurant action. Opening
  another source updates the report selector and its poster/share identity.
- Details: themes and chapter selection, one chapter at a time; time, recorded
  taste-tag and spending-range bars; all values remain available; complete
  owner/period/person-scoped Visit rows with private notes remain private.
- Lower-rated source comparison is in details, including per-source Restaurant
  drill-in. Existing source-quality rules and privacy defaults are retained.

## Data correctness

Rich QA seed previously assigned every sample a companion, including `.solo`,
and concentrated all times around one UTC base hour. The fixture now assigns
explicit local 08/12/15/19/23 meal hours, no companions to solo samples and consistent
party sizes. This changes QA totals where calculated spending depends on party
size; it does not edit real user records.

Analysis separately handles contradictory solo + named/social context: retain
the original Visit, label the conflict, exclude it from solo/together score
comparisons and individual companion attribution. Date-only Visits remain valid
record totals but cannot become midnight or late-night evidence. Same-name dishes
at different Restaurants are not merged.

## Verification

- 171 focused Vitest tests passed across 8 suites, including all five reports,
  source and companion sample rules, shared poster projection/privacy, semantic
  contract, default short-home topology and complete topic partition.
- `check-analytics-story-home.mjs`: PASS, 20 viewport/theme cases (375/402 ×
  light/dark × five reports), no horizontal overflow; DATA home height 704–999 px.
  Verified lens switching, samples, source drill-in/selector identity, one detail
  at a time, original rows, Restaurant actions, return and empty states.
- `check-analytics-report-fusion.mjs`: PASS, historical period retention, person
  switching, text-share privacy, actual PNG preview and byte-identical share Blob.
- Formal stage: typecheck, Hybrid build and Release local-bundle purity passed.
- Build: `TasteMap QA`, `DebugQA`, fixed iPhone 17 Pro simulator
  `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`.
- Branch/base: `feature/hybrid-final-integration`, `58bd556`, dirty worktree
  preserved. Built app:
  `/tmp/tastemap-profile-status-derived/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Dist → formal staged resources → built app → installed app: 26 files match
  byte-for-byte. Installed QA app starts Hybrid Development by build flag, no
  injected launch arguments; Map → Profile → Taste inspected in the actual app.
- Native touch test added: `testHybridFiveStoryHomesAndReachableDetails`.
  QA scheme has no Test action; DebugQA test targets lack configurations. The
  isolated Debug test run explicitly launches Hybrid Development with rich QA
  fixture, rather than changing the formal app's scheme or runtime ownership.
  Final touch-test outcome is recorded below after the run.

## Visual evidence (controlled QA data, not an analysis of Lafayette)

- [Taste](analytics-story-2026-09-07/tastemap-story-taste-402-light.png)
- [Month](analytics-story-2026-09-07/tastemap-story-monthly-402-light.png)
- [Year](analytics-story-2026-09-07/tastemap-story-annual-402-light.png)
- [Companion](analytics-story-2026-09-07/tastemap-story-companion-402-light.png)
- [Source](analytics-story-2026-09-07/tastemap-story-source-402-light.png)
- [Installed QA Taste](analytics-story-2026-09-07/tastemap-story-installed-taste.png)

## Design System Compliance / remaining work

Core UI: shared semantic colors, existing module navigation and return ownership,
44-point controls, readable type, wrapping and dark-mode contrast retained.
Food & Dining: shared supplied `FoodLibraryArtwork`, existing report-scoped lawful
Visit images, no emoji food or fabricated photo identities. Canonical template:
one shared five-mode short-home/detail composition, with no new host-specific
React renderer. No default-SwiftUI product styling introduced.

Not claimed complete: geographic basemap composition for city footprints; the
city/Restaurant evidence is retained honestly. Native rollback and legacy Browser
analysis remain two separate migration consumers; this change does not claim their
visual parity or switch route ownership. Existing unused legacy data CSS is
cleanup debt, not another rendered template. Final human visual acceptance and
physical-device acceptance remain separate from test/build success.
