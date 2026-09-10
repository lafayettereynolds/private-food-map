# Taste Map Product Design Rules

This document is the canonical, long-lived product and visual contract for Taste Map. A page is not parity-complete merely because a related feature exists or a SwiftUI screen opens. All UI/UX work must read this file before implementation and keep it synchronized when Lafayette confirms a new durable decision.

## 2026-09-06 — Reaffirmed recommendation badge and complete evidence

### Later same-day footprint and footer correction

Owner `我的 → 味觉足迹` renders actual record cards directly after Insights,
not a compact Restaurant-name timeline. Preserve all valid Visits (including zero
and unrated records) and active Want saves in real timestamp order; never filter
private history through Discovery eligibility. Reuse the shared activity frame,
Visit score badge and 1/2/4/5/6/7-photo album layout; owner history has no fabricated
public author/counters. Preserve private visibility, original notes and photo IDs.
Restaurant detail entry is the shared small Store icon beside the address, not
a visible `查看餐厅` text CTA or a standalone bottom row. Retain its accessible
name and working detail callback; omit an empty activity footer when no actions exist.

The current public-profile Native handoff retains its compact visited/wanted/map
entrances and independent Lists, then displays `TA 的味觉足迹` from that owner's
viewer-authorized content endpoint. Replace the obsolete `口味与餐厅证据` overview
in that position; renaming a representative-Restaurant summary is insufficient.
Reuse `PublicContentCard` for inline and drill-in records, with one scope/load
owner and stale-response guards. No account/permission/cache/export expansion.

Public activity footers align with the approved Discovery grouping: bare
Like/Comment/Share on the left and exactly three outlined circular Restaurant
actions (plus, bookmark, two-dice) on the right. The record plus is not a filled
primary disc. Secondary list/report/block actions belong to the activity header's
More menu, not a fourth/fifth Restaurant-footer slot. Native rollback quick
actions retain list access through the record action's context menu as well.
Use the shared 40-point visible Restaurant circle, 18-point glyph and 44-point
hit target. Do not remove existing functions to achieve three visible actions.

