# Editorial posters — implementation checkpoint

## Delivered code

Month, Year, Source, Companion and On This Day now use the shared editorial
renderer at 1080 × 1530. Existing Taste Profile stays 1080 × 1620.
Data-mode short homes and canonical evidence navigation remain intact.
The same report calculators project poster sections; no screenshot figures are
imported as real data. Existing food sheets supply fallback illustration.
Owner photos retain priority when available in the corresponding scope.

Source retains the explicit 最坑推荐来源 section in owner preview. Negative
rankings are not exported. Public sharing recomputes publicly visible records,
anonymizes names, hides spend and notes, and shares the exact preview PNG.
Same-day overview now has a complete-memory poster entry as well as the
single-record entry.

## Verified this checkpoint

- 7 targeted service suites, 115 tests passed.
- Full application/worker TypeScript checks passed in formal staging.
- Editorial browser probe: 5 layouts, 10 owner/share PNGs; no private names or
  notes in external render; first action preview-only; exact PNG sharing;
  rendering does not mutate the report.
- Existing v2 browser probe passed S01–S10, M01–M08, Y01–Y08, D01–D08,
  X01–X03, first-Visit evidence, period/day scoping and Visit handoff.
- Visually inspected all five owner compositions and corrected overlapped
  cuisine values, narrow restaurant names, date alignment and compact lists.
- QA Simulator build succeeded. dist, staged, built and installed public
  resources match byte-for-byte (26 files).
- Installed bundle com.lafayette.tastemap.qa on fixed Simulator
  E4F3EED9-89D8-405C-B4CB-7CA816CE3405 and launched Hybrid rich QA.
- Assets: index-Bce8dVr4.js, index-QWInUqks.css.
- Build log: /tmp/tastemap-editorial-build.log.
- Generated test-fixture images: /tmp/tastemap-editorial-posters.
- Boot screenshot: /tmp/tastemap-editorial-installed-qa.png.

Native UI tests from the earlier checkpoint are not a new poster-specific
acceptance run. Physical-device sharing, accessibility, and pixel-level parity
with the supplied art are NOT claimed complete. No production deployment.

## Design System Compliance

Core UI uses the existing audience control, ModalShell and canonical navigation.
Food & Dining uses scoped Visit evidence and the canonical category resolver;
paper and receipt details are code-native, not new bitmap stock assets.
Canonical poster templates are differentiated from short data-mode homes.
No new SwiftUI default controls or route-owner changes are introduced.

Current compositions use existing food art, not the reference's drawn human
couple. A licensed matching people illustration and handwriting font would
improve visual fidelity, but missing artwork does not fabricate personal facts.
No reliable mood/distance/dual-person rating fields means those claims remain
absent. Missing source-to-untried-restaurant attribution and embedded maps remain
separate known product gaps from the earlier checkpoint.

Worktree is shared and dirty; unrelated edits preserved, no commit or reset.
