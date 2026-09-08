# Footprint cards and public footer — QA 906.25

Status: source, focused tests, Browser visual probe, formal build/install PASS.
Final installed owner/public-footer visual and navigation acceptance PENDING:
CUA clicks/drags did not reliably operate Simulator; user was asked to open the
owner footprint region. Do not promote build or installed hashes into visual PASS.

## Scope / changes

- Public Native handoff SocialPublicProfileView now shows authorized actual
  PublicContentCard records after Lists, replacing the old dining-evidence summary.
  Existing count/map entries, list cards, following/fans, author visibility,
  content pagination and Restaurant actions remain. One contentSection task owns
  inline/drill-in data; scope/revision guards reject stale responses. Profile
  access revocation also invalidates in-flight content replies.
- QA 906.23 showed actual public inline cards at runtime, but the user correctly
  rejected their old footer and pointed out owner Profile was still a timeline.
  QA 906.23 is NOT acceptance of either issue.
- Owner React Profile and full Footprints now reuse TasteMapActivityCardFrame,
  Visit score badges, and TasteMapActivityMedia. All valid owner Visits, including
  zero/unrated, and active Wants remain in timestamp order. Exact Visit/dish
  images retain ID-only sources and deduplicate, then owner marker photo/category
  fallback. No private record acquires a fabricated public engagement count.
  Existing Restaurant navigation remains the working detail entry. Latest correction:
  the shared small Store icon sits beside the address; no visible 查看餐厅 text
  or separate bottom row. Its accessible name and callback remain. Shared frame
  omits empty footers. Both owner preview/full-page use the same implementation.
- Native rollback owner rows remove the timeline rail/outer card and use compact
  square media and shared Visit badge. Full Native rollback parity is not claimed.
- Native public cards use left bare Like/Comment/Share and exactly three right
  outlined 40-point controls: record plus, bookmark, and the React two-dice glyph.
  Header More owns food-list/report/block. Record context menu also preserves
  list access for Native Discovery consumers. Minimum native touch target is 44.
- Preserved current route ownership. Installed root remains React Hybrid +
  Native MapKit with the established Native social handoff, not a rollback launch.

## Inventory and boundaries

- React owner preview and full Footprints: one shared record renderer.
- Capacitor owner Profile: same React component; no separate page.
- Native public Social/Community/Discovery entry points: same SocialPublicProfileView
  and PublicContentCard / DiscoveryRestaurantQuickActions.
- Native private Footprints route: existing scoped snapshot and photo consumer.
- Legacy Browser public Profile's separate historical composition remains migration
  debt; this report does not certify public Browser parity or whole Social acceptance.
- No extension/export capability added. No photo/Visit deletion, real user mutation,
  production Worker deployment or physical-iPhone install. Treasure chest stays paused.

## Verification

- 42 tests PASS: PublicProfileFootprintsContract, HybridRemainingUIContract,
  tasteFootprint service; TypeScript PASS.
- hybrid/scripts/check-owner-footprint-cards.mjs PASS: actual React renderer at
  375/402, light/dark, 1/2/4/5/6/7 images (24 album cases), square sizes <=180,
  no row/timeline, complete notes, private label, 0 vs nil, real callback execution,
  address-line Store SVG, no visible 查看餐厅 text and no empty footer.
  Uses isolated local fixture photos, not production records. 300 owner records
  remain directly rendered in the regression contract.
- Browser screenshot /tmp/tastemap-owner-footprints-402-light.png inspected. Fixed
  the initial text-action wrapping defect; latest image confirms the small address
  icon replaces that entire text action and bottom row.
- QA 906.25 Xcode build PASS; /tmp/tastemap-footprints-90625-build.log.
- 18 resources match dist → formal staging → built → installed byte-for-byte.
- Built /tmp/tastemap-analytics-results-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app
- Installed /Users/lafayette/Library/Developer/CoreSimulator/Devices/E4F3EED9-89D8-405C-B4CB-7CA816CE3405/data/Containers/Bundle/Application/CC8F881F-E03B-43D9-8EDB-D22B33AC4E29/TasteMap.app
- Device E4F3EED9-89D8-405C-B4CB-7CA816CE3405, com.lafayette.tastemap.qa,
  isolated rich QA default, launch without route arguments; Map startup observed.
- Branch feature/hybrid-final-integration, base HEAD
  58bd556b8382734aeae1f08937ba649563682140; dirty user work preserved.

## Design System Compliance

Core: shared Activity frame, spacing, rating, album and native action tokens.
Food/Dining: existing photo loaders/actual owner photos and category visual;
no invented public source or expanded export rights. Canonical template: old
summary/timeline removed on touched current routes; public footer updated.
No new page renderer or default-SwiftUI primary button introduced. Remaining gaps:
installed final visual/return-path acceptance and legacy Browser public/Native
rollback full parity. These are NOT a global completion claim.
