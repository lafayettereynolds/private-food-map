# Same Taste comments — 2026-09-05

## Scope and diagnosis

The supplied card is the isolated rich-preview `春日泰味 7` / `林夏` item with two comments. Its Native producer emitted `demo-similar-visit-0`, while the Debug interaction validator requires `demo-visit-`. The validator rejected comments (and the shared like/add-comment path) before loading data. The production server comment endpoint was not the cause established by this reproduction.

Before-change runtime reproduction: `/tmp/tastemap-similar-comments-before.xcresult`. The new UI test opened the comment panel, but failed waiting for the first existing comment. This reproduced the screenshot against the pre-fix implementation.

## Correction and consumer inventory

| Consumer | Correction / boundary |
| --- | --- |
| Native Hybrid rich-preview producer | Same Taste uses `demo-visit-similar-N`, inside the existing validator namespace and distinct from feed `demo-visit-N`. No validation bypass was added. |
| Browser debug producer | Same namespace; its comment collection remains keyed by the actual Visit ID and backs the displayed count. |
| Shared React Hybrid Discovery | Following, Same Taste, Latest and any evidence-backed recommendation use the same comment loading function. Explicit loading/content/empty/error states; visible retry; stale responses after close or another open are discarded. |
| Comment entry | Reading comments no longer immediately opens the keyboard. Tapping the text field still opens it. The shared comment input is at least 16 px to avoid WebKit focus auto-zoom; closing blurs it and restores the captured card scroll position. Retry preserves the draft text. |
| Native rollback community comments | Load failure is separate from an empty conversation; retained comments and retry remain available. Existing shared `TasteMapEmptyState` is reused. |
| Browser legacy local Community comment UI | Local draft conversation, not this remote comment service or fixture ID validator; no changes to its separate local persistence semantics. It inherits the same safe input size through the shared comment class. |
| Extensions / posters / previews | No remote comment viewer in extensions or posters. QA preview data is explicitly isolated; no test comment is sent to a real user or production endpoint. |

The personal account, backend/Worker, schema, comment permissions, route ownership, and physical phone installation are unchanged. This task does not repair the separately diagnosed root `data.changed` bootstrap flash or MapKit overlap-order issue.

## Verification

- TypeScript: **66 tests passed** in `CommunityCommentList`, Browser debug fixture, Platform, and global Hybrid product contract suites.
- Native: **12 tests passed** in `HybridPhase2AIntegrationTests`, including `similarTasteFixtureInteractionsUseTheCommunityVisitNamespace`. Result: `/tmp/tastemap-similar-comments-native.xcresult`.
- Isolated Simulator: **UI test passed** for existing comments, sending, closing/reopening, remaining on Same Taste, and preventing that new comment from appearing in a different Following/Latest Visit. Result: `/tmp/tastemap-similar-comments-after.xcresult`.
- Fixed QA Simulator: **full UI test passed** after the scroll-return correction. Initial extended runs revealed that input focus/keyboard dismissal left the underlying first-card action at y = -28 pt, not merely a transition delay. The corrected input size and explicit card-position restoration passed reading, sending, reopening and cross-Visit isolation on the fixed QA app.
- `pnpm run hybrid:stage:formal`: signed local Release-resource check passed; **16 files byte-for-byte** from dist to staged resources.
- QA build and installed-app resource checks: **16 files byte-for-byte**; final JavaScript `index-D-ygRkE7.js`, CSS `index-BMQgiR8w.css`.
- A temporary source-test `node:fs` import failed the Browser typecheck; the source test now uses the repository's raw-source import convention, and the CSS source assertion lives in the Node-side global contract suite. Final typecheck/staging succeeds. Acceptance uses only the corrected staged artifact, not the stale intermediate package.
- A direct `DebugQA` test build lacked a Swift version for the test target. No project configuration was changed. Fixed-QA verification instead uses the already-compiled UI runner with an explicit QA target `.app` in a temporary `/tmp` test plan.

## Renderer and artifact identity

- Source: `feature/hybrid-final-integration`, base `58bd556`, dirty working tree; only scoped edits were made.
- Build: `/tmp/tastemap-map-anchor-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Fixed Simulator: `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`, iPhone 17 Pro / iOS 26.5.
- Bundle: `com.lafayette.tastemap.qa`, DebugQA companion; private `com.lafayette.tastemap` was not installed over.
- Runtime: `HYBRID_DEVELOPMENT`, React Hybrid Discovery / Same Taste / comment modal; rich isolated fixture. Test launch passes `--tastemap-hybrid-development`, Light mode, `TASTEMAP_VISUAL_QA_MODE=rich`.
- The fixed-QA test log explicitly identifies `Open com.lafayette.tastemap.qa` and `Launch com.lafayette.tastemap.qa`.
- Physical device / real-account server comment smoke: **not run**, and no phone was updated.

## Design System Compliance

- Core UI: existing modal, comment rows, action class, and Native empty/error component reused; no new measurement scale.
- Food & Dining: Restaurant image descriptors and card imagery unchanged.
- Canonical templates: Discovery header, five tabs, card anatomy, footer and bottom navigation unchanged; loading failure no longer impersonates an empty conversation.
- Duplicate components introduced: **0**. One shared remote-comment state renderer replaces the inline list in the shared Discovery page; Native keeps its required rollback implementation.
- Default-SwiftUI visual regressions introduced: **0**; error action uses the existing shared component.
- Remaining gaps: real-account/physical-device network smoke and Native rollback visual failure injection are not claimed as verified. General bootstrap flashing and map z-order are separate unresolved issues.

## Final fixed-QA rerun

**PASS**: `/tmp/tastemap-similar-comments-qa-acceptance.xcresult`, `testHybridSimilarTasteCommentsLoadAndRemainVisitScoped` on `com.lafayette.tastemap.qa`.

Verified installed application:
`/Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/4B514F19-1A7F-4C1C-888A-785AB5AC563F/TasteMap.app`.

Final QA screenshots inspected:
- Existing two comments: `/tmp/tastemap-comments-final-qa/F1238086-6F63-49F9-B885-61248D2DD003.png`.
- Reopened after sending: `/tmp/tastemap-comments-final-qa/D8DA99A4-76D4-4C1A-8764-48AA3DB0FDC7.png`.

The built and installed executable also match byte-for-byte. The QA companion was reopened to Discovery after the test; the private app and physical phone remain unchanged.
