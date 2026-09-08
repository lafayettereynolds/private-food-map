# For You compact media — QA 906.22

Latest request: For You Restaurant photo must use the same left-aligned compact
square as the other activity modules. Preserve identity, signal semantics,
reasons, actions, photo provenance and image/detail navigation.

## Change and consumer inventory

- Shared `TasteMapActivityCardFrame` defaults to compact media, independently of
  recommendation/activity meaning. Hybrid For You no longer inherits a full-width
  hero simply because its card is a recommendation.
- Existing Trending wide presentation remains explicitly selected; this request
  does not silently resize that separate mode.
- Browser Community For You already consumed the compact shared default; Native
  rollback Discovery already uses `socialFeedMediaWidth` square. No duplicate
  image loader, new photo source or per-page size scale was introduced.
- Included previous pending corrections: badge text inside artwork coordinates,
  shorter/quieter ribbon tails, no shadow, 62×70 shared badge size; feed methodology
  sentence removed while badge explanation remains available.

## Verification

- Recommendation/shared Hybrid/global product contract: 104 tests PASS.
- TypeScript and formal stage PASS; 18 signed local resources match dist → stage
  → built → installed byte-for-byte.
- Actual `HybridDiscoveryPage` Browser probe: For You, Similar Taste and Latest
  have equal single-image widths and left edges at 375/402, light/dark. Loaded
  images are square and <=180px; badge, reasons, 3 Restaurant actions and image
  navigation retained. Local images are isolated test material, not real records.
- Badge probe additionally checks complete text bounds lie strictly within the
  inner circle for 0/88/99/100/pending and explanation remains tappable.
- QA 906.22 built with scheme TasteMap QA / DebugQA; fixed iPhone 17 Pro iOS 26.5
  simulator E4F3EED9-89D8-405C-B4CB-7CA816CE3405, com.lafayette.tastemap.qa.
- Built: /tmp/tastemap-analytics-results-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app
- Installed: /Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/760F1CAF-7368-4379-B325-B6F7A59BA303/TasteMap.app
- React Hybrid For You inspected in the actual installed app: compact food photo,
  aligned percentage/label, full reason, absent methodology sentence, unchanged
  name/address/filter/navigation and action groups. Isolated rich QA data only.
- Screenshot: /tmp/tastemap-for-you-compact-90622.png.
- Browser regression: hybrid/scripts/check-recommendation-compact-media.mjs.

## Design System Compliance

Core: reused shared photo sizing/radius tokens and card frame. Food/Dining:
unchanged canonical visual descriptors and photo fallback. Canonical template:
latest For You override applied without replacing its recommendation semantics.
No new per-platform Hybrid page or default SwiftUI visual introduced. Native
rollback image primitive already matched; Native badge compiles but separate
rollback visual acceptance remains open. This scoped pass does not close the
footprint, poster, illustration, multiple-reason entitlement or other backlog.
No physical device install or Worker deployment performed; treasure chest paused.