Do Not Regress: test the actual owner dashboard (not just another user's profile),
complete 300-record reachability, zero vs nil, long notes, ID-only photos, all
album layouts and the installed public footer. Browser legacy public-profile
composition remains a separate migration gap, not implied accepted by Native
handoff correction.

**Later same-day refinement:** For You uses the same left-aligned compact square
Restaurant image and shared activity photo size/radius tokens as Latest and Same
Taste. Do not infer a full-width hero from the recommendation card variant.
`TasteMapActivityCardFrame` uses compact media for every Discovery single image.
**2026-09-07 Lafayette correction:** Trending also uses the same left-aligned
compact square; its former wide-media exception is superseded and removed from
the shared frame and CSS. Default and selected-city Trending share this rule.
Browser Community and Native rollback already use compact single images.
Do Not Regress: verify Trending beside For You/Similar Taste/Latest at 375/402
in light/dark, retain evidence and image navigation, and forbid a wide override.
No photo provenance,
multi-photo album, identity, evidence, score, action or navigation change is
authorized by this size correction. The requested methodology sentence is absent
from the feed; the badge retains its explanation dialog. Badge text uses the
artwork's own coordinates inside the inner ring (including 100% and pending),
with shortened ribbon tails and no outer shadow.

Lafayette explicitly reaffirmed the original gold ribbon/rosette reference after
seeing the old dashed circle still installed. The recommendation signal now uses
a gold rosette with navy/gold ribbon tails and the real percentage inside, not a
dashed or solid plain circle. Its inner value/ring retain the shared score palette
(`percent / 10`); the gold frame is decoration, not a public award, ranking or new
probability claim. Match/probability labels, validation gates, missing-evidence
state and explanation action remain intact. Shared React and Native Core signal
primitives own this presentation; ordinary Visit rating circles are unaffected.

Complete supplied recommendation reasons are visible directly on the card.
Every authorized reason appears once as a text-sized, wrapping light tag; long
Chinese/Latin strings wrap instead of truncating. No 12-grapheme excerpt, ellipsis,
line clamp or invisible modal-opening overlay remains. Do not invent additional
reasons when the source provides only one, or broaden server/Premium permissions.
This supersedes the earlier same-day dashed/solid signal-circle and abbreviated
reason-tag clauses below. The paused treasure-chest map markers are unrelated.

Do Not Regress: test 0/88/100/pending, both signal modes, 1/3 long reasons,
375/402 widths and light/dark; verify the actual installed formal bundle.

## 2026-09-06 — Shared activity photo albums

Lafayette requires Same Taste to use the same compact activity-photo presentation as Latest, not the full-width For You recommendation hero. Following shares this activity template. Keep author identity, concrete Visit rating, evidence, interaction order and restaurant actions unchanged. One image is a left-aligned square; two images are equal squares on one row; four images form a 2×2 grid; three or five-plus images use three columns. Initial display is limited to nine real images with an explicit expansion for larger retained albums. Never stretch images, repeat one image to fill a grid, or remove stored photos to satisfy a presentation limit. Two photos are the primary free-user acceptance case; 1/2/4/5/6/7 must each be checked in Same Taste and Latest.

React Browser and Hybrid own this composition in `TasteMapActivityMedia` inside `TasteMapActivityCardFrame`; sizing, spacing and radius belong to the shared activity tokens. Native rollback reuses `PublicContentActivityMedia`/`PublicContentMediaPresentation` and the existing read-only album viewer. A non-empty activity album contains only authorized photos of that exact Visit and author, preserving order and ID-only photos. Only an absent album falls back through the canonical Restaurant visual policy. System recommendations and Trends retain their separate image semantics. No public/friends image gains export permission by entering a grid.

Do not regress: Same Taste must not select the recommendation-hero card variant; no three/four-photo transport truncation; no page-local gallery scale; no clearing old albums during unrelated edits; no friends material persisted as public to work around a missing in-memory feed. The new Worker album response is **deployment HOLD** until Hybrid's friends-only session presentation is connected: mixed public/friends albums correctly upgrade cache scope and cannot safely be treated as public persisted cards. Local layout acceptance is not production-feed or real-device acceptance.

## Source of Truth

### 2026-09-09 — Independent personal recommendation filters

Lafayette explicitly requires two independent concepts: **预计喜欢度** (the
system's estimated personal rating) and **口味匹配度** (the existing matching
index). The existing historical-rating estimator is reused with a 0–10 display
unit; it is not an actual submitted rating and must never be relabelled as a
calibrated probability. The existing estimator's weighting and output floor are
retained. Missing owner history remains unavailable/积累中, never public rating
or the match percentage as a replacement. Calibrated liking probability remains
a separate unproduced future channel, subject to its existing attestation gates.

For You's quick filters, full sheet, sorting and selected-condition labels use
these independent values. Remove public-score/reviewer-count controls and public
rating sort from the shared current Discovery UI. Retain Restaurant Detail's
public rating facts and individual activity rating semantics; old API fields may
remain for backwards compatibility, but cannot remain invisible active conditions
in the new UI. Personal thresholds are applied before server pagination, bound
to the accepted owner/city/query and not carried into non-personal feed queries.
Browser's legacy local feed only filters its actually obtained scope; it is not
proof of complete server-city pagination.

Reuse Core FilterBar/FilterSelect/ModalShell and the Discovery card template.
Forecast methodology is progressive disclosure, not persistent calculation copy.
Food imagery and existing match badge artwork are unchanged. Do Not Regress:
independent thresholds, high public score failing a personal threshold, missing
evidence, owner isolation, reset, tab return, source/staged/built/runtime identity.
This supersedes earlier public-score quick-filter requirements, not recommendation
eligibility or default ranking. Source implementation does not imply deployed
Development support or physical-device acceptance.

When sources differ, use this priority order:

1. Lafayette's latest explicit design or product override.
2. This document.
3. Confirmed decisions in `docs/TASTEMAP_LEGACY_FUSION_DECISIONS.md`.
4. Confirmed current-only product capabilities and approved newer designs.
5. Confirmed production Web or previously approved historical/TestFlight design evidence.
6. Legacy source implementation evidence.
7. Current iOS visual implementation when it has not yet received human product acceptance.

Before changing layout, establish the Web feature semantics, data source, entry point, states, permissions, and return path. Fix a semantic migration bug before restoring its presentation. The current iOS implementation may supply working code, but it does not become the layout source of truth merely because it is native SwiftUI.

### Active rules, supersession, and historical evidence

This document is the only active long-term Product/UI contract. Task files, screenshots, audit reports, closure reports, and old test expectations remain useful evidence, but they never override this document. When historical text conflicts with an active rule, preserve it as history and treat it as `SUPERSEDED`; do not implement both variants.

The following historical statements are explicitly `SUPERSEDED`:

| Historical source or pattern | Superseded statement | Active rule |
| --- | --- | --- |
| Earlier 2026-09-05 count-cluster and proximity-stack revisions | city markers replaced by quantity numbers; overlapping circles within 50 m share a stack | latest explicit correction: no quantity numbers or numeric badges on markers; city Restaurants naturally overlap at their own coordinates, only strict coordinate matches share a stack/list, wider-area grouping shows a real high-priority Restaurant image |
| `reports/TASK_09_ACCESSIBILITY_DARK_MODE_LOCALE.md`, `reports/TASK_10_PERFORMANCE_MEMORY_LARGE_DATASET.md`, the initial Legacy audit wording, and the 2026-09-04 free-slot override | random jitter, spiderfy, or mandatory collision-free marker separation | circle anchors remain fixed; city natural overlap, wider-area Restaurant-image representatives and exact-coordinate stacks preserve every original Restaurant and coordinate without artificial free slots |
| Earlier Map/List parity reports | `适合你`, a separate segmented row, or a floating Map/List switch | `去过 / 想吃 / 推荐` plus the centered `我的地图 / 我的列表` title-and-icon switch |
| Legacy raw emoji marker/customizer references | raw emoji as formal Restaurant or Food/Dining artwork | real Restaurant image first; otherwise the formal `FoodDiningVisualLibrary` fallback |
| Source-specific Restaurant Detail reports or implementations | separate Map/Discover/Friend/Recommendation detail bodies | one `RestaurantDetailView` / `RestaurantDetailStandardBody` |
| Earlier Analytics dashboard acceptance | ordinary card dashboard or page screenshot treated as the approved analysis/poster experience | poster-like infographic pages and dedicated native share posters |
| Earlier Activity-card projections | Restaurant aggregate rating used when an Activity rating is absent | the author's specific Visit/Activity rating; an unrated Visit is excluded from public Discovery evidence rather than receiving a substitute score |
| `reports/TasteMap_DESIGN_SYSTEM_COMPLIANCE.md` | infrastructure PASS interpreted as complete visual Product Acceptance | PASS is limited to its audited infrastructure baseline; current page/product rules and human visual acceptance remain controlling |

### Legacy Fusion Governance

Legacy comparison uses exactly these decisions:

- `RESTORE`: the historical behavior was correct and is still missing;
- `KEEP CURRENT`: the current capability or architecture is newer and must remain;
- `FUSE`: restore historical product structure or semantics while preserving current capabilities;
- `RETIRE`: the historical behavior is explicitly obsolete;
- `NEEDS LAFAYETTE APPROVAL`: evidence cannot safely decide the product outcome.

Legacy evidence has no authority to delete or downgrade a current feature, data field, interaction, Premium capability, Social capability, sharing capability, Analytics capability, or current architecture. Any removal of a current formal capability is automatically `NEEDS LAFAYETTE APPROVAL` and must stop before implementation.

## Mandatory Design Workflow

Every UI/UX task follows this order:

1. Read this document in full.
2. Identify the affected Core UI components, Food & Dining visuals, and Canonical Page Template.
3. Confirm product semantics and data behavior before changing presentation.
4. Search the entire app for the same component or pattern.
5. Extend or consolidate the shared implementation; do not create a third variant.
6. Apply the correction to every affected screen inside the authorized scope.
7. Validate the reference, state coverage, accessibility, and shared-component reuse.
8. When the decision is durable and new, update this document in the same task.

A reported defect is evidence of a possible design-system defect, not permission to patch only the visible page. Filter, tab, top-bar, image, action-row, activity-card, rating, empty-state, and Restaurant Detail changes always require a global usage audit.

### Global semantic correction and runtime-proof iron rule

Every correction starts with a repository-wide inventory of the same semantic pattern. The visible screenshot is evidence of one affected surface, never the authorized limit of the correction. Browser React, Capacitor, Native/SwiftUI rollback UI, extensions, previews, accessibility text, and other shipping consumers must either use the same canonical semantic/shared component or be explicitly documented as a different meaning. A remaining matching surface with the old behavior means the correction is not complete.

Acceptance also follows the actual shipping path. Source code, snapshots, tests, generated `dist`, and build success are intermediate evidence only. For the formal iOS Hybrid app, the required chain is:

```text
shared React source
    → dist
    → ios/TasteMap/HybridRuntimeResources/public
    → built TasteMap.app/public
    → installed Simulator / real-device runtime
```

Each arrow must be verified. Use `pnpm run hybrid:stage:formal`, require the byte-for-byte formal-stage verifier to pass, verify the built `.app` resources, then visually inspect the affected installed surfaces. `hybrid:sync:*` targets the internal Capacitor shell and cannot stand in for formal Xcode-resource staging. A mismatch at any layer is `FAIL / STALE ARTIFACT`, even when source tests pass. This rule prevents a source-level correction from being reported while Lafayette is still running an older bundled UI.

## Taste Map Design System Architecture

Every page is built in this direction:

```text
Canonical Page Template
        ↓
Core UI Components + Food & Dining Visual Components
        ↓
SwiftUI rendering and interaction
```

Never start with default SwiftUI controls, improvise a page, and add brand color afterward. The three layers below are mandatory and have separate responsibilities.

### Layer 1 — Core UI System

The Core UI System defines the product's structural interface language:

- typography, font size/weight, and text hierarchy;
- spacing, padding, radius, border, shadow, and dividers;
- cards, buttons, icon buttons, CTAs, inputs, and search;
- filter chips, tabs, top bars, section headers, and list rows;
- empty, loading, error, permission, and authentication states;
- avatar, Restaurant image containers, rating components, sheets/modals, and safe-area behavior.

The target is modern, compact, high-information-density, and clearly layered. Use large cards, large CTAs, default segmented controls, and oversized rounded containers sparingly and only when the canonical template calls for them. Avoid the visual signature of a default SwiftUI sample app.

`TasteMapCoreTheme` uses cool white, low-saturation blue-grey, restrained borders and shadows, and native interaction behavior. Brand slate blue is primarily a structural/control color for selected state, focus, active tabs, buttons, and chips; it must not tint every icon, image placeholder, Food visual, or decoration.

SwiftUI remains the implementation framework, not the visual design system. A default `Picker`, `NavigationTitle`, Card-like container, SF Symbol, tint, or control style is not automatically an approved final design.

#### Core design tokens

Stable visual values belong in shared tokens rather than arbitrary page-local magic numbers. Maintain a coherent scale for:

- typography;
- spacing and standard section spacing;
- radius and border width;
- control, chip, and tab height;
- icon, avatar, and Restaurant image sizes/ratios;
- shadows and safe-area offsets.

Page-specific values are allowed only when a canonical composition needs them and the reason is clear.

The code authority is `TasteMapDesignTokens`. It owns the formal `Spacing`, `Typography`, `Radius`, `Border`, `Control`, `Icon`, `Avatar`, `ImageRatio`, `Shadow`, and `Layout` groups. Shared components consume those values directly. `TasteMapCoreTheme` remains the color/elevation theme and exposes only compatibility aliases for older feature code while it is migrated.

The following product invariants are tokens, not page-local choices:

- 44-point minimum interactive target;
- compact 34-point visible filter pill inside that target;
- 44-point primary-tab row with a 2-point selected indicator;
- one page inset and standard section-spacing scale;
- one card/control radius scale and one standard border width;
- shared icon, avatar, Restaurant image ratio, and social-poster ratio scales;
- shared semantic typography for filters, tabs, section headers, activity ratings, and empty states.

A page may retain a special composition measurement—for example a hero height or approved map top offset—when the Canonical Page Template requires it. It must not define another general chip, tab, card, avatar, icon, image-ratio, or touch-target scale.

### Layer 2 — Food & Dining Visual System

This is the brand layer that makes Taste Map recognizably about food, restaurants, dining memories, and social meals. Use the shared `FoodDiningVisualLibrary` and `FoodDiningVisualIcon` (or their formal successor), never page-specific unrelated art styles.

The vocabulary may include real food (for example sushi, hotpot, barbecue, noodles, burgers, steak, dumplings, bread, desserts, fruit, and vegetables), drinks (coffee, tea, milk tea, and other beverages), and dining objects (chopsticks, cutlery, bowls, plates, cups, menus, receipts, bills, napkins, takeaway bags, containers, and tables).

Two modes remain strictly separate:

- `decorative`: adds character without claiming the artwork represents user data;
- `dataLinked`: is selected only from a real cuisine, spend, companion, time, Restaurant, or other supported value.

Never invent data meaning to justify attractive artwork. Formal product art does not use system emoji. Use restrained natural food, coffee, produce, paper, and tableware colors; do not uniformly dye Food/Dining artwork brand blue. Keep line, corner, proportion, shadow, and light/dark behavior consistent, and use stable seeds so decorative choices do not jump on rerender.

The approved historical Premium hamburger is a separately locked asset and is not replaced by the Food & Dining library.

#### Restaurant Visual Source System

Taste Map separates Restaurant avatars from content imagery. Avatars preserve an explicit owner-selected image/food emoji; automatic avatar candidates are actual Visit/dish photography only, otherwise the established related food emoji. Content imagery uses eligible actual photography, otherwise a matching illustration from the user-supplied local food library. Merchant-photo availability is not a prerequisite for Search, Nearby, Map, Detail, or Discovery.

The normalized `FoodCategoryVisualID` vocabulary is intentionally small and stable: `chinese`, `japaneseKorean`, `western`, `hotpotBBQ`, `noodles`, `cafeBakery`, `drinksDessert`, `seafood`, `fastFood`, `vegetarianLight`, and `other`. Resolution uses existing Restaurant cuisine/category, provider POI category, tags, name, and address hints in that order of available evidence. The mapping is deterministic; it never uses random/system emoji or a network-downloaded icon. React and Native may render platform-appropriate local vectors, but the ID, palette family, food meaning, and fallback decision are shared.

Image source priority is surface-aware:

| Surface semantics | Formal priority |
| --- | --- |
| Personal Map | current-owner marker / Restaurant / Visit photo → Food Category Visual |
| Search / Nearby | matched current-owner photo → eligible public Taste Map UGC → Food Category Visual |
| Restaurant Detail main image | current-owner actual Visit/dish photo → eligible public actual photography → matching supplied-library illustration, without changing the canonical Detail IA |
| Following / Same Taste / Latest content image | viewer-visible activity/Visit photo → eligible public actual Restaurant photography → matching supplied-library illustration |
| For You content image | current-owner actual photo → eligible public actual Restaurant photography → matching supplied-library illustration |
| Trending content image | current-owner actual photo → eligible public actual Restaurant photography → matching supplied-library illustration |

The main-image rules above apply to all five Discovery tabs and Restaurant Detail in Browser, Hybrid and Native fallback surfaces. A dedicated Restaurant-avatar upload (`restaurantMarker`) must never enter the automatic/shared content candidate pool, even when public. Explicit avatar references remain owner preferences, not evidence of an actual dining photo. Preserve the avatar edit action on Detail while rendering its main image independently; never enlarge the circular avatar into the hero or use its emoji as the content-image fallback.

`FoodLibraryArtwork` is the shared content fallback, using the original user-supplied sheets and `public/food-library/catalog.json` on React and Native. Select deterministically by specific Restaurant name, then cuisine/tags, then normalized category. Display only the matched item, not the whole sheet. Identify it as an illustration, never as Restaurant/user photography; do not invent an actual dish, Visit or uploader. Preserve Discovery's approved compact square media geometry. Photo arrival, deletion, loss of permission and unreadability must update the candidate chain and restore the library fallback without changing an explicit avatar preference. See `docs/FOOD_LIBRARY_PROVENANCE.md` for originals and hashes.

For You remains a Taste Map algorithmic recommendation and Trending remains a system trend. Selecting a public photo never promotes its uploader into a recommender, trend source, avatar, byline, or explanation. Following, Same Taste, and Latest may associate the photo with a person only when the card is backed by that real, viewer-visible Visit/activity.

`RestaurantUGCImagePool` is the canonical eligibility pool and `RestaurantVisualResolution`/the typed image descriptor is the canonical surface decision. A public-pool record must be public at Photo, attached Visit (when present), and Profile boundaries; must match the Restaurant identity; must be readable; and must not be deleted, binary-deleted, actioned by moderation, account-deleted, or blocked relative to the viewer. Friends/limited photos may be used only by an authorized viewer on their corresponding activity surface. Current owners may see their own private photo on owner-scoped surfaces. Marker preference, explicit order, recency, and stable photo ID provide deterministic selection.

The renderer consumes one typed descriptor—`ownerPhoto`, `activityPhoto`, `publicUGC`, or `foodCategoryVisual`—and may own crop, ratio, radius, loading, and transition presentation only. It must not re-run source priority. A page-local URL resolver, provider branch, random fallback, or `if photoURL else placeholder` is migration debt, not a new standard.

Public UGC permission here authorizes in-app display only. Other-user UGC has `exportAllowed = false` unless a separate explicit grant exists and must not silently enter share posters, Analytics posters, downloads, Backup export, or external-share assets. Current-owner export continues under the established owner export policy. Provider identities may remain in Restaurant identity data, but these surfaces have no external merchant-photo dependency.

### Layer 3 — Canonical Page Templates

Templates define information architecture, section order, control and image placement, interaction hierarchy, content density, and component composition. Core components are not permission to freely rearrange an already approved product page.

#### Root App Shell Contract

- Ordinary cold launch starts at Map in Browser and the Native Hybrid coordinator.
  Explicit deep links, share destinations and isolated QA routes remain authoritative;
  foreground resume and back navigation preserve the active session, not force Map.
  Session restoration alone must not redirect a fresh Map launch to Profile.
- The formal bottom navigation is exactly `地图 / 发现 / 我的`, in that order, with exactly three items.
- `Add Restaurant` is a routable product surface, but route availability never implies bottom-navigation membership.
- Every full-screen secondary iOS surface opened from a previous product page must expose exactly one icon-only left-arrow action at the upper left with a 44-point hit target and the accessibility label `返回上一页`. Bottom navigation is not a substitute for restoring the immediately previous page. Modal sheets have one explicit exit owned by the destination, never a second host-added back action.
- Profile editing (full profile, display name, and homepage visibility, from Profile or Settings) uses only an icon-only upper-left back action plus the existing Save action. Do not render `取消`, a close X, or another host arrow alongside that back action. Returning discards the local draft; only Save writes changes. Saving locks the exit and interactive dismissal. Shared Native and Browser primitives retain a real 44-point hit area; automatic Native toolbar styling must not shrink it. Native handoffs that already own their navigation/exit must not be wrapped in another navigation toolbar; missing-data/authorization states still need a reachable exit. Existing completion and entitlement-cleanup actions retain their own semantics.
- The secondary-page back action must remain visible and tappable below the status-bar safe area throughout both outer-page and nested-content scrolling, including Restaurant visit history. Use the shared compact persistent navigation row; do not pin the Restaurant hero, duplicate a card close action, or require users to scroll to the top before returning. Its background must prevent scrolled content from showing through the return/status region. Browser document and overlay scrollers obey the same persistence rule; an existing overlay close action must remain reachable above nested navigation.
- An owner-editable Restaurant exposes a 44-point avatar-edit action at the upper-left of its image area. The editor supports a single owner photo through the native iOS photo picker or one complete Unicode emoji grapheme (including skin-tone, flag and ZWJ combinations); the saved Restaurant avatar is the single source used by avatar consumers in map, lists and roulette. The Detail main image is separate and follows the actual-photo / supplied-library content rule above.
- The single formal Add Restaurant entry is the Map-owned floating `添加餐厅` primary CTA. It must not be duplicated as a fourth bottom tab, page-wide tab, or competing primary action.
- Shared Browser and Capacitor rendering does not make a shell topology correct by itself. Any root navigation change must pass the exact Product Contract before cross-platform and visual parity can pass.
- Product Contract, One React UI, Current Capability Preservation, Browser ↔ Capacitor parity, Lafayette Reference parity, Function/Semantic, and Negative Contract are independent gates; no gate substitutes for another.
- A capability still implemented in Native remains visible in Hybrid through a typed Native handoff. `readOnly`, migration status, or a missing React write implementation must not silently remove Record Visit, Edit Visit, Photo/Camera, List mutation, Premium purchase/restore, Backup/Import, Sync, Account, or Share entries.
- React renders ownership-sensitive actions only from Native capability DTOs. It must not infer `canEdit`, `canDelete`, `canRecord`, `canAddToList`, report or block permission from a user-ID comparison or UI state.

#### 1. My Map / My List Template

- One React UI governs the shared product chrome, not the map engine: Browser uses its formal Web provider; iOS Hybrid embeds the established Native MapKit / `MKMapView` surface in the persistent shell.
- React owns Header, title switch, scopes, FilterBar, Add Restaurant CTA, selected-card/detail navigation, and bottom navigation. Native MapKit owns tiles, pan/pinch, viewport, Restaurant annotations, selection, CLLocation/user-avatar annotation, and map performance.
- The React ↔ MapKit contract is minimal and typed: filtered presentation markers/state flow Native; viewport and selected Restaurant flow back. JavaScript receives neither credentials nor SwiftData/write authority.
- The persistent Native MapKit layer is visible only when the accepted route is Hybrid Map **and** the current React presentation requests it. Leaving Map, entering List, or opening a React blocking overlay hides it immediately; late bridge replies/geometry must never reveal it over Discovery, Profile, Settings, or another route. Keep the same map instance and viewport. Do Not Regress: repeated Map ↔ Discovery acceptance must assert absence of the Native layer and usable feed content, not merely the Discovery header.
- AMap Web key or `securityJsCode` availability is never an iOS Map or Release blocker. A static Web fallback is never accepted as the iOS map.

- top breathing space;
- centered `我的地图` / `我的列表` plus the adjacent clickable view-switch icon as one group;
- `去过 / 想吃 / 推荐` using the shared primary tab bar;
- each scope uses one semantic line icon plus its text (`去过` = the canonical checkmark inside a circle, `想吃` = bookmark, `推荐` = star); the three items share icon size, baseline, spacing, selected treatment, and a minimum 44-point hit target;
- each scope also shows its owner-scoped unique Restaurant count as a compact adjacent badge. `去过 / 想吃` count Restaurants rather than Visits; `推荐` counts only the real recommendation projection. These scope totals stay stable during pan, zoom, search, and filtering so the tabs describe the user's overall collection instead of the current viewport;
- Map `推荐` is a geographic projection of the exact canonical `发现 → 为你推荐` snapshot, not a second recommendation query. The two surfaces share eligibility, case-insensitive Restaurant-ID de-duplication, rank order, snapshot version, and total count. Explicit Map filters may narrow the retained snapshot and the camera naturally determines what is onscreen; panning does not create a new recommendation query, introduce a Restaurant absent from that snapshot, or derive a separate top-N list from the owner's Visits;
- scope selection feedback is committed immediately and never waits for data, images, a Native bridge response, or map work;
- shared compact horizontal FilterBar; every closed select pill sizes to its currently visible label plus the shared disclosure indicator, never to the longest hidden option, so short labels such as `城市 / 评分 / 消费` remain visually balanced without dead space;
- Map and List share the active scope's query/filter/sort state. `去过 / 想吃 / 推荐` each own an independent query bank: first entry is clear, return restores that scope's filters/search/sort, and clearing one scope never clears another;
- switching scope preserves the mounted map identity, center, zoom, bounds, selected viewport and Map/List state; it must not recreate the map or trigger camera fitting merely because the scope changed;
- content may update asynchronously from an owner-scoped, versioned, bounded presentation snapshot; Native/SwiftData remains the source of truth, stale responses are rejected, and the cache is invalidated by owner/data changes;
- markers reconcile by stable Restaurant ID and reuse unchanged marker/image identity rather than performing a full teardown; image loading never blocks selected-state feedback and cached Restaurant images do not reload solely because the scope changes or the map pans;
- interactive Map data is one full filtered result capped at 300, not a succession of viewport-bound result replacements. Native MapKit may virtualize offscreen views, but panning never changes the underlying annotation identities;
- Native MapKit visited Restaurant markers continuously scale their unselected inner circle between 24 and 28 points as the user pinches. Including the unchanged 2-point white separation ring on each side, the visible outer circle is 28–32 points: the whole marker, not merely its center image, should remain within roughly twice an ordinary nearby POI icon's visual size. Native selection adds only 2–4 points to the inner diameter while preserving the center. Browser uses shared tokens of 32 px overall, 36 px selected, identically on mobile and desktop, without continuous diameter scaling. Both retain the rating/dashed ring and neutral hairline, with a weaker restrained shadow;
- Restaurant markers do not carry repetitive visited/want/recommended status badges; the selected scope already communicates that state, so the Restaurant image/rating ring remains visually clean;
- every individual Restaurant circle is center-anchored to its exact stored/provider coordinate. Native uses a fixed `44 × 44pt` annotation/hit frame and changes only its centered inner visual during zoom or selection; resizing the root frame or bottom-anchoring a circle must not create drift;
- city/street scale (`≤0.8°` latitude span) shows each distinct Restaurant coordinate as its own image marker, with natural overlap and no proximity hiding. Only strict latitude/longitude matches may share a stack/list; its members stay accessible through honest `此处` wording, never an inferred mall identity. Markers never show quantity numbers, count circles or numeric stack badges;
- above `0.8°`, wider-area grouping progressively increases its collision radius to the full value at `2.4°`. Each group preserves every member ID and coordinate and shows the highest-priority real member's Restaurant image at that member's actual coordinate. Tap zooms toward members; exact-coordinate stacks open the complete real member list. These are viewport-scale rules, not administrative-boundary detection;
- high scores lead the overlap order: personal-marker priority is `selected compositing layer → rating → visit count → stable Restaurant ID`; recommendation rank may break equal-rating ties but never places a lower-rated Restaurant over a higher-rated one. Selection is a temporary foreground override, not a different regional representative. Pan preserves grouping and priority; zoom splits and aggregates reversibly around immutable anchors;
- no collision offsets, free-slot displacement, bottom-anchoring of Restaurant circles, spiderfy, fabricated counts, decorative substitute-food aggregates, random jitter, or viewport-origin-dependent placement;
- Add Restaurant CTA in its approved non-overlapping position.
- On installed iOS Hybrid, the Native MapKit canvas extends to the physical bottom edge behind the one shared bottom navigation. The navigation owns one full-width rectangular exclusion in the Native overlay and must never be treated as an 18-point rounded floating control. Map-specific reserved strips, partial-height cutouts, visible seams, exposed map wedges, or a second background layer above/below navigation are forbidden. Floating Map controls remain positioned above the navigation and safe area.

#### 2. Discovery Template

- centered `发现` title;
- equal primary tabs `关注 / 为你推荐 / 同味之选 / 最新 / 趋势`;
- every Discovery tab exposes `搜索城市` using the shared city-search control. Users can type a city absent from loaded results; suggestions are optional shortcuts, not a whitelist. The selected city survives tab switches, while explicit city reset returns to the existing default discovery content. A selected city must load its authorized server query, never merely filter the locally loaded first batch. New selections clear old-city results immediately; empty results, errors/retry and continuation are distinct. City queries must not overwrite My Map's canonical recommendation snapshot or GPS state;
- the shared FilterBar and icon semantics;
- the standard Activity Card;
- the author's Visit/Activity rating semantics, never a substituted aggregate Restaurant rating;
- explicit loading, content, empty/insufficient-sample, authentication, and error states.

#### 3. Restaurant Detail Template

- Cover; city/state; Restaurant name;
- three compact icon actions for record/add, Want to Go, and roulette/list context as approved;
- address; reference price; phone; opening hours; directions;
- rating reference and four circular ratings for mine/all/friends/similar taste;
- user photos; my visit overview; visit history; dishes; detailed ratings; downstream modules.

`RestaurantDetailView` and `RestaurantDetailStandardBody` remain the only body. Entry source may change navigation, dismissal, analytics, and permissions, never this composition.

#### 4. Profile Dashboard Template

- compact avatar/name/joined/Premium header;
- following and followers;
- `去过 / 想去 / 总消费` using their formal calculation semantics;
- Owner statistics use the shared compact `ProfileSummary` rhythm: 8-point identity-to-statistics gap, 4-point vertical statistic inset, at least 44-point button height, and 10-point gap to the paired primary entrances. Preserve all three values, amount typography, wider amount column and section order; do not remove data or shrink text to reduce whitespace;
- paired `今天吃什么 / 我的口味档案`;
- one Memories group for `本月回顾 / 年度回顾 / 那年今日`;
- independent Lists section;
- paired `最佳饭搭子 / 谁最会种草` Insights;
- data and settings as a secondary later section.

#### 5. Activity Card Template

Discovery, Community, Latest, Trending, and similar activity surfaces share author/avatar/time/visibility, Restaurant image/name/address/context, the author's Activity rating when eligible, social actions, Restaurant actions, and separate sharing. These actions retain the approved grouping and visual weights instead of becoming one wall of identical pills. On ordinary rated-Visit Activity cards, the concrete Visit rating is displayed as a circular badge on the right of the Restaurant identity row; its number and border color come from that same Visit rating through the shared score-color policy.

The `Following` feed, Profile following metric, and Profile following people list are three projections of one owner-scoped relationship graph. Every visible author in `Discovery → Following` must be represented by the same active Follow and cached social profile used by the Profile count and list. Demo/QA fixtures follow this rule as strictly as production: a card-local `isFollowing` flag, a standalone counter, or a feed-only person is not a valid substitute for a relationship record.

The frozen Legacy-base card topology is semantic, not merely stylistic. Recommendation cards are ordered `Restaurant identity + recommendation tag → public Restaurant rating/sample + compact recommender/Visit context → horizontal Restaurant image → independent recommendation-reason/evidence block → social actions on the left + circular Restaurant actions on the right`. Ordinary Activity variants prepend the author/time/visibility row, keep the Restaurant identity before the image, and replace the recommendation block with the activity note when present. `关注 / 为你推荐 / 同味之选 / 最新 / 趋势` use this one shared card frame and only show or hide modules when the content semantics require it. Public Restaurant rating/sample and the author's specific Visit rating remain separate values; neither may substitute for the other.

Public Discovery uses qualified evidence rather than mirroring the complete Visit ledger. The minimum qualified Visit score is `7.5/10` (inclusive). A Visit below that threshold, including an unrated Visit, remains a valid record on My Map, the owner's Profile, Restaurant history, backups, and visit-count analytics, but it must not appear as an individual card or recommendation source in `关注`, `最新`, or `同味之选`; a `为你推荐` placement that is backed by a concrete user Visit follows the same rule. A system-level `为你推荐` card may exist without a concrete Visit when it has other qualified aggregate/personal evidence. `趋势` is the exception: all visibility-authorized Visits, regardless of score, contribute to recent unique-visitor counts, while only rated Visits contribute to rating aggregates. Trend cards remain Restaurant-level aggregates and never render an unrated Visit as a score. All product copy and visible filters express scores on the 10-point scale; the legacy 5-point Visit field is an internal compatibility detail only.

#### 6. Add Restaurant Template

Formal flow: Search, Nearby, external Share ingestion, and one Manual Add card for places absent from map providers. A selected result first shows the standard Restaurant Detail foundation, then offers Want to Go or Record Visit. Manual link paste is not promoted to a primary in-app section; parsing remains available to the Share Extension.

Browser and Capacitor consume one shared Restaurant-acquisition presentation system for the header, capability rows, Search/City fields, Nearby states, candidates, and Manual Add expansion. Search, Nearby, Share, and Manual Add are four expressions of one acquisition hierarchy—not four unrelated form/card dialects. On iOS/WKWebView every editable text control keeps a computed font size of at least `16px`; do not disable user zoom to conceal WebKit focus auto-zoom. A static city scope uses a city/building semantic icon, never a GPS/target icon. Loading, available, unavailable, denied, reduced-accuracy, and error states preserve the compact Nearby geometry and do not turn the section into a page-sized empty panel.

Successful precise-location acquisition does not render a separate `当前位置已更新`, precision, or GPS-sorting confirmation strip. The nearby candidates and their distances are the success feedback. Loading, permission denial, reduced accuracy, unavailable/error, retry, and honest no-result states remain visible because they require user understanding or action.

The Search/City form uses one compact trailing search action beside the city field. Because search is a familiar system action, its visible control is an icon-only rounded button with a real `44 × 44pt` hit target and the accessible name `搜索餐厅`; it is not a wide filled text CTA competing with the fields. Browser, Capacitor, and the Native rollback surface follow this same hierarchy and state styling.

#### 7. Roulette Template

The selected unique candidate pool, image/name chips, wheel segments, and result are the same data. Unfilled segments say `+ 添加更多餐厅`; do not duplicate Restaurants or present placeholders as real candidates. Random selection is uniform unless Lafayette explicitly approves weighting.

Candidate management always exposes both `搜索我的餐厅` and `添加自定义餐厅` with one explicit `添加` action. A custom name becomes a clearly identified local temporary candidate in the same unique pool, chip list, wheel, and result; it does not create or impersonate a saved Restaurant, does not acquire a fabricated image or detail page, and remains subject to the same duplicate-name and ten-candidate limits. Browser and Capacitor use this one shared React implementation. A control that creates a formal Restaurant record is a different action and must not be mislabeled as this temporary Roulette candidate input.

#### 8. Analytics / Poster Template

Taste Profile, Best Companion, Recommendation Source, Monthly, and Annual belong to one Analysis design family: warm/off-white paper, central Food Hero, infographic composition, connecting callouts, Restaurant imagery, food/dining storytelling, receipt/tape restraint, branded poster footer, and QR. Their layouts may vary with data semantics, but must not regress to ordinary card dashboards. Every report exposes exactly two peer modules, `数据 / 画报`. `数据` shows and shares a readable real-data summary; `画报` previews and shares the independently rendered image. Switching modules never changes the underlying report snapshot or opens a sibling analysis type.

Each Profile Analysis entry opens as a dedicated report on iOS. The page title is the selected report name (`我的口味档案`, `最佳饭搭子`, `谁最会种草`, `本月回顾`, or `年度回顾`), never the generic `数据分析`; sibling-report tabs are not shown inside that destination. The share action exports only the report currently opened from Profile.

The approved Taste Profile is a fixed 2:3 editorial infographic, not a generic mobile dashboard or a simplified 9:16 card. Its page and 1080 × 1620 share renderer keep the same module order: title/period, radial cuisine profile, overview, Top 3, taste preferences, recent insights, consumption distribution, price ranges, city footprint, companions, and dining times. Every value comes from the current user's records; cuisines, taste tags, and scene/environment tags remain separate, and all visible ratings use the 10-point scale. The other Analysis types keep their own semantics and 9:16 poster compositions.

## Theme Boundaries

- **2026-09-06 continuous page canvas:** the top status-bar safe area and the visible page header/canvas must share the active page's semantic background, with no default gray strip above a white Profile or Add Restaurant page. The shared Hybrid shell derives its canvas from its active `data-route`, never from the mere presence of a retained hidden page; HTML/body use that same token. Profile uses `--color-surface`, Map/Discovery/activity chrome uses the shared opaque `--tm-browse-chrome-background`, and Add uses `--tm-acquisition-surface`. Other pages retain their existing canvas; this is not permission to repaint every card or change page geometry. Browser and Capacitor share the CSS; Native rollback retains its existing safe-area-aware page backgrounds. **Do Not Regress:** verify actual top/content pixels, light/dark tokens, safe-area geometry, hidden-route isolation, and Profile → Settings → back and tab round trips. Do not cover the seam with an extra strip or force a reload/recreate of the page.
- `TasteMapCoreTheme` implements the Layer 1 Core App system.
- `TasteMapAnalysisTheme` implements the Layer 3 Analytics/Poster template with stronger Layer 2 Food/Dining storytelling.
- Analysis styling must not leak into Map, Settings, Restaurant Detail, or other Core App surfaces.
- The installed iOS Hybrid shell behaves like an App surface, not a selectable webpage: ordinary labels, cards, filters, buttons, images, and map chrome suppress text selection, browser context menus, and link-preview callouts. Editable inputs, textareas, and explicit content-editable regions retain the native selection, Copy, and Paste tools. This boundary is scoped to the installed Hybrid shell and does not remove normal selection from the public Browser product.

## Icon Semantics

- **2026-09-07 recommendation-only dismissal override:** The Not Interested X action exists only on For You recommendation cards. Restaurant details from every entry, including remote/public and owner restaurants, must not render or trigger it. This supersedes the earlier bottom-right Detail-image placement. Keep existing account-scoped recommendation preferences and For You/Map recommendation exclusion behavior.

- **2026-09-07 direct recommendation reasons:** Recommendation cards show their supplied reasons directly. Remove the redundant `查看依据` action and its card disclosure; do not replace it with another link or hidden clickable reason overlay. Preserve the visible reasons and the separate recommendation-signal explanation.

- **2026-09-07 Profile status correction:** Owner/public Profile Restaurant scopes use `去过 / 想吃`. Public Profile's compact count entrances and both inline/drill-in footprint selectors reuse `RestaurantStatus` titles and glyphs: circle-check for visited and bookmark for wanted. Browser Profile uses the equivalent shared visited glyph/bookmark. This supersedes historical `想去` statistics and `到访` scope labels below; actual Visit counts, timestamps and record actions retain their Visit terminology. Preserve the existing Profile template, counts, permissions and destinations. Do Not Regress: no iconless status entrance and no divergent inline/drill-in labels.

- Every functional icon must describe a real action or value.
- A familiar system action may use an icon alone when it remains clear and has a VoiceOver label.
- Ambiguous data dimensions use icon plus a short label or current value.
- Siblings in one component group either all use semantic icons or all omit them.
- A static city filter uses a building/city symbol, never GPS, location, or current-position imagery.
- An already-visited Restaurant uses the one canonical checkmark-inside-circle glyph in every status/scope surface across React, Capacitor, and Native rollback UI. Footprints/tableware remain reserved for visit-count, visit-history, and dining concepts; the plus remains the add/record-Visit action. Do not substitute a plain checkmark, bookmark, map pin, or fork-and-knife variant for the visited-state glyph.
- Decorative Food/Dining visuals are not functional icons and never imply data unless explicitly selected from real data.

## Shared Components

Shared implementations are the default. Maintain or converge on repository-wide equivalents of `TasteMapTopBar`, `TasteMapFilterBar`, `TasteMapFilterChip`, `TasteMapIconActionRow`, `TasteMapRestaurantImage`, `TasteMapRatingReference`, `TasteMapInfoGroup`, `TasteMapEmptyState`, `TasteMapActivityCard`, and `RestaurantDetailStandardBody`.

Changing one of these patterns requires checking every consumer. Map and Discovery do not get separate filter languages; activity surfaces do not get separate cards; entry sources do not get separate Restaurant Details; Restaurant image selection and fallback do not diverge by page. `RestaurantImagePriorityPolicy` plus the canonical Restaurant-image renderer owns that last decision.

### Filters

- **2026-09-08 membership filter correction (Lafayette):** Recommendation source
  type, exact recommender/source and dining companion are Premium-only filters.
  Keep visible lock affordances for free accounts; tapping requests Premium and
  must not apply the predicate. Full-sheet choices are direct chips with six
  initial items and More/Collapse for overflow, retaining a selected overflow item.
  `自定义` is a creation affordance in recording, never a filter option; actual
  custom source identities remain selectable in the exact-source choices.
  Shared React filter primitives own Browser/Hybrid presentation; Native rollback
  uses the existing chip grid. Do Not Regress: locks must cover query application,
  not just decoration, and preserve all unrelated filters and records.

- **2026-09-08 same-taste rating correction (Lafayette):** Free accounts keep the
  同味评分 slot with a lock and Premium action, without a score, sample badge or
  rating explanation. My/community/friend ratings are unchanged. Unresolved
  entitlement is locked; use the authoritative host entitlement, not fixture tier.

- **2026-09-08 Discovery selected-condition placement (Lafayette):** Selected
  conditions such as 未去过 belong inside the same first-row horizontal
  FilterBar as Filters, City, rating and photo controls. Never render a separate
  second selected-tag row. Preserve explicit per-condition clearing and query
  semantics; overflow remains horizontally scrollable rather than wrapping.
  The full Discovery filter panel includes an explicit 重置 action alongside
  Cancel/Apply. Reset clears draft conditions and session preferences, restores
  the tab's default sort and seven-day window, and retains the opening city
  context. It does not apply or close until the user chooses Apply; Cancel
  discards the reset. Disable reset during location acquisition to prevent a
  late location result from resurrecting reset distance conditions.
  Reset / Cancel / Apply stay visible in the shared sticky form action bar,
  outside the independently scrolling filter fields, including short viewports
  and keyboard resizing. They must not require scrolling to the last field.
  Later correction: record state is a permanent first-row dimension control,
  not a removable active tag. It offers 全部状态 / 未去过 / 去过 / 想吃.
  Clearing/resetting selects 全部状态 and never removes the control. This
  supersedes using an X-only selected tag as the sole record-state entrance.

- **2026-09-07 filter focus:** Shared compact selects suppress the platform's duplicate blue focus outline. Pointer/touch selection leaves no persistent focus ring; keyboard focus retains the shared semantic outline. Keep native picker behavior, full options, selected values and accessibility intact across Map/List and Discovery.

All compact product filters use `TasteMapFilterBar`, `TasteMapFilterChip`, and `TasteMapFilterSemantic`.

- **2026-09-07 Discovery city search (Lafayette):** All five Discovery tabs expose `搜索城市` inside the city control, including entry from the full filter sheet. A city need not already occur in loaded cards. Applying it queries that target city's authorized content, preserves the other active filters and never changes Profile city, GPS or the canonical Map recommendation snapshot. Changing owner/mode/city rejects late results; continuation retains the exact accepted query and clearly states loaded-page scope, not a fabricated whole-city total. Reset returns to the existing default browsing scope. Network/auth/old-server failures remain errors, not empty-city evidence or locally filtered substitutes. The controlled Simulator-only city dataset is visibly marked `模拟数据` and cannot be presented as real city coverage. Reuse the shared city input, filter tokens, page template and existing Restaurant visual policy; no separate city-page renderer is introduced.

- **2026-09-06 consistent compact-control whitespace:** Map/List and Discovery must share the icon, visible-value, disclosure, inline-padding and gap rules for the same kind of control. React Browser/Capacitor closed selects use `TasteMapFilterSelect` and common `--tm-browse-filter-*` tokens: intrinsic visible text controls width, with a shared ellipsis cap for long values. Native option menus retain all full labels and a 44-point hit target. Hidden options, hand-estimated `ch` widths, page-local minimum widths and host font resets must not change a pill's whitespace. Equal visible labels produce equal widths; different-length labels are not forcibly stretched into uniform columns. Expanded filter-sheet fields and Browser's freely editable city search remain different control semantics and retain their input abilities. Do not regress: test same-label geometry, selected/cleared states, dark/light appearance, full native-picker interaction and Map/List/Discovery consumers together.

- **2026-09-06 working filter entrances:** Discovery's leading `筛选` action opens an actual editable filter sheet on all five tabs, never a copy-only summary or a panel rendered only for one tab. Browser and Capacitor share `TasteMapFilterSheet` / `ModalShell`; city, the active tab's sort semantics, and its public/Visit minimum rating stay connected to the visible result query and toolbar. Reopening preserves current choices; reset clears the conditions represented by that sheet. Retain existing additional Browser recommendation distance/member filters with working, authorized field predicates; an unlocked advanced-filter button may not have an empty handler. Do not fabricate fields, extend public visibility, change qualified-evidence eligibility, or infer feed completeness from UI test data. Individual dimension chips continue to open only their own control.

- **2026-09-05 complete score choices:** Minimum-rating controls expose `不限评分`, every integer threshold from `1 分以上` through `9 分以上`, and `10 分` (full score), in ascending order. Do not restrict them to 6/7/8/9 or other high-score-only shortcuts. These are inclusive minimum thresholds, not exact-score filters; clearing includes unrated records again where the underlying surface permits them. Discovery retains its existing 7.5 shortcut in addition to all integers, without changing qualified-public-evidence eligibility. Existing multi-select score-band controls remain a separate, full-range filtering mode, not a substitute for missing minimum-score options.

- One horizontal scrolling row, 8-point spacing, 34-point visible pills, minimum 44-point hit targets.
- Every primary chip has a semantic icon plus short text/value.
- Active state, count badge, press feedback, Dark/Light behavior, and VoiceOver behavior are shared.
- A dimension chip opens only its own control. Rating opens rating; price opens price; visit count opens visit count; companion opens companion; city opens city.
- Only the leading Filters/More chip may open the complete filter sheet.
- My Map's complete sheet is never a four-dropdown placeholder. For `去过` and real recommendation records it includes Dining Mode, Visit Count, multi-select Score Bands, Queue Duration (including Unrecorded), multi-select Dining Occasions, Recommendation Source type and exact source, per-visit Price Range, Visit Period, Distance, City, Dining Companion, and Cuisine. `想吃` hides visit-only dimensions while retaining Restaurant-level filters. Every visible option must change the shared typed query on Native, Hybrid, and Browser; multiple visit-level conditions must match the same Visit rather than unrelated Visits from one Restaurant.
- My List is not a contact-style directory. Each Restaurant entry restores the historical information hierarchy with a prominent square image, name/detail disclosure, 10-point score, Visit or saved/recommendation state, optional real per-person spend, address, latest Visit date, up to three real tags, and an optional personal impression or recommendation reason. Absent fields collapse; public scores, visit facts, dates, prices, and notes are never substituted for one another or fabricated.

### Primary Tabs

My Map's three scopes and Discovery's five scopes use `TasteMapPrimaryTabBar`: equal distribution, the same typography, a two-point selected indicator, and a 44-point hit target. My Map supplies semantic icon-plus-text items plus the stable Restaurant-count badge for every scope—never one isolated icon, raw emoji, or a FilterChip/pill treatment. Discovery may omit counts when they are not part of that tab's semantics. Accessibility exposes each control's text, exact Restaurant count when present, and selected state; decorative glyphs and the visually repeated count badge stay hidden from assistive technology.

### Activity and Discovery Cards

One card language must preserve: author/avatar/time, Restaurant image/name/address, the author's Visit/Activity rating, social actions, Restaurant actions, and separate sharing. Restaurant aggregate rating must never substitute for a missing Activity rating.

The visual composition is an open social feed, not a shadowed rectangular card enclosing every element. Author/Restaurant identity leads, a single Restaurant image uses a compact left-aligned square composition with deliberate surrounding whitespace instead of a mandatory full-width banner, and the social/Restaurant action groups remain visually separate. Recommendation evidence remains independent but uses open hierarchy or a light divider rather than another rounded card inside the feed item. Follow/unfollow is a Profile relationship action and does not appear in the Activity-card footer beside Like, Comment, and Share.

**2026-09-06 reason tags and social weight (latest Lafayette approval):** Each recommendation reason is an independent text-sized light-background tag, using the shared 5-point radius, 6-point horizontal / 3-point vertical inset, 6-point wrapping gap and 11-point text tokens. Tags flow onto another row only when needed; each visual tag stays compact and on one line. Prefer concise labels backed by actual structured evidence. When only full reason strings exist, show at most 12 original graphemes plus an explicit ellipsis and expose the complete unchanged reasons through the shared accessible explanation action. The combined reason region supplies one minimum 44-point hit target without inflating every small tag into a 44-point box or adding repeated empty rows. No full-width description tag, enclosing reason box, forced equal widths, border outline or leading bullet belongs to this primitive. Like, Comment and Share use bare semantic icons with quiet adjacent counts; remove the enclosing social circles while retaining real existing counts, selected/pending state and at least 44-point hit targets. The three right-hand Restaurant actions and the Visit score circle retain their existing meaning and operation. Owners are `TasteMapRecommendationReasons` / `TasteMapSocialAction` in shared React and their Native Core equivalents; no page-local list/bullet override may supersede them.

### Restaurant Actions

Restaurant action rows are compact and semantic. Record, Want to Go, add to list, roulette, directions, phone, and share do not become a wall of equal-weight pills or large cards.

The canonical Restaurant Detail title row keeps exactly three primary icon actions in this order: `加入餐厅 / 再次添加`, `收藏餐厅`, `加入转盘`. Their precise alignment is a page-composition decision: choose the placement that gives the current title, card width, spacing, and surrounding content the best visual balance rather than turning one screenshot's alignment into a global positioning formula. The `+` remains an action that opens a new Visit for an already-visited Restaurant; it is never disabled merely because the Restaurant is already `visited`. The bookmark represents whether the Restaurant is already in the current user's personal collection: a WantToGo Restaurant may be removed, while a visited Restaurant remains visibly saved and must never be downgraded to WantToGo or lose Visit history. Current viewer state may change selected/disabled presentation, but must never remove one of the three primary action slots.

The Restaurant Detail contact actions remain one equal-width three-column row in this exact order: `电话 / 营业时间 / 路线`. Long phone or opening-hours values may wrap inside their own card, but no action may wrap onto a second row. This rule belongs to the shared Restaurant summary and applies to every Browser and Hybrid consumer.

### Empty States

Use `TasteMapEmptyState`. A relevant Food/Dining visual may be supplied as decorative artwork; its message and action still describe the actual state. Loading, empty, insufficient sample, authentication, permission, and network failure are distinct states.

### Restaurant Detail

`RestaurantDetailView` and `RestaurantDetailStandardBody` are the only Restaurant Detail body. Entry source may change dismissal, analytics, and permissions, never the core information architecture.

The four rating references are `我的评分 / 全部用户 / 好友评分 / 同味评分`. Group values come from the exact Restaurant identity and the current account's authorized social/discovery projection; React must not infer relationships or query a second data architecture. Hybrid Restaurant Detail receives these values through its typed Browser/Native adapter contract. `暂无数据` remains honest when no qualifying samples exist, while the isolated Rich Demo must include populated, distinct, above-threshold samples so all four states can be visibly verified together.

Rating methodology is progressive disclosure. The default four-item strip shows only each score orb, its sample-count badge, and its rating label; `样本较少`, historical-prediction formulas, sample caveats, and other methodology copy never sit persistently below an item. Selecting a score presents a modal explanation card above the page without inserting content into or reflowing Restaurant Detail. Dismissing it restores the unchanged score strip. Browser, Hybrid, and Native fallback detail surfaces follow the same behavior.

The `用户实拍` section contains only its heading and real user photos, or the honest empty state when none exist. Restaurant-level actions must not be duplicated beneath this section. The canonical three title-row actions remain the only Restaurant action group here; Visit-specific editing remains attached to its corresponding Visit history row.

## My Map

Before the secondary settings area, Profile places an independent private `味觉足迹` directly after `发现与洞察`. It merges every valid Visit (including unrated Visits) with every currently active Want to Go save, uses the actual dining time or first-saved time respectively, and sorts all entries newest first. Discovery eligibility filters never remove owner-history entries, and every visible rating uses the 10-point presentation. The current model has no action audit log, so a removed save must not be reconstructed from `updatedAt` or fabricated as a historical event.

- Browser and iOS share the same product UI but deliberately use different map engines: Browser Web map provider; iOS Native MapKit. This is the only correct interpretation of One React UI for the map surface.

- The root App Shell contains exactly `地图 / 发现 / 我的`; `添加` is forbidden as a fourth bottom tab.
- `添加餐厅` appears exactly once as the Map-owned floating primary CTA and routes to the formal Add Restaurant flow.
- Adding a Restaurant to Roulette never opens the wheel automatically. Once the current-session candidate pool is non-empty, My Map/My List and all Discovery tabs show the same shared bottom candidate dock above the root navigation with the exact selected count, candidate review/removal/clear controls, and a one-tap `开始抽` action that remains disabled until at least two real candidates exist. The dock uses the same candidate IDs as the Roulette page, survives Restaurant Detail return and Map/Discovery/List switching, disappears when cleared, and never becomes a fourth bottom tab. Map's Add CTA sits above the dock with positive separation; scrollable content reserves enough bottom space to remain readable. Native map exclusions subtract overlapping control areas without even-odd cancellation, so MapKit can never reappear through the controls.
- Centered `我的地图` or `我的列表` title with the adjacent view-switch icon.
- Primary scopes are `去过 / 想吃 / 推荐`.
- **2026-09-06 pending-destination treasure-chest override (latest Lafayette supplied-PNG approval):** `想吃` and `推荐` Restaurant markers use Lafayette's original cartoon open treasure-chest PNG, not a code-redrawn frame or generated reinterpretation. Lafayette explicitly authorized only lossless removal of exterior-connected white background and cropping of empty margins: retain every interior color, black outline, lid, gold border and clasp; preserve the original in `docs/assets/map-marker-chest/` with checksums and the reproducible cutout script. Browser `public/map-markers/treasure-chest.png` and Native `MapMarkerTreasureChest` are byte-identical transparent assets. The canonical Restaurant photo (or existing honest fallback) appears in the body window beneath the original clasp; this is a separate presentation mask, never a destructive modification of the approved PNG or a fabricated merchant photo. This supersedes the earlier code-native chest proposal and unvisited circular/dashed shell. `去过` retains its existing circle and score ring. Browser map, static preview, Native rollback and Hybrid MapKit share the same asset/window semantics, including each exact-coordinate stack member. Keep the existing centered outer dimensions, zoom scaling and `44 × 44` root hit box; do not change coordinates, center offset, grouping, layer priority, stack offsets or click behavior. **Do Not Regress:** no numeric badge, chest emoji, replacement artwork, baked checkerboard, photo-source change or async image update that erases the independent chest shell. The user-location avatar/bubble is unaffected.
- Every primary scope visibly includes its stable total Restaurant count. Counts are current-owner scoped and count unique Restaurants, never Visits or only the currently visible map bounds; an unavailable real recommendation set is honestly `0`.
- `我的地图`顶部使用紧凑、醒目的单行文字显示口味数据进度，格式为`（X / 阶段目标 · 对应阶段文案）`，不使用占地图面积的提示卡。它只统计当前用户至少有一次有效评分的不同 Restaurant，同一 Restaurant 的多次 Visit 只计一次，无评分 Visit 不计。阶段依次为 `0–5 / 5`、`6–10 / 10`、`11–15 / 15`、`16–20 / 20`，达到阶段整数时使用完成文案而不显示“再评分 0 家”。达到或超过 20 家时先短暂显示`（20 / 20 · 口味数据已较稳定）`，之后按用户在本机隐藏此前期提醒；若有效评分数重新低于 20，则恢复相应阶段提示。
- The `去过` scope/status glyph is always the canonical checkmark inside a circle; do not regress it to a plain checkmark, footprints, tableware, map pins, or bookmarks.
- No separate Map/List segmented row.
- Map/List switching preserves scope, filters, sort, city, and search.
- Scope switching preserves map instance identity, center, zoom, bounds and Map/List state, while restoring the target scope's independent filters, sort and search. A first entry into a scope starts with clear filters. A scope value must not participate in the camera-fit identity. Explicit filter/search edits may request a fit only when their accepted result snapshot is applied; switching scope cancels an unapplied previous-scope fit.
- The selected scope updates on the next visual frame without waiting for projection, bridge, marker or image work. Scope data arrives asynchronously through a bounded, owner/version-keyed presentation snapshot; out-of-order responses cannot overwrite the newest selection.
- Marker updates use a stable-ID diff and retain unchanged marker/image identity. A scope change must not destroy/recreate every marker, reload cached Restaurant images, or rebuild the map.
- Filters use the shared components.
- Every Restaurant remains in the filtered map data snapshot. Browser and iOS retain every distinct Restaurant coordinate at city/street scale (`≤0.8°` latitude span), with natural overlap rather than hidden proximity groups. Only exact-coordinate members share a stack/list. Wider-area grouping grows between `0.8°` and `2.4°` and displays a real high-priority Restaurant image, never a quantity number or numeric badge. No grouping changes original records or primary scope totals.
- Every Restaurant marker uses one canonical concentric visual hierarchy across Browser, static fallback, Native MapKit, and Hybrid MapKit: Restaurant image or approved fallback at the center, the shared ring, a clearly visible 2-point white separation ring, then only a restrained neutral hairline and shadow. Visited Restaurants use the score-color solid ring. Every unvisited Restaurant—both `想吃` and `推荐`—uses the exact historical Web shell: a neutral dashed ring at reduced opacity with the same center image/fallback, white separation ring, hairline and shadow. Recommendation test data must never leak an owner rating into this ring. The white ring remains present in normal, unvisited/dashed, and selected states; no surface may place the inner ring directly against the map or invent a page-local palette. Wider-area representatives retain their actual member Restaurant's visual; exact-coordinate stacks preserve member access through their list without a numeric badge.
- Do not place a checkmark or other scope-status badge beneath each Restaurant marker; `去过 / 想吃 / 推荐` belongs to the shared scope control, not repeated marker chrome.
- Do not hide scope Restaurant totals or substitute current viewport Marker count, filtered-result count, or Visit count for them.
- The circle center, not its lower edge, anchors an individual Restaurant's actual coordinate. Native's root annotation frame remains `44 × 44pt`; only its centered visible circle changes size. Wider-area representatives and exact-coordinate stacks use a deterministic real source-coordinate anchor while preserving all member coordinates. Exact-coordinate Restaurants open a complete real member list instead of being moved into invented slots or hidden behind an unreachable top Restaurant.
- Layering is deterministic: personal scopes use `selected → rating → visit count → stable Restaurant ID`; recommendation rank breaks equal-rating ties, never overrides a higher score.
- Selected is always topmost; higher-rated Restaurants cover lower-rated Restaurants; visit count breaks equal-rating ties; stable ID is the final tie-break.
- A pure pan cannot change member identities, images, group membership or layer order. Zoom changes wider-area grouping on both map engines and restores distinct Restaurants at city/street scale. For visited Restaurants, Native MapKit additionally changes its 24–28-point unselected inner-circle diameter continuously inside a fixed 44-point root frame, yielding a 28–32-point outer circle including the white ring. Browser uses shared 32 px overall / 36 px selected tokens on mobile and desktop. Each visible circle preserves its anchor; exact-coordinate members remain reachable through a stack/list without quantity numbers. There are no layout offsets or spiderfy.
- Current user location uses the user's circular avatar, the shared brand-color outer ring, a subtle halo, and a small downward pointer whose tip anchors the precise coordinate. It is a location bubble, not a plain Restaurant circle or Restaurant tableware. Browser, static fallback, Native SwiftUI, and the persistent Hybrid MapKit surface preserve this same semantic silhouette.

## Discovery

- **2026-09-07 real-data review and quick filters (Lafayette):** Simulator product review uses the authenticated application/private-preview data path, not the fixed visual-QA feed. Empty, insufficient-evidence and network/auth errors remain honest; no fixture filling. Remove the repeated full-width fixture explanation strip from all Discovery tabs. Isolated visual-QA remains identifiable by its compact existing description, not a new banner. Add working public-score, distinct-reviewer-count and actual-photo controls to the existing single horizontal FilterBar beside Filters/City, using shared FilterSelect tokens; each opens only its own choices and updates the server query. This supersedes the earlier default-selected-chips-only constraint for these quick controls. Keep Release route defaults, real-account isolation and the five tabs unchanged.

- **2026-09-07 Lafayette Not Interested action:** `为你推荐` has a quiet `不感兴趣` action beside Share. The canonical Restaurant Detail places the same action at the image's bottom-right, above the existing roulette title-row action; do not add a fourth title-row action or remove any detail region. A successful dismissal persists privately per current account and removes that Restaurant and its proven local/provider/global identity aliases from both For You and Map/List `推荐`. Never match another branch merely by name or nearby coordinates. This is a recommendation preference, not deletion of the Restaurant, Visits, Wants, Lists, photos, or other users' content. Share/ratings/public-feed eligibility and image ownership are unchanged. React uses `RecommendationNotInterested` / `useRecommendationPreferences`; Native rollback uses `RestaurantRecommendationPreferences` / `RestaurantNotInterestedButton`. Read errors are not an empty preference; show Retry, suppress initial excluded-content flash, reject old-owner/late reads, preserve successful exclusions through pan/cache refresh/reopen, and never show write success on storage failure. The two recommendation projections update their count and markers together. **Do Not Regress:** same-ID/alias removal, owner isolation, save failure/retry, unmount/reopen and viewport/cache resurrection require regression coverage. The legacy Browser CommunityPage remains a separate migration gap until it consumes this shared preference boundary; source tests alone do not claim installed Simulator acceptance.
- **2026-09-06 recommendation percentage color alignment (latest Lafayette override):** Both `口味匹配度` and eligible `喜欢概率` use the canonical Restaurant score palette with `displayed percent / 10`: 100% uses 10-point color, 90% uses 9-point color, and 88% uses 8.8-point color. Reuse `scoreColor` / `RestaurantScoreColorPolicy` for value and outline accents; absent or invalid evidence uses the neutral unrated color rather than zero's color. Preserve the different labels, line styles, explanations and probability validation gate. This is a color mapping only, never conversion into an actual Restaurant/Visit rating or a new probability producer. Shared React and Native signal components own the rule. **Do Not Regress:** test scale endpoints, score-band boundaries, nil/invalid inputs and both modes; do not replace the existing palette with a page-specific gradient.
- **2026-09-06 Trending header simplification (latest Lafayette override):** Trending Restaurant cards omit both the `近期趋势` identity tag and the complete `大家评分` summary, including its numeric rating and sample count. Keep Restaurant name/context, imagery, all supplied trend-evidence reasons, Restaurant actions and Share unchanged. This is a presentation-only removal in the shared Browser/Capacitor card, not deletion of underlying rating data or a change to trend ranking, filters, Restaurant Detail ratings, other feeds' Visit ratings, or For You's match/probability signal. Native rollback already has neither matching header group and must not add them. **Do Not Regress:** populated as well as empty public-rating data must not recreate either group in Trending; verify the retained image, evidence and actions at runtime.
- Centered `发现` title.
- Equal primary tabs: `关注 / 为你推荐 / 同味之选 / 最新 / 趋势`.
- Uses the same FilterBar, FilterChip, and icon semantics as My Map.
- Activity rating is the author's specific Visit rating. Unrated Visits are excluded from public evaluation cards; they remain available to the owner's history and to Trend visit-count aggregation.
- Recommendation cards keep the high-density Legacy-base order: Restaurant identity and tag, public rating/sample plus compact source context, image, independent evidence block, then two deliberately separated action groups. Do not promote the image above identity, flatten evidence into an ordinary sentence, move Share to its own text row, or turn all Restaurant actions into equal pills.
- Similar Taste explicitly represents loading, content, empty/insufficient sample, authentication, and error states.
- **2026-09-06 honest dual recommendation signals:** Prefer `喜欢概率` only when an actual evaluated model supplies a valid probability plus validated calibration, sufficient evidence, an explicitly approved positive-feedback definition/version, model/calibration versions, validation sample count and unexpired validity. The client must not invent a liking threshold from public-feed eligibility or promote a record-count milestone into probability. Otherwise show `口味匹配度` using the existing matching index; missing or invalid numeric evidence remains `积累中`, never a percentage parsed from prose. Match and probability use distinguishable restrained dashed vs solid signal circles and a working explanation action. The match explanation explicitly says it is not a liking probability; the probability explanation states its actual approved target and calibration source. No current production probability model/producer exists, so the present product truth is the match fallback and the probability DTO is an optional future channel.

## Add Restaurant and Nearby

- **2026-09-06 complete Nearby snapshot access:** Every genuinely obtained, deduplicated, in-range candidate from the same accepted precise-location search remains reachable. Nearby initially displays 12 rows, then `继续加载附近餐厅` expands successive local batches and states the displayed/obtained counts; this is not an exhaustive provider-coverage claim. Browser, Capacitor and Native rollback retain the entire accepted snapshot. Expanding never requests GPS or repeats provider search. Refresh, a changed accepted position, owner change or superseded request invalidates the previous batch; the new snapshot starts from its first batch. Do not silently truncate the provider result to 8 or 12 Restaurants.
- Formal order: Search, Nearby, external Share ingestion, and one Manual Add card.
- Browser and Capacitor reuse the same acquisition scaffold, input, state, and result components; platform adapters supply provider/location behavior without forking the visual page.
- Restaurant-name, city, and Manual Add text fields render at `16px` or larger in WKWebView so focus never triggers automatic viewport zoom. Never solve this by disabling pinch/user scaling in the viewport meta tag.
- City scope uses a building/city/map-region icon. GPS/target icons are reserved for live current-location and Nearby status.
- After accepting a fresh GPS fix, reverse-geocode its city and prefill the editable City scope (for example, a Hangzhou fix shows `杭州`). A late location response, lifecycle refresh, or retry must never overwrite a city the user has manually edited.
- Search results must pass a shared relevance policy after the provider response: normalized Restaurant-name matches rank first, then address and food-category matches; mixed CJK/Latin input ignores case, width, punctuation, and spacing. Unrelated provider suggestions are removed rather than displayed below a true match. This filtering applies to Native, Hybrid, Browser, fixtures, and every Add/Edit Restaurant consumer; it never filters the independent Nearby list.
- Shorthand must retain a meaningful brand/place prefix and dining noun while allowing a short qualifier (for example `兰州拉面` → `兰州牛肉拉面`). Provider completions are search hints, not fabricated Restaurant records. Even when other chain branches were found, supplement the accepted same-city GPS area. Hand-picked remote city wins over GPS. Refresh an expired previously accepted precise fix before using nearby bias; never silently reuse stale coordinates or permanently discard location after the user spends time typing. A failed refresh still allows city/name search. Continuation appends genuine obtained results without duplicates and is invalidated when query/city changes; it is not a guarantee of every provider listing.
- A precise Nearby success requires full-accuracy authorization and the existing freshness/accuracy gates. Reduced accuracy displays a clear actionable status instead of distant candidates as though they were directly nearby. Supplement broad results with both a small-radius 500 m POI request and a region-required local Restaurant-keyword request before the shared identity deduplication, straight-line-distance ordering and 3 km cutoff; a nearby text result may resolve a small Restaurant omitted from the POI response. Never hard-code neighborhood merchants into production queries. Test GPS and synthetic candidates must be paired behind an explicit isolated test gate, never substituted into ordinary QA or iPhone use. Ordinary and Private Preview launch schemes disable Xcode location simulation; the isolated QA scheme is the explicit simulation surface.
- Search, Nearby, Share, and Manual Add share icon-container, row-height, divider, focus, pressed, disabled, loading, empty, and error grammar while retaining their approved primary/secondary weights.
- Manual paste is not a primary in-app section; parsers remain available to the Share Extension.
- Nearby uses a fresh CLLocation after checking authorization, accuracy, timestamp, and horizontal accuracy. Full-accuracy authorization alone does not make the first delivered coordinate precise: the shared location provider must reject coarse fixes, continue long enough to select the best acceptable update, and prefer a meter-level fix before starting the provider query. A new sensor request must not mistake a replayed cached fix for a new fix. Revalidate at delivery time as well as callback time, because suspension can make a previously acceptable fix stale. Map and Add may share an in-flight sensor request, but a new request after completion acquires again. The visible Map refreshes actual location on foreground resume, ignores superseded/hidden-page responses, and preserves the user's browsed camera extent. City center or map camera center can never impersonate GPS.
- Nearby provider coverage begins with a coordinate-centered food/dining point-of-interest radius request, then merges the established Restaurant/Food/Dining keyword searches plus a local-small-food query, deduplicates provider identities, recomputes straight-line distance from the same accepted GPS fix, applies the 3 km bound, and sorts nearest first. Provider relevance ranking alone must not hide genuinely nearer small Restaurants. If this first pass is empty, Native MapKit performs one bounded secondary pass with alternate Food/Dining vocabulary and a wider provider-ranking region while still enforcing the same 3 km result boundary. A partial provider failure is an error with Retry, never proof that the user's neighborhood contains zero Restaurants; the no-result state is allowed only after every independent request completes successfully and all merged in-range results are empty.
- A successful precise Nearby result proceeds directly to candidates; do not add a redundant location-success banner or GPS-sorting footer. Keep compact loading, reduced-accuracy, permission, error/retry, and no-result feedback.
- Selection shows the standard Restaurant Detail foundation before Want to Go or Record Visit.
- Provider identity aids dedupe but is never the Taste Map primary key.

## Restaurant Detail

Canonical order: hero; city/status; name; address; compact actions; reference spend; phone; hours; directions; rating reference; my/all/friend/similar-taste ratings; user photos; my visit overview; visit history; dishes and detailed ratings.

Rating circles mean: large circle = score, small circle = sample count. Nil never renders as zero. In the four-item rating-reference strip, every no-data dimension uses the same empty-state composition inside its circle: the shared empty graphic plus `暂无数据`, with only the dimension name below. `我的评分` must not diverge into a dash plus a separate `未评分` caption.

Restaurant facts obey a fail-empty provenance contract. Name, address, coordinate, phone, website and category are retained from real fields returned by the selected Provider, with Apple MapKit / `MKMapItem` as the primary iOS source. The current Restaurant Detail deliberately omits the website item; the Provider website remains in the data/sync contract for compatibility and is not replaced with a `暂无官网` card. Opening hours, merchant images, ratings and reference price may appear only when an approved real source actually supplies them; public MapKit APIs not exposing structured hours is not permission to synthesize hours. Missing displayed facts render a stable `暂无…` state instead of Demo Restaurant content. A category/emoji marker may remain as a clearly labelled Restaurant icon or avatar, but it must never be labelled or styled as a merchant photo.

Rich Demo and fixture Restaurants are test infrastructure only. They require an explicit isolated QA/test runtime or an explicit internal debug opt-in. Release and normal Debug user paths must neither auto-seed nor auto-load them, and real accounts must never need to restart before real Provider fields replace a previously sparse projection.

## Visit Editor

- **2026-09-08 amount-only display (latest Lafayette override):** Under `消费金额（元）`, do not display calculation hints, computed reference-per-person/spending outputs, or historical-payment preservation/recalculation notes, for any amount or payment mode. Shared `VisitSpendFields` (Add Restaurant / Record Visit / Edit Visit in Browser and Capacitor) and Native `VisitEditorView` show only the existing editable amount field in this block. Keep payment-mode and party-size inputs elsewhere, all validation, AA/treat calculation, nil/zero semantics, historical-payment preservation and actual statistics unchanged. This supersedes the earlier requirement to display these internal calculations, not the calculations themselves. Do Not Regress: no hidden-copy placeholder or empty calculation row; Restaurant reference prices outside this input block remain intact.
- **2026-09-06 unframed context:** Record Visit and Edit Visit keep the existing Restaurant context but remove its enclosing border above `这次到访 / 修改这次到访`. Retain the named section divider and its two 1-pixel side rules. Browser and Capacitor use the same `AddVisitModal` and the shared Restaurant-summary unframed variant; do not hide or delete Restaurant facts/photos to remove the line, or remove unrelated form/card separators.
- **2026-09-05 automatic consumption semantics:** Add Restaurant, Record Visit, and Edit Visit expose exactly one editable `消费金额（元）` field. Do not reintroduce separate `整桌账单` and `我的实际消费` inputs. The selected consumption mode and party size determine the internal actual-spend result: AA divides the amount by the positive party size; I treat pays the full amount; being treated pays zero; separate/other accepts the owner's entered payment as personal expenditure, never as a fabricated table total. A single-person record pays the amount. New blank amounts remain unrecorded except the explicitly selected being-treated zero. The 2026-09-08 override removes display of this computation from the input block.
- Personal total expenditure is the sum of resolved, non-deleted owner Visit payments using that same rule in Profile, spend details and analyses. Preserve explicit historical personal payments on unrelated note/photo edits; changing amount, party size or payment mode recalculates on save. Omitted Native optional keys and explicit null are equivalent. Legacy multi-person records without a payment mode remain unresolved, not silently AA or fully owner-paid; unknown future payment modes are not treated as single-person.
- **Restaurant reference price remains:** `参考人均` is a dining-price reference for Restaurant cards, detail, filters and analyses, distinct from personal expenditure. When a recorded meal amount and party size exist, derive its per-person reference independently of who paid: 200 for four people is reference 50 under AA, I-treat and being-treated, while personal expenditure is respectively 50, 200 and 0. Separate/other personal payments may provide the person's own price reference without inventing a table total. Existing Restaurant/reference prices are not removed by this input simplification or replaced by a guest's zero payment. Calculated outputs no longer appear below the amount input under the 2026-09-08 override.
- The approved editor is one continuous, compact dining diary. Restaurant context, core experience, ratings, dishes/photos, dining context, notes, and the final save action remain in one readable flow.
- Optional choice dimensions are visible and directly tappable. They must not be hidden behind default disclosure/expand controls merely to shorten the page.
- Every editable star control uses explicit `SET` and `CLEAR` semantics. A star or half-star tap directly sets the target 0.5-step value in one state transition, including when tapping the current value; it never toggles to nil. Only the separate `清除` action may remove a rating. The shared field uses semantic `fieldset` markup so an ancestor label cannot forward the same gesture to the clear button.
- Selected stars use the shared warm-amber `--color-rating-selected` token, promoted from the historical approved dish-rating gold; unselected stars retain a quiet gray/blue-gray outline. Browser and Capacitor consume the same shared editable rating component and synchronized star/label/ten-point projection.
- The visual restoration does not change field optionality, nil semantics, persistence, offline mutation behavior, photo lifecycle, or save validation.
- The primary save action remains the current canonical save implementation; the Legacy reference governs layout density and information order, not data architecture.
- Successful Visit saving completes the editor's existing navigation entry. Returning from the resulting Restaurant Detail must restore its original parent, never reopen the completed editor or duplicate that Detail in history. Shared Browser/Capacitor and Native navigation reconcile this even when the editor was restored without an in-memory parent reference; a late navigation acknowledgement must not undo a newer user destination. Saving still refreshes the real owner data without recreating the shell or waiting for unrelated Discovery requests.

## Profile and Lists

- **2026-09-08 private directory settings:** Settings owns one `饭搭子与推荐来源` management entry, below membership/referral groups, for friend linking, private companion/source avatars and source-to-user attribution. Companion linking retains explicit recipient consent. Source attribution is private, not a public endorsement or authorization to copy records. Owner-scoped metadata must never change another person's Profile avatar or leak across account switches. Do not regress account/membership ordering or promote a Hybrid route as part of this feature. See `PRIVATE_DIRECTORY_SETTINGS.md` for implementation limits and pending activation acceptance.

- Compact identity header with avatar, name, joined date, Premium, following and followers.
- **Profile avatar resource regression (2026-09-07):** a saved Native personal avatar must resolve through the existing authenticated Native resource channel, never the Browser Dexie/Drive photo namespace. Profile and owner activity authors share the same projected avatar and `UserAvatar` renderer. Loading/unreadable images use the existing preset rather than an empty circle; this does not change saved avatar preferences, public-photo authorization or Restaurant image rules. Validate actual photo selection → Save → Profile → owner activity, not editor preview alone.
- **Profile editing entry (Lafayette, 2026-09-06):** remove the explicit `编辑资料` button from the owner dashboard identity block; the existing `设置 → 账户与安全 → 编辑资料` is the canonical full-edit entry, with no duplicate Settings row. Remove the button's now-empty action container/spacing, but preserve avatar, name, ID, social metadata, joined date, statistics, Premium, legitimate share actions and all downstream ordering. This narrow change does not alter the existing avatar gesture or editor/modal/API; React Browser/Capacitor and Native rollback use their shared identity owners. **Do Not Regress:** no dashboard text-edit button or empty identity action row; Settings still opens the real editor and save/cancel retains its destination.
- Following and follower counts sit immediately below the person's name as compact identity metadata; they do not float above the name or become a second detached statistics block.
- Top statistics are unique visited Restaurants, Want to Go Restaurants, and valid actual spend.
- The three top statistics remain one coherent group. Each uses an icon-and-value line with the label below; the longer currency value receives sufficient width and a restrained fitting size so it does not overpower or collide with the two Restaurant counts.
- Roulette and Taste Profile are paired; Monthly, Annual, and On This Day share one Memories section; Lists and Insights retain their own sections.
- The paired `今天吃什么 / 我的口味档案` and `最佳饭搭子 / 谁最会种草` cards stay as two equal-width columns at phone widths. These cards are already complete tap targets and never carry a trailing arrow or chevron. Their icon, title, and supporting copy provide the affordance without redundant right-edge decoration; Native dashboard tiles follow the same card grammar. The first pair uses one short, stable invitation line (`帮我挑一家` / `看看我爱吃什么`); the Profile entry never replaces that line with cuisine, price, or taste-trait data previews.
- The stable numeric public user ID appears immediately below the account display name on owner and public Profile headers. Profile bio/signature is retired: it has no display surface and no edit control. The legacy schema field remains read-compatible only so older sync/backup payloads are not broken.
- Lists support real create/add/reorder/edit/remove/visibility/persistence behavior; decorative empty art never masquerades as list data.
- Food-list Restaurant rows retain the original stored/provider coordinate and a nullable ten-point rating with an explicit source: `我的评分` is the current viewer's own authorized Visit aggregate; `公开评分` requires an actual public Restaurant aggregate. A list author's private Visit, list rank, recommendation match or missing sample never supplies that score. Missing coordinates do not become city-centre pins, and absent ratings remain `暂无评分`. In-app detail pagination preserves every obtained member and states the loaded/total counts; a cached preview is not a complete List. Sharing succeeds only through an actual permission-checked public link, not the List title as text. Non-public, unsynced, unavailable and non-owner share cases remain honest errors without automatically changing visibility. **Do Not Regress:** owner change, permission revocation and a new List revision reject old pages/links; preserve existing notes, rankings, images, edit rights and the reachable back action.
- On the owner Profile, a single List card spans the available row. The `查看全部食单` entry remains in normal document flow below the card with positive separation; it must never use a negative margin or overlap the List card.
- Owner Profile and `查看全部食单` are two projections of the same iOS/Native List snapshot, never a Native/Web-Dexie split. Profile shows the two most recently updated owner Lists and the entry states the full owner-List count; creating or editing a Native List refreshes both projections together. A Profile List card opens that exact List detail rather than a separately queried or reconstructed copy.
- Creating or editing a List presents `仅自己 / 好友 / 公开` as three directly tappable, fully labeled choices. The selected state must be visually explicit and the saved List must persist that exact visibility; iOS must not depend on a small browser-style select control for this choice.
- The add-Restaurant panel inside a List uses a stable three-column row: fixed circular Restaurant avatar, two-line name/location copy, and a fixed trailing add affordance. Copy layout rules must never flex or stretch the avatar, and repeated rows retain clear separators and tap targets.

## Roulette

**2026-09-08 Lafayette allowance:** Nonmembers may draw once per local calendar
day; opening the wheel or managing candidates consumes nothing. Starting a valid
draw consumes the allowance; reroll uses the same check. Premium has unlimited
draws. Current local implementation persists an account-keyed device allowance
across remount/relaunch. Cross-device/server-authoritative accounting remains
unimplemented and must not be represented as global enforcement. Preserve the
approved wheel, uniform draw and candidate management.

Restore the approved Web/history wheel while following the current iOS interaction contract. Candidate chips, visible wheel segments, and the random pool are the same unique Restaurant set: three candidates produce exactly three segments, with no vacant or `添加更多餐厅` segment after drawing begins. Candidate management remains a separate control outside the wheel. Chips, segments, and the selected-result card use the same Restaurant image/fallback identity. Restaurant detail is a child destination of the roulette, so returning restores the same candidates, winner, wheel rotation, and reroll state.

## Analytics and Share Posters

**2026-09-08 Lafayette duplicate-entry removal:** Taste Profile's F02 question
index omits 饭搭子与来源 and shows five topics, not six. The independent
最佳饭搭子 and 谁最会种草 reports retain their entries, calculations and data.
This supersedes the six-entry F02 reference for this navigation region only;
no companion/source records or poster data are deleted.

**Latest 2026-09-07 clarification — keep editorial posters, update data routes:**  
The later five-image reference set extends the rich scrapbook/receipt editorial
direction to Monthly, Annual, Recommendation Source and On This Day posters.
Their simplified memory-card layouts are interim and do not satisfy final
visual-reference acceptance. Data mode retains the v2 navigation. Use the
corresponding reference anatomy, real available evidence and the existing privacy
boundary; never invent mood/quotes, identities or source-attribution metrics to
fill decorative sample modules. Best Companion has no new supplied poster image.

Lafayette explicitly reconfirmed the supplied radial-food / receipt / paper-note
Taste Profile image for 画报, while retaining the new clickable structure for
数据. The shared Taste poster is again 1080 × 1620 (2:3), with the complete
editorial module anatomy, not the simplified F24 9:16 card described in the
historical paragraph below. This is a poster-only supersession: do not restore
long default-expanded data reports. Reuse the existing shared editorial renderer,
canonical food assets and actual report snapshot. Owner/full and external/public
previews remain distinct; exported PNG must be the reviewed privacy-safe blob.

The supplied 分析回忆补全 v2 adds Source S01–S10, Month M01–M08, Year Y01–Y08,
On This Day D01–D08 and shared X01–X03 reading flows. Source has two visible peer
entrances, with 最坑推荐来源 an independent S03 page, not a hidden subsection.
Its detail preserves source identity, low/all lens and first-experience records.
Methods and samples remain free; >=5 first-rated Restaurants and the existing
baseline-minus-one rule remain authoritative. S10 is anonymous positive-source
sharing, never a named negative leaderboard. Missing saved-source relationships
must be explicit; S08 cannot invent untried recommendations from Visit data.

Monthly/yearly short homes lead to real calendars, exact scoped records, original
first/new versus repeat visits, matched-period comparisons and period-specific
people/sources. A quarter's photos must come from that quarter. On This Day is a
free independent memory flow: exact prior-year calendar date, all qualifying
Visits, original notes and selected-Visit images; nearby dates are a separately
labelled fallback and never become same-day matches. Cover and privacy are shared
bottom sheets with actual preview updates. No fixture names or numbers are facts.

Shared implementation owners: AnalysisReadingUI, RecommendationSourceExplorer,
PeriodMemoryExplorer, OnThisDayExplorer and MemoryPoster. Browser and Capacitor
consume these same components and typed canonical Visit/Restaurant handoffs.
Embedded MapKit in F13/Y05, untried-source attribution and Native rollback parity
remain acceptance gaps; this rule does not promote route ownership.
Do Not Regress: editorial 2:3 Taste poster, short data homes, explicit S03,
first-Visit source evidence, period/back context, private/public recomputation,
date-only ≠ meal time, no fabricated map or sample winner.

**2026-09-07 evening — F01–F24 clickable reference override:** Lafayette supplied
`routes.json` and `TasteMap_逐屏可点击原型.html` and explicitly requested this
composition. For the shared Taste Profile destination this supersedes the earlier
chapter-selector navigation and 2:3 poster target. F01 uses a left-aligned title,
one real conclusion, a small data-linked food visual, four bounded categories,
habit strip and a single complete-analysis entrance. F02 has six direct question
entries, not topic tabs followed by a chapter dropdown. Detailed charts carry
typed same-Visit conditions into the original-record list. Filter drafts apply
only on confirmation; evidence uses the shared bottom sheet and closes to the
same reading position. Reuse canonical Restaurant/Visit destinations; no new
analysis-only editor or duplicate app router. Browser and Capacitor share
TasteProfileExplorer, existing Core/modal controls and FoodLibraryArtwork.

F24 is a dedicated 1080 × 1920 (9:16) taste card, not a page screenshot. It uses
the selected scope and real frequency-ranked cuisines. The owner preview stays
private; the external version is rebuilt from public records only (private and
friends records excluded), then strips spending, companion identity and private
notes. Preview and export use the exact same PNG Blob. No valid public-link
configuration means no invented QR. Existing legacy 2:3 renderers remain separate
migration consumers, not proof of conformity to this new shared-route design.

**Later explicit addition: 最坑推荐来源 must remain available.** Provide an
explicit peer view beside 最合口味 in the source explorer and a visible entrance
in the standalone source report. Reuse the existing source-quality policy:
at least five rated attributed Restaurants; low outcome is first-experience
score at least one point below the owner's first-experience baseline. Show
numerator/denominator and concrete Restaurant/Visit evidence, preserve low-score
return context, and never fabricate a worst source from insufficient samples.
The label describes recorded outcomes, not the worth of a person.

Do Not Regress: six one-click topics, explicit 最坑 entry, record predicate
intersection, date-only ≠ night meal, unrated ≠ zero, source sample gates,
public-only recomputation, cancel/apply and return restoration, 16px inputs,
44px targets, bounded home and 9:16 bitmap. F13's embedded MapKit footprint
remains OPEN until implemented and verified; city rows are not map acceptance.
Native rollback/legacy analytics remain migration gaps, with no route promotion.

**2026-09-07 latest Lafayette short-story data override:** The five-phone
reference governs the DATA module only. Each home follows one report-backed
headline → food/memory visual → at most four facts → one focus → complete analysis.
Use open white/blue-grey composition, readable headline type, a compact pale-blue
habit/feature band and a single full-analysis CTA. Core content targets one to two
phone screens at default type; never shrink type or clip content to meet the goal.
The independent approved 2:3 Taste poster is unchanged by this override.

Taste separates frequency from personal rated averages and uses at most four
data-linked cuisine illustrations with one number per active lens. Unrated meals
count only toward frequency; the shared analyzer owns rated-comparison sample
gates and the UI must not invent or independently hard-code them. Monthly facts
are Visits, distinct Restaurants, first-ever-recorded
Restaurants and repeat Visits (all period Visits minus period first Restaurants).
Annual uses Visits, Restaurants, known cities and first Restaurants, and states
the actual month coverage. Neither page calls the frequency winner "most loved".
Companion facts describe the selected person's shared records, not relationship
quality; the score explicitly belongs to the owner. "First explored together"
means the owner's first recorded Restaurant experience had this companion; it
does not claim to know the companion's earlier history. Shared repeat Visits
exclude each Restaurant's first shared Visit. Unrepeated memories say "一起吃过".

Source home omits the food hero and negative ranking, presents at most three
qualified sources with high-score numerator/denominator and verified rated
Restaurant sample, and never crowns a one-sample source. Existing source-quality
gates/ranking remain authoritative. A source drill-in updates the selected report
identity so its data and poster/share stay aligned; negative sources remain a
detail view. When there are no untried attributed candidates, link a genuinely
verified high-score Restaurant instead of fabricating a suggestion.

Complete analysis retains every section behind topic/section navigation, one
chapter at a time. Meal-time, taste-tag and price distributions use compact bars,
with full labelled values available on expansion. No population radar comparison
or invented geographic outline is authorized. Original owner/period/person-scoped
Visit rows remain available, including their unmodified notes; share projections
continue to exclude those private notes. City details currently retain factual
city/Restaurant evidence; a geographic basemap is a separate remaining visual gap.

Shared owners: analyticsReportHome, AnalyticsReportDataView/AnalysisDetailSection,
analyticsReport and the existing FoodLibraryArtwork. Browser and formal Capacitor
consume the same React template. Native rollback and the legacy Browser analysis
panel remain migration gaps; this data-layout change does not switch route owners.
Date-only records never count as timed meals. Contradictory solo + companion/social
context is labelled for confirmation and excluded from solo/together comparison
and person attribution, without modifying the original Visit. Rich QA seeding now
uses explicit local meal hours and does not attach companions to solo samples.
Do Not Regress: bounded five-mode home topology, real sample gates, selected
source/share identity, four correctly unit-labelled facts, complete detail and
record reachability, long names, empty states, 375/402 light/dark and formal
staged/built/installed runtime identity. This supersedes default-expanded data
tables and older mandatory in-app poster anatomy, not poster/export privacy.

**2026-09-07 Lafayette reference and data correspondence:** The newly supplied
Taste Profile image reaffirms the 2:3 editorial target: central food with radial
cuisine nodes, title/period at left, receipt overview and findings at right,
Top 3, taste preferences, consumption, reference-price ranges, cities, companion
context and dining times below. Reference numbers, five-star ratings and inferred
relationships are not data. Keep ten-point scores and the real report scope.
The accompanying five-module V1 document is a content reference, not automatic
approval of new paywalls, scoring formulas, sample thresholds or 9:16 Taste Profile.

Shared `analyticsReportHighlights` owns the data/poster finding priority; poster
renderers must not invent a second set of highlights from unrelated counters.
The owner-only complete poster preview retains the report's original private
statistics. The share action first switches to a visibly labelled safe share
preview; only a subsequent action on that generated safe preview may export its
exact Blob. No owner-only download action exists. Default share still hides
consumption and companion information; this change grants no extra photo rights.
Both preview variants retain the same owner, report, period and selection.

Date-only Visits stay in record totals, but never become midnight/late-night
evidence. Data and poster use the same timed-Visit denominator and display its
coverage. Multi-label cuisine percentages explicitly remain non-additive. Missing
fields or privacy-hidden charts have honest states, not invented bars or a hollow
donut labelled as data. Use shared poster drawing/food-library assets and semantic
flavor icons, never emoji or fabricated geography. Do Not Regress: all five report
findings, private-preview/export separation, exact PNG equality, long text,
date-only history, 375/402 light/dark and installed Hybrid runtime must be checked.

**Latest Lafayette override, 2026-09-06 — results first:** The data report is
not a default-expanded inventory of every statistic. Lead with a prominent core
conclusion and no more than three report-backed findings, with explicit visual
separation, readable titles and clear priority. Promote meaningful historical
changes and supported outcomes ahead of supporting tables; never invent a finding
or bypass sample gates to fill a card. Keep the complete owner/period/selection-
scoped analysis behind accessible disclosure controls, including methods, history,
metrics and Restaurant evidence. This is a presentation projection, not a new
calculator. Preserve the established poster, stable share, period/person selectors
and privacy defaults. The five shared Hybrid data reports use this same renderer.
Native rollback and the legacy Browser panel remain separate migration consumers;
this presentation correction alone does not claim their parity or change ownership.

**Lafayette override, 2026-09-06:** `数据` is a legible, scrollable data report,
not a scaled-down poster. This supersedes older in-app infographic-only language.
Fuse legacy depth/history with current identity, sample, payment and privacy rules;
do not restore the old Web application wholesale. All five Hybrid reports now use
one owner/period/selection-scoped report object, including their share projection.
Keep historical month/year selection and a stable top share action across both
modules. `画报` retains the independent 2:3 Taste Profile / 9:16 other-report format;
it is a same-evidence summary, while data mode retains the complete analysis.
Default share excludes actual spending, private notes, and companion directory
names. Selection changes cannot reuse another person's or period's evidence.

- Analysis pages are scrollable poster-like infographics, not ordinary card dashboards.
- The center Food Hero is data-linked only when supported; otherwise it is clearly decorative.
- Taste Profile, Best Companion, Recommendation Source, Monthly, and Annual share one visual family while preserving independent semantics.
- Every page has one `数据 / 画报` module switch. The data module shares a readable text summary of its current real metrics and insights; the poster module previews the formal renderer output and owns image share/save.
- Every poster footer uses the official App Icon, Taste Map name, optional short tagline, and a high-contrast QR code from fail-closed Release configuration.

## Premium

**2026-09-07 Developer Gift:** Gift annual/lifetime unlock the exact existing Premium feature set through the authoritative entitlement service. Preserve the current Paywall template, Core controls and approved hamburger assets. The active-state text is `赠送会员 · 有效期至 YYYY年MM月DD日` or `永久会员 · 由 Taste Map 赠送`, beneath Taste Map Premium. Gift has no Apple management action; App Store subscriptions retain it. The sales state exposes only Monthly/Annual. Internal gifting stays on an independently authenticated server Admin page, never in the consumer App bundle or navigation. Do Not Regress: no React entitlement inference from profile tier, no device-bound gifts, no StoreKit overwrite, no Release debug override; test late A→B→A responses as well as ordinary logout.

The compact Premium identity badge used in Profile keeps the previously approved historical hamburger asset. The Paywall hero hamburger is a separate visual-approval region and is currently pending a Lafayette-approved redesign; no candidate may replace the formal Paywall hero before approval. Never use fake prices or emoji food rows in the formal Premium hero.

## Human Visual Approval Freeze Registry

**Latest Lafayette hold, 2026-09-06 (after supplied-PNG work):** treasure-chest
marker changes are PAUSED while Lafayette considers the design. The PNG and
renderer edits currently in this worktree are local candidates, NOT final visual
approval and NOT eligible for real-device sync or release. This overrides the
earlier supplied-PNG approval below. Do not resume or ship this candidate until
Lafayette explicitly confirms; a future unrelated sync must isolate/exclude it.
No treasure-chest build has been installed on Lafayette's physical iPhone.

The paused candidate is isolated by a shared-semantic, default-off marker-shape
gate in the Web and Native primitives. Formal main markers and exact-coordinate
back members retain the historical circle/dashed shell. The PNG, source artwork
and candidate renderer remain preserved for isolated tests only; no user setting,
launch argument or ordinary QA mode enables them. This isolation is not renewed
design approval. It changes no size, coordinate, anchor, offset, image source,
grouping or interaction, and the staged/built artifact still requires verification.

Lafayette visual approval is region-based and convergent. A region marked KEEP is frozen; later candidate versions may change only regions marked `需要修改` or `重新设计`, unless Lafayette explicitly unfreezes a region.

- **Approval source:** `TasteMap-Lafayette-Visual-Approval.zip`, exported 2026-09-02. Its `approval.json` is the current machine-readable freeze registry; report text and earlier automated `Visual PASS` labels cannot override it.
- **My Map / My List:** approved title switch, scopes, filters, preview, add action and state behavior are frozen. Lafayette's latest 2026-09-05 correction requires fixed circle anchors, individually visible Restaurant images with natural city/street overlap, wider-area real Restaurant representatives and exact-coordinate member lists. No quantity number or numeric badge belongs on a map marker. Higher scores appear in front. Native visited circles retain a fixed 44-point root frame and a 28–32-point normal outer diameter including the white ring; Browser uses shared 32 px overall / 36 px selected tokens on both viewport classes. Rating-colored rings, the unchanged white separation ring and canonical real-image priority remain required. Generated QA artwork may not masquerade as a provider merchant photo.
- **Discovery:** the approved Legacy-base/FUSE composition is frozen, including centered title, five primary tabs, shared FilterBar and Legacy activity-content geometry.
- **For You card override:** the personal-history recommendation card must not show `优先推荐`, `推荐给你`, or a public `大家评分` as its primary signal. The latest 2026-09-06 approved dual-mode rule supersedes the former unqualified `喜欢度` percentage: validated and sufficiently supported model output may show `喜欢概率`; existing heuristic/history percentages show `口味匹配度`, with distinct styling and accessible explanations. The latest reason-tag approval supersedes a full-width enclosing reason box or leading bullets; each reason hugs its text and wraps independently. Footer Like/Comment/Share lose their outer circles while keeping the separate right-hand Restaurant action group. This correction changes these approved regions only and does not authorize new image, route, score or action semantics.
- **Add Restaurant / Nearby:** the Legacy-base Search, Nearby, Manual Add, results, preview, actions and transition are frozen; current Share ingestion remains frozen and current-only.
- **Restaurant Detail:** the global Legacy-base information architecture is frozen and continues to use the single current `RestaurantDetailStandardBody`.
- **Roulette:** the approved Legacy wheel, candidate management, result, imagery and state geometry are frozen while current selection semantics remain authoritative.
- **Visit Editor:** all regions approved. Legacy layout/density is frozen for restaurant context, core experience, ratings, dish/photo entry, dining context, and notes; the current canonical Save CTA is frozen.
- **Dish / Photo Manager:** all approved regions use the Legacy layout base while preserving current photo lifecycle and business semantics.
- **Visit photo entitlement (2026-09-06):** one Visit allows 2 photos for Free and 20 for Premium, counting attached dish photos in the same budget. Preserve all historical photos above the current limit during unrelated edits; do not truncate, delete, or migrate them. New material must satisfy the current allowance at selection and save/sync boundaries. Browser-local material must not cross the Native bridge, which continues to use opaque photo IDs. Backup/import retains historical data and is not a new-photo picker.
- **Public Profile / Social Hub:** Social Metrics, actions, Restaurant evidence, activity, public Lists and safety actions preserve current Social, moderation, sharing, and data-isolation capability. The user-facing follower term is `粉丝`. The Social Hub has exactly four peer sections in this order: `好友 / 关注 / 粉丝 / 推荐`; a visible friend exists only when both users follow one another. Recommendation and search share the `推荐` section, while legacy search/request concepts never become extra top-level sections. The current public Profile does not hide `食单` and `动态` behind a mutually exclusive switch: it presents an authorized public food map first, then an independent `食单` section, then an independent `动态` section. `到访 / 想吃` belongs inside the `去过公开记录` activity block and must not be repeated as detached hero statistics. `关注 / 粉丝` uses the same compact identity metadata pattern as the owner Profile directly below the person; the real joined month follows with city metadata. Every visible value comes from the authenticated Provider/API response or its permission-safe cache; unavailable data uses an explicit loading, empty, or failure state and never a dash, fabricated zero, Demo Restaurant, or generated record. Header machine choice is still blank and must not be auto-approved, even though a historical note says it was confirmed.
- **Social Hub compact Follow action (Lafayette, 2026-09-06):** recommendation and people-search rows share one compact text-only Follow primitive. Center the visible `关注` title inside its capsule; do not reserve a hidden List Label icon column or stretch the action to fill remaining row width. At default type, use a 64-point minimum width and 30-point visible height with a real minimum 44-point interactive target. Loading retains the same width and centers its spinner; larger accessibility text grows naturally without truncation. Reuse semantic brand/on-brand colors and centralized tokens. This row-action rule does not replace the distinct public-profile relationship action group, icon-only Browser actions, or Add Friend semantics.
- **Lists / Public Lists:** all approved regions use the Legacy layout base while preserving current list models, visibility, sharing, and persistence.
- **Settings / Data:** the current native-density structure is approved and frozen.
- **2026-09-08 APP ICP registration (Lafayette):** The existing SwiftUI `AboutSettingsView`, reached from 我的 → 设置 → 关于 Taste Map and reused by the Hybrid native handoff, displays `备案号：浙ICP备2026070007号-1A` directly in its legal-information section. The whole row opens `https://beian.miit.gov.cn/` with the system browser through SwiftUI Link/openURL. Keep it visible even when other legal URLs are unconfigured, with wrapping text and the shared 44-point minimum target. Do Not Regress: no placeholder registration, nested registration page, custom WebView, extra permission, navigation restructuring, or changes to bundle/team/signing/StoreKit/Premium.
- **Settings information architecture:** iOS has one Settings index. `账户与安全` is a single detail destination containing profile editing, Taste Map ID, sign-out and permanent account deletion; it must not reopen or duplicate the Settings index. Backup/import/local clear, sync, privacy, permissions, storage, Premium, help and about each have one canonical entry and navigate directly to their own detail or system surface.
- **Signup Premium trial (Lafayette, 2026-09-08):** the existing Premium page offers an explicit server-authorized one-time 7-day claim with `免费体验 Premium 7 天`, `无需订阅，不会自动续费`, and `免费领取 7 天`. Reuse its current card, typography and minimum 44-point controls without changing the hero, benefits or navigation. Hide the claim after any historical signup trial, show success and expiry, and restore the ordinary monthly/annual options after access expires. Native and shared Hybrid use the same server entitlement authority; this is not an Apple introductory offer and never creates a StoreKit transaction. See `SIGNUP_PREMIUM_TRIAL.md`.
- **Settings membership priority (Lafayette, 2026-09-06):** the Settings index presents an independent `会员权益` section immediately after `账户`, before data/backup, sync, privacy/permissions and storage. The Premium entry is visible in the first screen without scrolling for both free and paid users; it must not be buried in or grouped with Storage. Reuse the existing Settings section/row style and actual Premium destination—no additional promotional hero, fabricated price, duplicate purchase entry or entitlement-policy change. React Browser/Capacitor and Native rollback follow the same priority; legacy Browser's all-settings membership-first entry remains valid. **Do Not Regress:** assert order, single Premium action, first-screen visibility and the working benefits/return path.
- **Settings direct editing (Lafayette, 2026-09-06):** `显示名称` and `主页可见范围` are editable rows, not read-only summaries that require detouring through `编辑资料`. Each opens only the requested fields in the same owning Profile editor; the full `编辑资料` entry retains avatar, name, city and visibility together. The Privacy detail uses the same visibility editor, not a second profile form or duplicated “current value → modify → full profile” sequence. Save updates only the requested scope, cancel makes no change, unrelated fields remain intact, and returning preserves the Settings destination. Read-only account facts have no disclosure arrow or fake action. Decided location/camera/photo permissions—including allowed states—remain adjustable through OS Settings; undecided permissions explain their real contextual request without auto-requesting. Sync labels distinguish a status/detail entry from `立即同步`/`重试同步`, show the actual result, and lock repeated actions while pending. Browser Settings must honor the named detail/backup/storage destination rather than routing every row to a generic data modal. Shared owners: `SettingsEditableRow`, `ProfileEditorSheet`/`ProfileEditorModal`, `HybridEntryRow`, and `TasteMapSettingsPage`. **Do Not Regress:** no no-op edit-looking rows, no unrelated detail pages, no duplicated forms, no loss of sign-out/deletion/import/export safety confirmation.
- **Clear local data:** Settings exposes one destructive `清除本机数据` action behind an explicit confirmation. It removes the current account's Restaurant, Visit, Dish, List, related local-photo and derived-cache state from this iPhone only, while preserving the signed-in account, own Profile, active Profile avatar, Premium entitlement, sync checkpoint and all server-side data. Copy must keep this boundary distinct from permanent Account deletion.
- **Profile:** Header, Social Metrics, Main Statistics, Memories, Lists, Insights and Settings are frozen. The frozen composition has Add Friend and Settings at the two top corners, no extra `我的` navigation title, `关注 / 粉丝` under the identity, and `去过 / 想去 / 总消费` in one statistic group. Core Entries alone remain `NEEDS REDESIGN`; a later candidate may change only that region.
- **Analytics (Best Companion, Recommendation Source, Monthly, Annual):** no candidate is approved. All composition regions remain pending redesign; the approved Taste Profile infographic family is the governing reference.
- **Taste Profile / Share Poster:** the Lafayette-provided 2:3 editorial infographic is the governing reference and is frozen as the structural target; the in-app analysis and 1080 × 1620 share output use the same real-data anatomy. Later optimization requires separate approval.
- **Share Posters (other four types):** no candidate is approved. All composition regions remain pending redesign; candidates remain 9:16 renderers with the canonical privacy/footer contract.
- **Premium Paywall:** all regions except the hamburger hero are frozen to the current FUSE composition. Only the hamburger hero remains pending redesign.

Candidate code, screenshots, recommendations, and approval-tool selections do not become formal product decisions until Lafayette explicitly approves the relevant region or page.

## Historical Mistakes — Do Not Regress

- Do not redesign product structure merely because another layout feels “more iOS.”
- Do not let Map and Discovery create separate filter systems.
- Do not use a GPS icon for a static city filter.
- Do not use Restaurant aggregate rating as Activity rating.
- Do not surface an unrated Visit as public Discovery evidence or replace its missing score; keep it in personal/history records and include it only in count-based Trend metrics.
- Do not regress Discovery recommendations into a generic `large image → text → equal pill actions` Restaurant card; the frozen Activity Card topology and rating semantics apply to all five Discovery tabs.
- Do not place quantity numbers, count circles or numeric badges on map markers. Do not hide distinct city/street Restaurant coordinates merely because their circles overlap. Wider-area grouping retains a real high-priority Restaurant image, and every exact-coordinate member remains reachable through a real stack/list. Never use decorative substitute-food aggregates.
- Do not move an individual Restaurant to avoid visual overlap. Its actual visible circle center must match the map projection of its coordinate during and after pinch, pan, selection and reuse. Keep the Native 44-point root frame fixed and scale only the centered visual. Wider-area grouping and exact-coordinate stacks never authorize free-slot offsets or bottom-anchored circles.
- Do not let Marker overlap order drift from `selected → rating → visit count → stable Restaurant ID`.
- Do not maintain multiple Restaurant Detail bodies.
- Do not fill a missing displayed Restaurant phone, opening-hours, price, rating, category or image field with fixture, placeholder or inferred merchant data; show the canonical no-data state. Website data remains Provider-backed but is not rendered in Restaurant Detail.
- Do not auto-load Rich Demo Restaurants in Release or a normal Debug launch. Fixtures require an explicit isolated test mode.
- Do not promote manual link pasting as Add Restaurant's main entry.
- Do not use a successful fresh location as a reason to add a redundant `当前位置已更新`/precision/GPS-sorting notice above or below Nearby results.
- Do not use city center, map camera center, or stale coordinates as Nearby GPS.
- Do not treat the first Core Location update or full-accuracy permission as proof that a fix is precise; a coarse first update must never become the Nearby query center while a better update is still arriving.
- Do not use only natural-language provider ranking for Nearby; it must be merged with coordinate-centered food/dining POIs before distance sorting so prominent Restaurants cannot crowd out closer small shops.
- Do not render system emoji as formal Food/Dining artwork.
- Do not let Food/Dining fallback cover an available lawful real Restaurant image.
- Do not let Restaurant-facing pages invent independent image-source resolvers instead of the canonical policy and renderer.
- Do not replace the approved compact Profile Premium badge. Do not promote a Paywall hamburger redesign candidate before Lafayette approves it.
- Do not treat “the function exists” as Product Parity PASS.
- Do not patch one instance of a repeated UI problem without globally searching and correcting the shared pattern.
- Do not add a page-local component when a shared component or canonical template already owns the behavior.
- Do not let pages independently choose radius, chip, tab, card, icon, Restaurant image, or empty-state styles.
- Do not reintroduce stable Core UI measurements as page-local magic numbers when `TasteMapDesignTokens` owns the same concept.
- Do not use Core UI components as permission to freely rearrange a Canonical Page Template.
- Do not leave a newly confirmed long-term design decision only in chat or a temporary acceptance report; update this document.
- Do not declare a global correction complete after fixing only the screenshot that exposed it; inventory and verify every same-semantic shipping consumer.
- Do not treat React source, `dist`, or the internal Capacitor shell as proof of what the formal Taste Map Xcode target ships. Stage, compare, build, install, launch, and inspect the actual formal app artifact.

## Design System Acceptance

Final Product Acceptance must report:

- Core UI System: PASS/FAIL;
- Food & Dining Visual System: PASS/FAIL;
- Canonical Page Templates: PASS/FAIL;
- duplicate/conflicting component count;
- default-SwiftUI visual regression count;
- remaining design-system gaps.

Acceptance checks information architecture, section order, control position and visual weight, image placement, horizontal/vertical relationships, spacing, information density, accessibility, and shared-component reuse. When a Web or approved historical reference exists, compare it directly to the iOS result; structural disagreement is not PASS. Automated tests, builds, snapshots, and an earlier compliance report cannot by themselves declare visual Product Acceptance PASS.

## 2026-09-01 Final Rule Reconciliation Record

The historical “全局 Product / UI Design System 最终统一指令” contained 27 numbered rule groups. Reconciliation against this document, the Legacy Fusion decisions, current confirmed capabilities, and the latest Lafayette overrides produced:

| Result | Count | Meaning |
| --- | ---: | --- |
| Already present | 24 | The active rule already existed here; no duplicate rule was added. |
| Newly supplemented | 1 | Restaurant image priority now also mandates convergence on one canonical renderer/presentation layer. |
| Superseded | 1 | The older default-offset rule was first replaced by natural overlap, followed by the 2026-09-04 free-slot experiment; the 2026-09-05 geographic-anchor override below supersedes all free-slot displacement. |
| Conflicted with the current rule | 1 | The historical five-level Source of Truth order was replaced by the final seven-level order above. |

This reconciliation did not rerun Product UX Tasks 01–14, redesign pages, or authorize business-code changes. The active rules are the consolidated text above, not the historical attachment or its task-shaped implementation instructions.

### 2026-09-05 Restaurant Images Without Numbers and Fixed Marker Anchor Override

**Latest overnight far-distance and rejected-layout clarification:** The size figures below describe the near/approved regional baseline through `2.4°` latitude span. Beyond that span, both engines continuously shrink the centered Restaurant visual using `p = clamp(log(span / 2.4) / log(80 / 2.4), 0, 1)`. Native visited inner diameter interpolates 24→10 points (outer white-ring diameter 28→14); Browser CSS border-box diameter interpolates 32→14 px with its existing white separation ring unchanged. Pending emphasis tapers 4→1 point, and selection emphasis tapers to 1 point, without changing the fixed 44-point anchor/hit box or geographic coordinates. Returning to the approved regional view restores its original size. These visual dimensions never drive grouping thresholds. The rejected 35 m / 24 px nearby five-image flower experiment is not a product rule: different coordinates remain independently projected and may overlap naturally, not placed in fixed slots. Only exact-coordinate members may use the small real-image stack below. Overall city-density visual approval remains a separate user-review gate.

**Later same-day pending-destination emphasis:** `想吃 / 推荐` Restaurant circles add the same restrained 4-point diameter emphasis over the visited baseline at every zoom. Native unselected inner circles are 28–32 points (32–36 including the unchanged white ring); selected outer circles remain at most 40 points within the fixed 44-point annotation frame. Browser CSS border-box sizes remain 32/36 px for visited normal/selected and become 36/40 px for pending normal/selected, with the existing outer white ring unchanged and one fixed 44 px anchor box. Real same-coordinate back members use their own status's same shared sizing and dashed/solid shell. Distance remains metadata and never shrinks a pending destination back below this emphasis; absent GPS does not change its size. This additive override supersedes the earlier all-status size limit, not visited sizing, source coordinates, grouping, imagery or page chrome.

**Pure-pan compositor contract:** The canonical score/rank/visit/ID order must be supplied to MapKit through distinct `zPriority` values, with a separate selected priority and the current-user location above Restaurants. Do not rely on root `CALayer.zPosition` assignments: MapKit rewrites those while recompositing annotations. Only the content-local back layers of a true same-coordinate composite own manual z positions. Runtime regression compares real member/image-generation identity and the actual rendered front-to-back order through repeated forward/back pans. A pure pan never promotes another Restaurant, changes a stack's leading image or regenerates its source selection.

Lafayette's latest map correction requires Restaurant circles to remain fixed to their real geographic coordinates and limits the complete visible circle, including its white ring, to roughly twice an ordinary nearby POI icon. Native MapKit's visited unselected inner diameter changes continuously from 28 points nearby to 24 points far away; the existing 2-point white ring on each side produces a 28–32-point outer diameter. Selection adds only 2–4 points to the inner diameter while remaining centered. Browser uses shared overall sizes of 32 px normal and 36 px selected on both mobile and desktop, without continuous diameter scaling. Rating/dashed ring semantics, the neutral hairline and imagery remain unchanged; shadow strength is reduced to avoid enlarging the marker's perceived footprint.

Lafayette's final explicit correction supersedes the intermediate quantity-cluster and 50 m proximity-stack proposals: show Restaurants, with no quantity numbers, count circles or numeric stack badges. Browser and Native MapKit retain every distinct Restaurant coordinate as a naturally overlapping image marker through city/street scale (`≤0.8°` latitude span). Only strict latitude/longitude matches share a stack/list. Wider-area grouping begins above `0.8°` and reaches its full collision radius at `2.4°`, retaining the highest-priority real member's own image and coordinate. Tap zooms toward member locations; an exact-coordinate stack opens the complete real Restaurant list using `此处` wording. The app never infers a mall identity from proximity alone.

Every group retains all original Restaurant IDs and coordinates. A deterministic member supplies the source-coordinate anchor and Restaurant visual. Higher scores appear in front: personal ordering uses rating → visit count → stable ID; recommendation rank only breaks equal-rating ties. Selection remains a temporary foreground override without changing the wider-area representative. Zooming in and out reversibly splits and groups the same data. These thresholds are scale controls, not administrative-boundary data; primary scope totals remain separate from marker presentation.

An exact-coordinate stack must visibly contain real member visuals, not a front Restaurant over empty decorative outlines. Show the highest-priority member in front plus at most two actual member-image/fallback layers behind it, while the complete membership remains available in the list. The front circle alone anchors the exact geographic point. Back layers use fixed local visual offsets `(-10, -8)` and `(8, -10)` inside that one stack; these are not changes to any Restaurant coordinate or collision-avoidance offsets between independent markers. Every layer uses its own Restaurant's canonical visual descriptor and rating ring, never a copied leader image or invented merchant photo. No layer displays a quantity number.

A pure pan preserves the filtered snapshot, member identities, images, group membership and layer order. Native keeps its `44 × 44pt` annotation/hit frame fixed and scales only the centered inner circle. Runtime acceptance measures the actual visible circle center and outer diameter, not the unchanged root-frame size, and compares the visible center to the map projection across zoom and pan. This final rule supersedes the 2026-09-04 free-slot experiment and the intermediate 2026-09-05 quantity-cluster and proximity-stack revisions. Do not regress: no quantity numbers or numeric badges on markers, city proximity hiding, collision-avoidance offsets, bottom-anchored circles, random jitter, spiderfy, inaccessible same-coordinate members or decorative cluster substitutes.


## 2026-09-07 Referral Premium Reward

**2026-09-08 registration-form layout correction:** Invite-code entry uses a
separate label, full-width input (at least 16px text), helper copy and a full-width
44px primary action. No inline label/input/button crowding. Blank and pending
submissions are disabled and success/failure is visibly announced. Retain the
existing Settings hierarchy and authoritative referral/registration boundaries.

Lafayette's referral rule adds one Settings entry after Membership Benefits: 邀请好友. It is a Settings detail, not a StoreKit product, paywall plan, fourth tab or redesigned Premium benefit set. Reuse HybridPageHeader/HybridEntryRow and the existing native-density Settings template. Food imagery is not applicable.

Attribution is accepted only during verified new-account registration, to one Taste Map referrer userID. The first server-saved valid, nondeleted Visit to a nondeleted, non-test, same-owner Restaurant qualifies it; rating and public visibility are not prerequisites. A referrer has five lifetime qualified slots, including subsequently revoked slots. Each qualification awards 30 days to the inviter and one-time 14 days to the invitee. A sixth qualifying attempt is capped and awards neither side.

Server ledger and authoritative Premium service alone decide access. Active Apple subscriptions queue new rewards; no StoreKit date/product mutation is permitted. Gift/Reward coverage extends through independent contiguous reward intervals. Lifetime-at-grant records retain invitation counts without adding duration. All attribution, qualification, cap, grant, activation, rescheduling and revocation transitions are audited. Revocations retain attribution/slot history.

Do Not Regress: no client-side Premium grant, device-bound reward, late attribution endpoint, duplicate rewards, restore overwrite, Apple renewal-date fabrication, public Admin entry or new StoreKit SKU. Detail shows code/link, X/5, earned/pending days and records; actual sharing uses the system share capability. Existing users do not bind a new referrer at sign-in. Production Universal Link validation requires the final domain and signed Associated Domains configuration, not only a Simulator build.

### 2026-09-08 — Premium discoverability for free accounts

Lafayette requires Premium feature entries to remain visible for nonmembers, with a lock and a working membership explanation action. Do not hide a feature merely because access is denied or still loading. This includes analysis/data/poster entries, recommendation-source failure analysis (最坑推荐来源), source/companion/exact-recommender filters, same-taste discovery and rating, custom avatar and restricted photo upload. Protected numbers, counts, analysis results and upload pickers must not leak through the locked entry. Existing user records are not deleted when membership expires. Daily free roulette remains usable once; its subsequent action remains visible and locked.

Use shared PremiumFeatureLabel / PremiumAccess / FilterChoiceGroup for React and the native inline entitlement badge for rollback consumers. Premium opens above its caller as a temporary child layer; keep the originating filter/form mounted, including selected conditions, expanded choices, draft and scroll position. Back closes only Premium and reveals that exact caller, never a hard-coded main page. This supersedes the earlier implementation that dismissed the filter to expose the paywall. The shared PremiumReturnLayer owns Hybrid presentation, modality and Escape containment; Browser and Native paywalls retain their caller via their existing modal/sheet presentation. Recording a dish's name, taste, price and rating stays free: keep 添加菜品 immediately after 本次照片; only its photo action is Premium. Scrollable editor grid rows must preserve intrinsic content height, never collapse overflow-hidden dish sections.

Do Not Regress: visible locked entry is not permission to render paid results. Do not remove free record editing, hide entire feature groups, or silently consume a roulette allowance while entitlement is loading.

### 2026-09-08 — Premium subscription purchase visibility

For the reported missing purchase actions/prices, place Monthly/Annual subscription actions before the long benefits/comparison content in shared React and Native rollback paywalls. Preserve the existing hero, trial, entitlement and return-layer semantics. Product metadata comes from StoreKit independently of Taste Map authentication; display Product.displayPrice and never substitute hardcoded CNY prices when another storefront or an error is returned. Loading/empty states retain an explicit explanation and retry action. Core spacing and minimum touch targets apply; keep plan name/renewal text distinct from price. Existing legacy Browser paywall keeps its plan-first flow. Do Not Regress: no dev.* StoreKit fixture attached to the formal TasteMap Run scheme, no fabricated prices or paid entitlement, and no purchase before authenticated server readiness.


## 2026-09-08 — First TestFlight Referral visibility hold
Lafayette defers the real two-account Referral E2E to internal beta follow-up. The first TestFlight hides Settings invitation entry and rejects direct invitation routes/registration preparation in Browser, Hybrid and Native rollback. Reuse the existing signed ProductionEnvironment.json product configuration, referralAvailable=false, without Debug/URL/local-storage overrides. Worker independently blocks invitation landing/dashboard and new-registration referral attribution; existing entitlements, qualification/settlement implementation, admin permissions, Offer mappings and inventory remain retained. No unverified invitation allocation or code consumption. This is release product visibility, not a new remote flag platform; reopening requires a reviewed config/build/deploy after real E2E PASS.
Core UI Settings rows and existing unavailable state remain canonical; Food/Dining visuals and page templates are unchanged. Do Not Regress: all entry paths, native bridge, stale saved invite code and server attribution must remain closed together. Normal StoreKit evidence remains PASS. Referral E2E is non-blocking only while this closure is effective. Real core smoke and visual/map approval still precede any HYBRID_PRIMARY cutover.

- **2026-09-08 Discovery current-city default (Lafayette):** Discovery's five tabs
  default to the city reverse-geocoded from the current authorized location.
  An empty Profile city must not prevent filter Apply. Manual city selection wins
  over late location results; changing tabs retains that selection. Unavailable
  location may retain the existing resolved browsing city or allow manual input,
  but must never be described as a successful current-position fix. Default For
  You and Map recommendations consume the same canonical snapshot; explicit
  city/filter/sort queries remain independent full server queries. Validation
  feedback stays beside the shared sticky Apply controls. No privacy change to
  Latest or owner history is implied. Do Not Regress: empty profile, location
  failure, delayed location after manual selection, reset and account switch.

- **2026-09-08 homepage/footprint visibility linkage (Lafayette confirmed):**
  Settings' 仅自己 / 好友 / 公开 controls the owner's homepage, historical and new
  Visits in 味觉足迹, and attached Visit/Dish photos together. Lafayette explicitly
  authorized applying the current public setting to the existing24 Visits and
  their attached content. Supersedes independent Visit visibility controls and
  copy saying homepage changes exclude Visits. Keep List visibility separate.
  Synchronize legacy Visit/Photo visibility fields through the ordinary owner-scoped
  mutation queue; never move records between owners, change ratings/notes/times,
  or relax another viewer's profile/friendship/block/photo authorization. Latest
  includes one's own qualified public Visits; existing score/city filters remain.
  Do Not Regress: all three settings, historical records, attached photos,
  repeated reconciliation, another owner, tombstones, offline/pending sync,
  profile downgrade and public-photo permission checks.

### 2026-09-08 — Ordinary launch and retained share drafts

Ordinary cold launch defaults to Map. A newly received external share may open Add Restaurant once; presentation is distinct from saving/consuming the draft. An already presented unsaved share must not repeatedly redirect subsequent launches. Keep its payload available through Add Restaurant until saved or expired. Explicitly sharing it again may present it again. Do not delete user Restaurant/Visit data to repair startup routing.

### 2026-09-08 — Discovery failure presentation and provider labels

Provider enum identifiers such as MKPOICategoryRestaurant are not product copy. Translate known category metadata, retain actual cuisine tags and omit unknown provider enum identifiers. Discovery displays one current-scope failure; cached results are labelled as cached, query failures never become empty-results success. Avoid a repeated global/per-tab/pagination error stack. Automatic failed refreshes back off, while explicit retry remains available.

### 2026-09-10 — Personal Restaurant aggregate precision

Raw Visit ratings remain 0.5–5 stars in half-star steps; the visit input and stored
history are unchanged. A personal Restaurant aggregate uses eligible same-owner,
nondeleted rated Visits: retain the precise five-star mean, multiply by two, and
round only the final ten-point output to one decimal (positive half-up). Natural
8.7 / 8.8 / 9.1 / 9.3 values are valid. Browser summary, Restaurant Detail personal
rating and Native Hybrid DTO must share these semantics. Keep exact mean inputs
for existing precise sorting; do not change liked thresholds or recommendation
meaning. Community/friend/similar-user aggregates retain their independent cohort,
visibility, sample and weighting contracts. Activity badges describe the concrete
Visit, never the Restaurant aggregate.

Do Not Regress: no intermediate five-star rounding, arbitrary fractional raw
Visit scores, aggregate overrides for screenshots, historical data rewrites or
schema changes to achieve display precision. Shared Core rating components and
canonical page composition remain unchanged; Food/Dining visuals are unaffected.
### 2026-09-10 — Formal Hybrid UGC safety contract

- Public Activity and Recommendation images expose a discoverable `…` safety action in the identity/header area, never a fourth Restaurant footer action. The established Social 3 + Restaurant 3 composition is unchanged.
- The displayed photo's resolved descriptor determines its reportable Visit, including image fallback changes; do not report a different candidate photo or a restaurant's personal avatar.
- Comment `…` exposes report/block for others, delete for the owner. Eligibility is a service projection, not a React owner-ID inference. Failure is visible; deletion hides immediately, restores on failure, and uses the existing server tombstone.
- Block acts on Taste Map users, not device contacts. It filters the current viewer's content and derived caches without deleting anyone's original content. Auth changes clear local presentation state and fence late results.
- The shared safety dialog uses the existing moderation categories and backend. Settings → Help retains the official support URL. This does not redesign social profiles or replace the existing Native social capability.
