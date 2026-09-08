# Restaurant content artwork / avatar isolation — 906.32

## Scope and result

Latest user direction: all five Discovery content surfaces and Restaurant Detail
main images use actual viewer-authorized Visit/dish photography, otherwise the
best matching supplied-library illustration. Explicit avatar uploads are not
automatic content candidates. Avatar editing and avatar consumers stay separate.

Simulator acceptance passed; no physical device update, account mutation,
private database access, or production Worker deployment was performed.

## Consumer inventory

| Consumer | Canonical implementation | Validation |
| --- | --- | --- |
| Hybrid/Browser shared Discovery: Following, For You, Same Taste, Latest, Trending | HybridRestaurantContentImage → HybridRestaurantImage content appearance → FoodLibraryArtwork | All five mounted at 375/430 px, light/dark; all five inspected in Simulator |
| Browser standalone Community five tabs | RestaurantContentImage, Visit/dish refs only | Focused source/renderer tests, TypeScript |
| Hybrid/Browser Restaurant Detail and shared summary | RestaurantContentImage + dedicated content DTO fields | Mounted lifecycle, Simulator coffee fallback and recorded-photo detail |
| Native rollback For You/Trending/remote Detail | DiscoveryRestaurantImage + FoodLibraryArtwork | Native compile and focused source/render-policy tests |
| Native rollback Following/Latest/Same Taste | PublicContentActivityMedia + FoodLibraryArtwork | Native compile and focused source/render-policy tests |
| Native local Detail | RestaurantDetailImageResolver actual photos + authenticated UGC + FoodLibraryArtwork | Native detail and photo-recording tests |
| Map/List/roulette avatars, avatar editor | Existing avatar components; explicit selection retained, automatic actual-photo candidates | Map/List and editor inspected; isolation tests |
| Previews / extensions / accessibility | Shared renderer descendants; no separate in-scope content renderer found | Source inventory; library label explicitly says illustration, not actual photo |

Native rollback runtime was not substituted for the Hybrid acceptance surface.
Its compile/tests do not constitute a separate full rollback visual acceptance.

## Implementation and assets

- Additive `contentImage/contentImageResolution` on Native and TypeScript Restaurant
  and content DTOs. The avatar `image` is not repurposed.
- Seven original sheets, 41 catalog entries, name → tags → normalized-category
  matching. Original files are copied unchanged. Runtime crop windows show a
  single item; no generative replacements. Provenance and hashes are in
  `docs/FOOD_LIBRARY_PROVENANCE.md`.
- Discovery compact square dimensions and Detail composition are retained.
- Source removal/unreadability falls back to the next eligible photo or library.
- Worker public pools filter actual `visit/dish` types. Native accepts typed
  responses and conservatively handles old responses with Visit identity.

## Artifact identity

- Branch: `feature/hybrid-final-integration`; base HEAD
  `58bd556b8382734aeae1f08937ba649563682140`, with existing uncommitted work preserved.
- Scheme/configuration: `TasteMap QA` / `DebugQA`; build `906.32`.
- Built app: `/tmp/tastemap-analytics-results-qa/Build/Products/DebugQA-iphonesimulator/TasteMap.app`.
- Simulator: iPhone 17 Pro / iOS 26.5,
  `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`.
- Bundle: `com.lafayette.tastemap.qa`; no additional launch arguments or environment.
- Runtime: compile-selected `hybridDevelopment`, default QA `.rich` in-memory
  fixtures; React Hybrid page rendering with Native MapKit on Map.
- `hybrid:stage:formal` passed; all **26 files** in dist, formal staged resources
  and built app matched byte-for-byte before installation and after inspection.
- Exact app installed and launched with `simctl`, without uninstalling.

## Verification

- React focused agent suite: 68 tests passed; parent asset/content/avatar check:
  28 tests in four files passed (overlapping counts, not additive).
- Actual browser lifecycle: 375/430 × light/dark, all five tabs and Detail;
  empty → authorized photo → removed → unreadable → supplied artwork;
  custom avatar unchanged. Test uses isolated descriptors/assets, not user uploads.
- Original-material renderer probe: coffee, steak, noodles, Thai, sushi,
  croissant, Korean and yakitori visually inspected; clip boundaries corrected.
- Native: 41 tests in four suites plus 31 tests in two detail/photo-recording
  suites passed, **72 total**. Build succeeded.
- Worker: 69 focused tests and Worker TypeScript passed locally.
- Simulator: coffee/no-photo Detail shows supplied coffee artwork; its editor
  still independently offers photo/emoji. For You and Trending show matched
  compact artwork. Following/Latest/Same Taste preserve fixture activity photos.
  Wildfire Yakitori 1 Detail uses its Visit photo above the matching User Photos
  item rather than the yakitori illustration. Ratings, business information,
  user-photo section and original actions remain visible. Map/List avatars remain
  separate. No real-account upload/delete scenario was performed.

Evidence:
- `/tmp/tastemap-90632-content-browser.log`
- `/tmp/tastemap-90632-content-tests.log`
- `/tmp/tastemap-90632-native-tests.log`
- `/tmp/tastemap-90632-native-detail-tests.log`
- `/tmp/tastemap-90632-build.log`
- `/tmp/tastemap-food-library-render.png`
- `/tmp/tastemap-90632-for-you.png`
- `/tmp/tastemap-90632-detail-library.png`
- `/tmp/tastemap-90632-detail-photo.png`

## Design System Compliance and remaining boundaries

- Core: existing card geometry, typography, controls and 44-point editor retained.
- Food: one shared supplied catalog and content-artwork primitive per platform;
  no new page-local art style, no illustration labelled as a real visit.
- Template: no route/runtime ownership change; no removal of downstream Detail
  sections or actions; compact Discovery media remains compact.
- Duplicate patterns: all same-semantic shipping content consumers moved to shared
  content rendering; avatar rendering intentionally remains separate.
- Native regression: focused suites and compile passed; full rollback visual
  sweep was not performed or claimed.
- Three broader existing Product Contract assertions remain failing: old Map
  count string, old Native Discovery chrome check, and whole-file Trash2 ban
  conflicting with approved deletion entry. They were not weakened for this task.
- Worker source changes are **not deployed**. Existing city/album deployment HOLD
  remains; cross-device production public-pool acceptance requires a separately
  scoped deployment. Do not ship the entire dirty Worker as part of this UI change.
- Remaining supplied poster assets / Analytics poster work are outside this result.
- Browser historical non-empty explicit emoji preference remains preserved because
  its model has no separate explicit-choice flag.
