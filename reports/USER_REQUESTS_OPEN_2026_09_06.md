# User-request completion ledger — 2026-09-06

This is a work ledger, not a blanket acceptance report. Source, tests, installed
Simulator and physical-device delivery are separate states. Never infer completion
of earlier requests from a later feature's build or from this file's existence.

## Latest Simulator update — QA 906.25

Owner record cards and corrected public activity footer are built and installed;
owner 查看餐厅 text is now a small Store icon beside the address, with no empty footer.
42 focused tests and the 24-case Browser photo-layout probe PASS. Final installed
owner/public-footer visual and return-path verification remains PENDING because
Simulator automation did not reliably operate. See FOOTPRINT_CARDS_2026_09_06.md.
QA 906.23's old public footer was explicitly rejected; do not count it as accepted.
Other open work stays open. No physical-iPhone update.

## Historical Simulator update — QA 906.22

For You compact square photo, badge text/sizing refinement and deletion of the
inline methodology sentence are now installed and visually checked on the same
fixed Simulator. See RECOMMENDATION_COMPACT_MEDIA_2026_09_06.md. The QA 906.21
section below is historical evidence, not the latest installed version. Other
open items remain open; the owner footprint timeline screenshot is specifically
NOT accepted as the requested record-card presentation.

## Verified in this integration turn

| Request | Source / tests | Installed runtime | Physical iPhone |
| --- | --- | --- | --- |
| Cold launch defaults to Map | Shared React and Native Hybrid defaults corrected; route/back/global suite 60 PASS, agent route/map/global 61 PASS | QA 906.21 fixed Simulator: launch with no route override opens Map | Not updated |
| For You match icon uses original ribbon-medal style | Shared React and Native Core gold rosette/ribbons, real percent and score palette; shared recommendation/global suites 103 PASS | QA 906.21 For You inspected; dashed circle absent | Not updated |
| Complete recommendation reason text | Shared React and Native Core no 12-grapheme excerpt or modal overlay; 1/3-reason tests, long Chinese/English, 375/402 light/dark PASS | QA 906.21 complete supplied reason visible | Not updated |

## Still open — do not silently drop or report complete

- **Number of recommendation reasons:** renderer displays all supplied reasons,
  but the rich QA producer currently supplies only one For You reason. Separately
  audit production source/Free/Premium explanation gates; do not invent reasons
  or expand permissions merely to fill a card. Browser CommunityPage still has
  its existing core-reason/expanded-analysis policy.
- **Restaurant avatar refresh:** fixes landed for Native preferredEmoji and
  per-record map snapshot invalidation; 61 JS / 1 lightweight Swift test passed.
  New iOS integration cases and actual save-detail-map round trip remain pending.
  Legacy Native detail/roulette consumers were not fully closed by this fix.
- **New York Da Andrea search:** fallback relevance and iOS 26 district fixes
  landed; 23 JS tests passed. Real full-name search and iOS integration tests not
  accepted yet. See NEW_YORK_RESTAURANT_SEARCH_2026_09_06.md.
- **Poster illustration series / layout:** incomplete. Generated illustrations
  are candidates; full asset bundle, data-driven editorial integration, fixed
  layout/preview/export/Native consumer validation remain pending.
- **Analytics depth, historical fusion and results-first presentation:** prior
  reports document partial completion; do not equate results-first QA 906.19 with
  complete legacy/new-method fusion or poster acceptance.
- **Public Profile changes:** taste footprints, visited/wanted counts with drill-in,
  map entry, follow state beside fans and direct food-list cards need an explicit
  consolidated acceptance audit against the user's latest instructions.
- **Earlier remaining UI / behavior:** edit-profile Settings-only entry, action
  icon balance, 2/4/5/6/7-photo same-taste/latest albums, removed Trending header
  groups, average-score precision and saved-editor return stack require their
  existing evidence plus current-artifact verification, not a blanket claim.
- **GPS / Nearby:** previous physical-device work is separate; current integration
  has not revalidated device GPS or delivered these UI changes to the phone.
- **Physical-device sync:** not performed for QA 906.19 / 906.21 UI changes.
- **Treasure chest:** explicitly PAUSED. Keep default-off isolation; do not resume
  or include the candidate in ordinary device behavior.

## Artifact evidence for QA 906.21

- Branch: feature/hybrid-final-integration; base HEAD 58bd556b8382734aeae1f08937ba649563682140, dirty integration worktree preserved.
- Built: /tmp/tastemap-analytics-results-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app
- Simulator: E4F3EED9-89D8-405C-B4CB-7CA816CE3405, iPhone 17 Pro iOS 26.5.
- Bundle: com.lafayette.tastemap.qa, version 906.21; React Hybrid + Native MapKit;
  isolated rich QA data, no startup route argument, no real account modifications.
- Installed: /Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/02D7FC9A-05D9-4307-A338-E000F074D9A0/TasteMap.app
- dist → staged → built → installed: all 18 formal resources byte-identical.
- Screenshot: /tmp/tastemap-recommendation-medal-90621.png.
- Browser probe: /tmp/tastemap-recommendation-medal-check.mjs;
  /tmp/tastemap-medal-{375,402}-{light,dark}.png. Probe data is isolated, not real evidence.

## Design System Compliance

Shared Core recommendation primitives/tokens own the change; real Restaurant
image resolution, concrete Visit ratings, filters, actions and route ownership
are preserved. Gold artwork is a decorative signal frame, not a new award or
food-data claim. No page-local Hybrid variant or default SwiftUI control added.
Native counterpart compiles; complete Native visual/interaction parity remains
an open gate. The broader backlog is NOT accepted by this scoped validation.
