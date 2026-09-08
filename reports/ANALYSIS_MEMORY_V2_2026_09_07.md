# Analysis / Memories v2 — implementation checkpoint

## Scope and reference authority

User-supplied ZIP: TasteMap_分析回忆补全_含最坑推荐来源_v2.zip.
Shared data flows implement S/M/Y/D and X reading destinations, with explicit
S03 最坑推荐来源, first-experience evidence, scoped calendars/comparisons,
exact prior-year memories and working cover/privacy sheets.
The later image clarification restores the Taste poster to the full 2:3
editorial composition without reverting the new short data homes.
The subsequent five images also require richer Month/Year/Source/Day posters:
those four compositions are still PENDING; current memory cards are interim.

## Implemented boundaries

- Source scoring reuses formal sample/baseline policy, stable source identity
  and first-rated Restaurant records; subsequent visits never replace evidence.
- Month/year share the same report calculator and period/record predicates.
- On This Day excludes deleted/orphan/current-year records, preserves multiple
  prior-year Visits, and labels nearby-date exploration separately.
- External posters recompute public-only data, then remove private fields.
  Cover/privacy updates regenerate the reviewed blob; sharing uses that blob.
- Browser and Capacitor use the same new reading components. No database writes,
  remote deployment, route promotion or physical-device installation.

## Verification

- Eight targeted service suites: 127 tests passed.
- Added restored editorial 1080 × 1620 composition regression: share suite
  rerun, 21 tests passed (included in the suite count, not additive).
- Browser v2 probe passed S/M/Y/D/X route checks, scoped raw evidence,
  public-safe image generation, privacy toggles and canonical Visit handoff.
- Updated F01–F24 browser probe passed, including S03 integration and 2:3 PNG.
- Final native UI run: 2 passed / 0 failed. Taste question/source/back/filter
  and monthly calendar/day/comparison paths tested on fixed Simulator.
  Result: /tmp/tastemap-memory-v2-final-20260907.xcresult.
- Earlier failed native attempts were test harness issues: startup readiness,
  combined accessible source label, and WKWebView exposes aria-pressed calendar
  buttons as Switch elements. They are not counted as passes.
- Earlier global product suite has two unrelated Discovery source-text
  assertion failures; global suite is NOT reported green.
- Formal build: typecheck, signed-local bundle purity and stage verification.
  26 files match dist/stage/built/installed byte-for-byte.
  Assets: index-CM_-qmRl.js, index-QWInUqks.css.

## Artifact / renderer identity

Source: feature/hybrid-final-integration, baseline 58bd556, dirty worktree;
unrelated existing changes preserved, no commit.
Built: /tmp/tastemap-profile-status-derived/Build/Products/DebugQA-iphonesimulator/TasteMap.app.
Installed QA bundle: com.lafayette.tastemap.qa.
Fixed Simulator: E4F3EED9-89D8-405C-B4CB-7CA816CE3405.
Launch: --tastemap-hybrid-development -AppleInterfaceStyle Light.
Environment: TASTEMAP_VISUAL_QA_MODE=rich.
QA boot screenshot: /tmp/tastemap-v2-installed-qa.png (Hybrid root with Native
MapKit surface, fixture data; not the user's personal analysis).
Native tests use Debug app with the same staged React bundle; QA installed
artifact byte identity and Hybrid boot separately verified.

## Design System Compliance

- Core UI: shared headers/back, ModalShell bottom sheets, existing token colors,
  controls and minimum touch targets; no new navigation stack outside report
  reading history and canonical typed Restaurant/Visit destinations.
- Food & Dining: existing FoodLibraryArtwork and owner-scoped Visit evidence,
  no imported sample people/numbers/photos as real data, no new bitmap assets.
- Canonical templates: short data homes plus themed detail, real calendars and
  records; Taste restored editorial poster. Other four new rich-poster images
  remain a composition task, not visual-reference PASS.
- Remaining duplicates: old Profile OnThisDay detail implementation remains
  unreachable from the normal new day entry; Native rollback remains separate.
- Default SwiftUI regression: none introduced; new product UI is shared React.
- Gaps: embedded MapKit F13/Y05, saved/untried source attribution S08, full
  four-poster editorial migration, dedicated Best Companion poster reference,
  Native rollback parity, physical-device sharing/accessibility coverage.
- D02 screenshot /tmp/tastemap-v2-D02.png captured before fallback art was
  confirmed visible; do not use that blank image frame as visual acceptance.

## Optional user materials

Layered reference files, separately licensed handwriting fonts, people/paper/
tape assets, and a Best Companion poster reference would improve fidelity.
They are not prerequisites for continuing layout with existing assets.
Missing mood/attribution fields must remain honest, not inferred as sample facts.
