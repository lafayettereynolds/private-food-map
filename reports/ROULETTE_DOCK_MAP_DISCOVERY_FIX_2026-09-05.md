# Roulette candidate dock: Map and Discovery

## Scope and cause

The Map Add CTA and candidate dock occupied overlapping screen rectangles. The Native MapKit even-odd mask XOR-ed those rectangles, re-exposing the map inside their intersection. The shared mask now subtracts every control path; the Add CTA reserves a separate position above the dock. The dock preserves 44-point button targets and scrollable candidate review.

Lafayette additionally requested the dock on Discovery. Browser and Hybrid now display the same session dock on Map/My List and Discovery. Hybrid Discovery adds/removes candidates without navigating away; all five feeds receive the current selected IDs and display the selected action state. Discovery content reserves bottom scrolling space. Only the dock's explicit Start action opens Roulette.

## Consumer inventory

- Browser: `App` → `RouletteCandidateDock`; shared `MyMapBrowsePage` and Discovery scaffold.
- Capacitor: `HybridAppShell` → the same dock; all five `HybridDiscoveryPage` tabs.
- Native MapKit: one `TasteMapHybridMapOverlayView` owns all React-control exclusions, including the dock and its review popover.
- Native rollback: no matching floating candidate-dock implementation in Map; the existing Roulette page remains a separate destination.
- Extensions: no matching map/dock surface.

## Verification and artifact identity

- Branch `feature/hybrid-final-integration`, base `58bd556`, existing dirty worktree plus this scoped patch.
- 91 tests passed across dock, global shell, Map and remaining Hybrid UI contracts; TypeScript checks passed.
- `HybridPhase2AIntegrationTests` passed, including an overlapping-mask geometry and hit-test regression plus restored map visibility after clearing exclusions.
- Formal stage and both built apps: all 16 UI resource files match byte-for-byte. Assets: `index-DBFGKVlr.js`, `index-tltxKze1.css`.
- Simulator: iPhone 17 Pro `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`; `/tmp/tastemap-roulette-review/Build/Products/DebugQA-iphonesimulator/TasteMap.app`; bundle `com.lafayette.tastemap.qa`; `DebugQA` isolated fixture session, no extra launch arguments or environment overrides. Renderer: React Hybrid with Native MapKit map slot.
- Runtime inspection: Discovery 1/10 remains on Discovery with selected action; Map 1/10 preserves candidates with an intact dock and separated Add CTA; expanded review remains opaque over Map; My List retains the same pool; adding another Restaurant from Detail produces Discovery 2/10 with Start enabled. No full draw or manual clear cycle was completed in this checkpoint.
- Private device: exact verified `/tmp/tastemap-avatar-fix-device/Build/Products/DebugPrivatePreview-iphoneos/TasteMap.app`, bundle `com.lafayette.tastemap`, successfully installed on `00008101-001C20AC0200001E`. Automatic launch was rejected because the phone is locked. Physical-device visual acceptance remains pending unlock.

## Design System Compliance

- Core UI: shared dock, minimum 44-point actions, positive spacing and safe-area placement.
- Food & Dining visuals: existing Restaurant renderer and data unchanged.
- Canonical templates: shared Map/My List and Discovery session controls; three bottom tabs preserved.
- New duplicate components: 0. New default-SwiftUI UI variants: 0.
- Remaining verification gaps: physical-device visual check, manual clear/full-draw cycle, and separate Browser interactive smoke. Simulator runtime evidence is not represented as real-account data or physical-device acceptance.
