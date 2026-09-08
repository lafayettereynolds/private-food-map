# Analytics results-first presentation

## Scope

Latest request: show important conclusions first, fewer default-visible statistics,
and clearly separated blocks. No formula, data ownership, source identity, privacy,
poster renderer, navigation ownership or physical-device installation changes.

The shared `AnalyticsReportDataView` serves all five modes of
`TasteMapAnalyticsPage`, consumed by the integrated Hybrid shell. It now has a
primary conclusion, at most three supported findings, and collapsed complete
analysis/evidence. Supporting sections are independently expandable. Selection
changes reset disclosure through the report identity key. Restaurant actions are
retained inside evidence. The presentation helper respects insufficient confidence,
skips empty/zero-count results and avoids duplicate Restaurant highlights. It uses
existing report order and values, never recalculates rankings or scores.

## Verification

- 47 tests passed across result-priority, shared report and share-privacy suites.
- TypeScript and formal Hybrid release-bundle build passed.
- Real-component Chrome probe: 375/402 widths, light/dark; all five mode layouts
  and empty states; supporting data collapsed; at most three findings; historical
  period retained; selected companion evidence retained; PNG preview/share and
  default private-text exclusion passed.
- DebugQA build 906.19 succeeded, installed only on fixed iPhone 17 Pro simulator
  `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`, bundle `com.lafayette.tastemap.qa`.
- All 18 local resources match dist → staged → built → installed byte-for-byte.
- Actual installed app opened from My → Taste Profile: title, stable module/share
  control, main preference card and separate recent-change card visually inspected.
- Evidence: `/tmp/tastemap-analytics-results-90619.png`,
  `/tmp/tastemap-analytics-data-402-light.png`,
  `/tmp/tastemap-results-{taste,companion,source,monthly,annual}.png`, plus empty
  variants; build log `/tmp/tastemap-analytics-results-build.log`.

## Design System Compliance / boundaries

Core UI uses the shared muted blue-grey palette, readable type, 44px disclosure
targets and consistent card/spacing values in the shared report stylesheet.
Food/Dining evidence remains the original authorized Restaurant image component;
no new ornamental or generated food evidence. Analytics data template uses
results-first progressive disclosure; the poster template is unchanged. No new
SwiftUI defaults or duplicate platform-specific Hybrid page were introduced.

Consumer audit found legacy Browser `ProfileAnalyticsPanels` and Native rollback
analysis screens remain separate consumers from this shared report route. They are
not retired or claimed as aligned by this scoped change. No primary-route switch,
Worker deployment, Release binary update or phone synchronization was performed.
This report does not close other GPS, discovery, photo-security or analytics
data-source migration gates.
