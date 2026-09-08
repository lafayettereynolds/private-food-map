# On This Day year navigation — 2026-09-08

The D01 button navigated to D03, but OnThisDayExplorer had no D03 content branch. It fell through to the home-like content, including another link to D03. Repeated taps appended indistinguishable entries to the reading history, making the destination/back behavior appear stuck.

Correction: D03 now renders newest-first calendar-year groups from the existing authorized exact-day Visit result. One year/one unrated Visit remains meaningful; nearby/current-year records are not introduced. Each memory opens D02 and returns to its year list. D08 remains reachable. D03 has no link to itself. Shared reading navigation ignores identical destinations, including repeated taps before React commits, while preserving distinct entity/lens/record/date navigation.

Consumer inventory: Browser and Capacitor share OnThisDayExplorer. The Native rollback OnThisDayAnalysisView already renders report.groups directly and has no matching D03 self-link. The shared reading guard also serves PeriodMemoryExplorer and RecommendationSourceExplorer; route identity tests preserve their distinct lenses and record sets. No route ownership or data storage changed.

Verification:

- 10 focused tests passed across OnThisDayExplorer, AnalysisReadingRoute, onThisDayMemory and analyticsMemoryShare.
- Isolated Browser real-component checks covered multi-year, one-year/one-record, detail → year → home navigation. The probe is local and ignored under `.private/on-this-day-navigation/`; its simulated data is not in the formal bundle.
- Formal staging plus final QA/Release built-app checks passed: 26 matching Web resources. Release purity passed for 50 app files, with no test/development/credential leak.
- Installed `DebugQA-iphonesimulator/TasteMap.app` from `/tmp/tastemap-directory-build/Build/Products/`, bundle `com.lafayette.tastemap.qa`, on fixed iPhone 17 Pro Simulator `E4F3EED9-89D8-405C-B4CB-7CA816CE3405` (iOS 26.5). Ordinary QA launch; React Hybrid renderer with its existing isolated rich dataset. Source is dirty `feature/hybrid-final-integration`, base `58bd556`.
- The screenshot-matching `月白甜品 2` entry now opens `2025 年 · 1 条记录`; its D02 detail opens, then each single Back returns to D03 and D01. This is QA fixture verification, not production-account evidence. No backend deployment or record edit was performed.
- A preliminary Private Preview launch showed auth-required, and is explicitly not acceptance evidence for the reported populated screen. The correct QA app was subsequently updated and verified as above.

Design System Compliance: Core PASS for existing ModalShell/ReadingLink/back controls, with no new size or color scale. Food/Dining imagery unchanged. Canonical D01–D08 reading template retained; no new duplicate page/renderer or SwiftUI layout changes. Scope is this navigation defect, not full analytics/poster visual acceptance.
