# Trending compact media — Simulator 906.31

Scope: remove the Trending full-width image exception; preserve image provenance,
Restaurant identity, trend evidence, filters, actions and navigation. No phone install.

## Consumer inventory

- Formal React Browser/Capacitor: `HybridDiscoveryPage` default and selected-city
  results both use `RecommendationCard` → `TasteMapActivityCardFrame`.
- Shared frame: removed the sole `wideMedia` prop/consumer and corresponding wide
  CSS. Every single image uses existing activity size/radius tokens; albums unchanged.
- Legacy Browser `CommunityPage`: already consumes the compact shared frame.
- Native rollback and Discovery previews: `DiscoveryRestaurantCard` already uses
  square `TasteMapDesignTokens.Layout.socialFeedMediaWidth`; no wide exception.
- No additional matching extension renderer found. No route/runtime owner changed.

## Verification

- 44 tests passed in HybridRemainingUIContract and TasteMapActivityMedia.
- Actual React/browser geometry probe passed For You, Same Taste, Latest and
  Trending at 375/402 in light/dark: equal compact square dimensions/left edges,
  no wide variant, retained evidence/actions and working image navigation.
- Formal stage and built app each match all 18 resources byte-for-byte.
- Xcode DebugQA build succeeded; version 906.31 installed and launched on fixed
  iPhone 17 Pro Simulator E4F3EED9-89D8-405C-B4CB-7CA816CE3405.
- Runtime: React Hybrid (`hybridDevelopment`), isolated `visualQA` fixture,
  no launch overrides. Map → Discovery → For You → Trending inspected.
- Trending now shows 春日泰味 7 as a left-aligned small square, not a banner.
  Both trend-evidence tags and Share/three Restaurant actions remain visible.
- Screenshot: `/tmp/tastemap-90631-trending-compact.png`.
- Built app: `/tmp/tastemap-analytics-results-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Source baseline: feature/hybrid-final-integration, HEAD
  58bd556b8382734aeae1f08937ba649563682140, with preserved working-tree changes.

## Design System Compliance

Core UI: PASS, reused compact sizing/radius and existing controls.
Food & Dining: PASS, unchanged lawful image/fallback selection.
Canonical Activity Template: PASS for scoped image correction.
Remaining conflicting wide-image consumers: 0. Added duplicate components: 0.
Default-SwiftUI regressions introduced: 0; Native rollback unchanged.
Other pre-existing migration/production-data/visual acceptance gaps are not closed
by this narrow fix. Physical-device installation was explicitly out of scope.
