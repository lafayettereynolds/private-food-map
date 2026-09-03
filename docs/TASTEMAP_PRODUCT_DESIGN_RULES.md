# Taste Map Product Design Rules

This document is the canonical, long-lived product and visual contract for Taste Map. A page is not parity-complete merely because a related feature exists or a SwiftUI screen opens. All UI/UX work must read this file before implementation and keep it synchronized when Lafayette confirms a new durable decision.

## Source of Truth

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
| `reports/FULL_PRODUCT_PARITY_MODULE_8_REMAINING_CORE.md` and earlier map reports | far-zoom Food/Dining or numeric Restaurant clusters | every Restaurant remains independent at every zoom; no cluster/count aggregate |
| `reports/TASK_09_ACCESSIBILITY_DARK_MODE_LOCALE.md`, `reports/TASK_10_PERFORMANCE_MEMORY_LARGE_DATASET.md`, and the initial Legacy audit wording | default slight offset, collision dispersion, spiderfy, or zoom-driven separation as the normal layout | markers may overlap naturally; no default forced offset/spiderfy; optional expansion is user initiated only |
| Earlier Map/List parity reports | `适合你`, a separate segmented row, or a floating Map/List switch | `去过 / 想吃 / 推荐` plus the centered `我的地图 / 我的列表` title-and-icon switch |
| Legacy raw emoji marker/customizer references | raw emoji as formal Restaurant or Food/Dining artwork | real Restaurant image first; otherwise the formal `FoodDiningVisualLibrary` fallback |
| Source-specific Restaurant Detail reports or implementations | separate Map/Discover/Friend/Recommendation detail bodies | one `RestaurantDetailView` / `RestaurantDetailStandardBody` |
| Earlier Analytics dashboard acceptance | ordinary card dashboard or page screenshot treated as the approved analysis/poster experience | poster-like infographic pages and dedicated native share posters |
| Earlier Activity-card projections | Restaurant aggregate rating used when an Activity rating is absent | the author's specific Visit/Activity rating; nil is `未评分` |
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

#### Restaurant image priority

Every Restaurant-facing surface—Nearby, Search, Map, List, Discovery, Community, Restaurant Detail, Lists, Roulette, Analytics, and share posters—uses this priority:

1. the user's real uploaded/recorded Restaurant photo;
2. a lawful public or cached Restaurant photo;
3. a lawful provider Merchant image;
4. `FoodDiningVisualLibrary` only when no real Restaurant image is available.

Food/Dining art must never cover a real image that the product can legitimately render. If a provider has no lawful image, fall back honestly rather than fabricating merchant imagery.

`RestaurantImagePriorityPolicy` is the canonical **data-selection policy**. All Restaurant-facing presentation must progressively converge on one canonical renderer/presentation layer—`TasteMapRestaurantImage` or its formal successor—that consumes the policy result. Map, List, Nearby, Search, Discovery, Community, Restaurant Detail, Lists, Roulette, Analytics, and Posters may choose different approved aspect ratios or compositions, but they may not implement separate source-priority or fallback logic.

A page-local URL resolver, photo lookup, provider branch, or fallback is temporary migration debt, not a new standard. Changing the policy or renderer requires a global consumer audit and contract coverage for local photo, public/cache photo, lawful provider image, revoked/deleted image, and honest fallback states.

### Layer 3 — Canonical Page Templates

Templates define information architecture, section order, control and image placement, interaction hierarchy, content density, and component composition. Core components are not permission to freely rearrange an already approved product page.

#### Root App Shell Contract

- The formal bottom navigation is exactly `地图 / 发现 / 我的`, in that order, with exactly three items.
- `Add Restaurant` is a routable product surface, but route availability never implies bottom-navigation membership.
- The single formal Add Restaurant entry is the Map-owned floating `添加餐厅` primary CTA. It must not be duplicated as a fourth bottom tab, page-wide tab, or competing primary action.
- Shared Browser and Capacitor rendering does not make a shell topology correct by itself. Any root navigation change must pass the exact Product Contract before cross-platform and visual parity can pass.
- Product Contract, One React UI, Current Capability Preservation, Browser ↔ Capacitor parity, Lafayette Reference parity, Function/Semantic, and Negative Contract are independent gates; no gate substitutes for another.
- A capability still implemented in Native remains visible in Hybrid through a typed Native handoff. `readOnly`, migration status, or a missing React write implementation must not silently remove Record Visit, Edit Visit, Photo/Camera, List mutation, Premium purchase/restore, Backup/Import, Sync, Account, or Share entries.
- React renders ownership-sensitive actions only from Native capability DTOs. It must not infer `canEdit`, `canDelete`, `canRecord`, `canAddToList`, report or block permission from a user-ID comparison or UI state.

#### 1. My Map / My List Template

- One React UI governs the shared product chrome, not the map engine: Browser uses its formal Web provider; iOS Hybrid embeds the established Native MapKit / `MKMapView` surface in the persistent shell.
- React owns Header, title switch, scopes, FilterBar, Add Restaurant CTA, selected-card/detail navigation, and bottom navigation. Native MapKit owns tiles, pan/pinch, viewport, Restaurant annotations, selection, CLLocation/user-avatar annotation, and map performance.
- The React ↔ MapKit contract is minimal and typed: filtered presentation markers/state flow Native; viewport and selected Restaurant flow back. JavaScript receives neither credentials nor SwiftData/write authority.
- AMap Web key or `securityJsCode` availability is never an iOS Map or Release blocker. A static Web fallback is never accepted as the iOS map.

- top breathing space;
- centered `我的地图` / `我的列表` plus the adjacent clickable view-switch icon as one group;
- `去过 / 想吃 / 推荐` using the shared primary tab bar;
- each scope uses one semantic line icon plus its text (`去过` = footprints/check, `想吃` = bookmark, `推荐` = star); the three items share icon size, baseline, spacing, selected treatment, and a minimum 44-point hit target;
- scope selection feedback is committed immediately and never waits for data, images, a Native bridge response, or map work;
- shared compact horizontal FilterBar;
- Map or List content backed by the same query/filter/sort state;
- switching scope preserves the mounted map identity, center, zoom, bounds, selected viewport and Map/List state; it must not recreate the map or trigger camera fitting merely because the scope changed;
- content may update asynchronously from an owner-scoped, versioned, bounded presentation snapshot; Native/SwiftData remains the source of truth, stale responses are rejected, and the cache is invalidated by owner/data changes;
- markers reconcile by stable Restaurant ID and reuse unchanged marker/image identity rather than performing a full teardown; image loading never blocks selected-state feedback and cached Restaurant images do not reload solely because the scope changed;
- independent Restaurant markers at every zoom, with natural overlap and deterministic layer order rather than numeric clusters;
- no default forced offset, spiderfy, collision dispersion, zoom-driven separation, or “coin wall” whose purpose is to expose every marker;
- marker layer order is `selected → rating → visit count → stable Restaurant ID`; pan and zoom must not randomize it;
- optional expand/spiderfy is allowed only after the user explicitly asks to inspect a highly overlapped area;
- Add Restaurant CTA in its approved non-overlapping position.

#### 2. Discovery Template

- centered `发现` title;
- equal primary tabs `关注 / 为你推荐 / 同味之选 / 最新 / 趋势`;
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

- compact avatar/name/joined/edit/Premium header;
- following and followers;
- `去过 / 想去 / 总消费` using their formal calculation semantics;
- paired `今天吃什么 / 我的口味档案`;
- one Memories group for `本月回顾 / 年度回顾 / 那年今日`;
- independent Lists section;
- paired `最佳饭搭子 / 谁最会种草` Insights;
- data and settings as a secondary later section.

#### 5. Activity Card Template

Discovery, Community, Latest, Trending, and similar activity surfaces share author/avatar/time/visibility, Restaurant image/name/address/context, the author's Activity rating, social actions, Restaurant actions, and separate sharing. These actions retain the approved grouping and visual weights instead of becoming one wall of identical pills.

#### 6. Add Restaurant Template

Formal flow: Search, Nearby, external Share ingestion, and one Manual Add card for places absent from map providers. A selected result first shows the standard Restaurant Detail foundation, then offers Want to Go or Record Visit. Manual link paste is not promoted to a primary in-app section; parsing remains available to the Share Extension.

#### 7. Roulette Template

The selected unique candidate pool, image/name chips, wheel segments, and result are the same data. Unfilled segments say `+ 添加更多餐厅`; do not duplicate Restaurants or present placeholders as real candidates. Random selection is uniform unless Lafayette explicitly approves weighting.

#### 8. Analytics / Poster Template

Taste Profile, Best Companion, Recommendation Source, Monthly, and Annual belong to one Analysis design family: warm/off-white paper, central Food Hero, infographic composition, connecting callouts, Restaurant imagery, food/dining storytelling, receipt/tape restraint, branded poster footer, and QR. Their layouts may vary with data semantics, but must not regress to ordinary card dashboards. Analysis pages provide one `生成分享海报` action; share/save belong in Poster Preview.

## Theme Boundaries

- `TasteMapCoreTheme` implements the Layer 1 Core App system.
- `TasteMapAnalysisTheme` implements the Layer 3 Analytics/Poster template with stronger Layer 2 Food/Dining storytelling.
- Analysis styling must not leak into Map, Settings, Restaurant Detail, or other Core App surfaces.

## Icon Semantics

- Every functional icon must describe a real action or value.
- A familiar system action may use an icon alone when it remains clear and has a VoiceOver label.
- Ambiguous data dimensions use icon plus a short label or current value.
- Siblings in one component group either all use semantic icons or all omit them.
- A static city filter uses a building/city symbol, never GPS, location, or current-position imagery.
- Decorative Food/Dining visuals are not functional icons and never imply data unless explicitly selected from real data.

## Shared Components

Shared implementations are the default. Maintain or converge on repository-wide equivalents of `TasteMapTopBar`, `TasteMapFilterBar`, `TasteMapFilterChip`, `TasteMapIconActionRow`, `TasteMapRestaurantImage`, `TasteMapRatingReference`, `TasteMapInfoGroup`, `TasteMapEmptyState`, `TasteMapActivityCard`, and `RestaurantDetailStandardBody`.

Changing one of these patterns requires checking every consumer. Map and Discovery do not get separate filter languages; activity surfaces do not get separate cards; entry sources do not get separate Restaurant Details; Restaurant image selection and fallback do not diverge by page. `RestaurantImagePriorityPolicy` plus the canonical Restaurant-image renderer owns that last decision.

### Filters

All compact product filters use `TasteMapFilterBar`, `TasteMapFilterChip`, and `TasteMapFilterSemantic`.

- One horizontal scrolling row, 8-point spacing, 34-point visible pills, minimum 44-point hit targets.
- Every primary chip has a semantic icon plus short text/value.
- Active state, count badge, press feedback, Dark/Light behavior, and VoiceOver behavior are shared.
- A dimension chip opens only its own control. Rating opens rating; price opens price; visit count opens visit count; companion opens companion; city opens city.
- Only the leading Filters/More chip may open the complete filter sheet.

### Primary Tabs

My Map's three scopes and Discovery's five scopes use `TasteMapPrimaryTabBar`: equal distribution, the same typography, a two-point selected indicator, and a 44-point hit target. My Map supplies semantic icon-plus-text items for every scope—never one isolated icon, raw emoji, or a FilterChip/pill treatment. Accessibility exposes each control's text and selected state; the decorative glyph itself stays hidden from assistive technology.

### Activity and Discovery Cards

One card language must preserve: author/avatar/time, Restaurant image/name/address, the author's Visit/Activity rating, social actions, Restaurant actions, and separate sharing. Restaurant aggregate rating must never substitute for a missing Activity rating.

### Restaurant Actions

Restaurant action rows are compact and semantic. Record, Want to Go, add to list, roulette, directions, phone, and share do not become a wall of equal-weight pills or large cards.

### Empty States

Use `TasteMapEmptyState`. A relevant Food/Dining visual may be supplied as decorative artwork; its message and action still describe the actual state. Loading, empty, insufficient sample, authentication, permission, and network failure are distinct states.

### Restaurant Detail

`RestaurantDetailView` and `RestaurantDetailStandardBody` are the only Restaurant Detail body. Entry source may change dismissal, analytics, and permissions, never the core information architecture.

## My Map

- Browser and iOS share the same product UI but deliberately use different map engines: Browser Web map provider; iOS Native MapKit. This is the only correct interpretation of One React UI for the map surface.

- The root App Shell contains exactly `地图 / 发现 / 我的`; `添加` is forbidden as a fourth bottom tab.
- `添加餐厅` appears exactly once as the Map-owned floating primary CTA and routes to the formal Add Restaurant flow.
- Centered `我的地图` or `我的列表` title with the adjacent view-switch icon.
- Primary scopes are `去过 / 想吃 / 推荐`.
- No separate Map/List segmented row.
- Map/List switching preserves scope, filters, sort, city, and search.
- Scope switching preserves map instance identity, center, zoom, bounds, filters, sort, search, and Map/List state. A scope value must not participate in the camera-fit identity.
- The selected scope updates on the next visual frame without waiting for projection, bridge, marker or image work. Scope data arrives asynchronously through a bounded, owner/version-keyed presentation snapshot; out-of-order responses cannot overwrite the newest selection.
- Marker updates use a stable-ID diff and retain unchanged marker/image identity. A scope change must not destroy/recreate every marker, reload cached Restaurant images, or rebuild the map.
- Filters use the shared components.
- Every Restaurant remains an independent marker at every zoom; no numeric or Food/Dining count clusters.
- Markers may overlap naturally. Ordinary rendering does not force offset, spiderfy, collision dispersion, zoom separation, or full visibility.
- Layering is deterministic: `selected → rating → visit count → stable Restaurant ID`.
- Selected is always topmost; higher-rated Restaurants cover lower-rated Restaurants; visit count breaks equal-rating ties; stable ID is the final tie-break.
- Pan/zoom cannot randomly change layer order. Expand/spiderfy may exist only as an explicit user action for inspecting a highly overlapped area.
- Current user location uses the user's circular avatar and a subtle halo, not Restaurant tableware.

## Discovery

- Centered `发现` title.
- Equal primary tabs: `关注 / 为你推荐 / 同味之选 / 最新 / 趋势`.
- Uses the same FilterBar, FilterChip, and icon semantics as My Map.
- Activity rating is the author's specific Visit rating. Nil is `未评分`.
- Similar Taste explicitly represents loading, content, empty/insufficient sample, authentication, and error states.

## Add Restaurant and Nearby

- Formal order: Search, Nearby, external Share ingestion, and one Manual Add card.
- Manual paste is not a primary in-app section; parsers remain available to the Share Extension.
- Nearby uses a fresh CLLocation after checking authorization, accuracy, timestamp, and horizontal accuracy. City center or map camera center can never impersonate GPS.
- Selection shows the standard Restaurant Detail foundation before Want to Go or Record Visit.
- Provider identity aids dedupe but is never the Taste Map primary key.

## Restaurant Detail

Canonical order: hero; city/status; name; address; compact actions; reference spend; phone; hours; directions; rating reference; my/all/friend/similar-taste ratings; user photos; my visit overview; visit history; dishes and detailed ratings.

Rating circles mean: large circle = score, small circle = sample count. Nil never renders as zero.

## Visit Editor

- The approved editor is one continuous, compact dining diary. Restaurant context, core experience, ratings, dishes/photos, dining context, notes, and the final save action remain in one readable flow.
- Optional choice dimensions are visible and directly tappable. They must not be hidden behind default disclosure/expand controls merely to shorten the page.
- The visual restoration does not change field optionality, nil semantics, persistence, offline mutation behavior, photo lifecycle, or save validation.
- The primary save action remains the current canonical save implementation; the Legacy reference governs layout density and information order, not data architecture.

## Profile and Lists

- Compact identity header with avatar, name, joined date, edit, Premium, following and followers.
- Top statistics are unique visited Restaurants, Want to Go Restaurants, and valid actual spend.
- Roulette and Taste Profile are paired; Monthly, Annual, and On This Day share one Memories section; Lists and Insights retain their own sections.
- Lists support real create/add/reorder/edit/remove/visibility/persistence behavior; decorative empty art never masquerades as list data.

## Roulette

Restore the approved Web/history wheel. Candidate chips and segments represent the same unique candidate pool; no copied Restaurants, placeholders presented as candidates, hidden weighting, or mismatched random pool. Empty segments say `+ 添加更多餐厅`.

## Analytics and Share Posters

- Analysis pages are scrollable poster-like infographics, not ordinary card dashboards.
- The center Food Hero is data-linked only when supported; otherwise it is clearly decorative.
- Taste Profile, Best Companion, Recommendation Source, Monthly, and Annual share one visual family while preserving independent semantics.
- The page has one `生成分享海报` action. Share/save live in Poster Preview.
- Every poster footer uses the official App Icon, Taste Map name, optional short tagline, and a high-contrast QR code from fail-closed Release configuration.

## Premium

The compact Premium identity badge used in Profile keeps the previously approved historical hamburger asset. The Paywall hero hamburger is a separate visual-approval region and is currently pending a Lafayette-approved redesign; no candidate may replace the formal Paywall hero before approval. Never use fake prices or emoji food rows in the formal Premium hero.

## Human Visual Approval Freeze Registry

Lafayette visual approval is region-based and convergent. A region marked KEEP is frozen; later candidate versions may change only regions marked `需要修改` or `重新设计`, unless Lafayette explicitly unfreezes a region.

- **Approval source:** `TasteMap-Lafayette-Visual-Approval.zip`, exported 2026-09-02. Its `approval.json` is the current machine-readable freeze registry; report text and earlier automated `Visual PASS` labels cannot override it.
- **My Map / My List:** approved title switch, scopes, filters, preview, add action and state behavior are frozen. Marker layout uses the Legacy natural-overlap base; rating-colored rings and the canonical real-image priority are required. Generated QA artwork may not masquerade as a provider merchant photo.
- **Discovery:** the approved Legacy-base/FUSE composition is frozen, including centered title, five primary tabs, shared FilterBar and Legacy activity-content geometry.
- **Add Restaurant / Nearby:** the Legacy-base Search, Nearby, Manual Add, results, preview, actions and transition are frozen; current Share ingestion remains frozen and current-only.
- **Restaurant Detail:** the global Legacy-base information architecture is frozen and continues to use the single current `RestaurantDetailStandardBody`.
- **Roulette:** the approved Legacy wheel, candidate management, result, imagery and state geometry are frozen while current selection semantics remain authoritative.
- **Visit Editor:** all regions approved. Legacy layout/density is frozen for restaurant context, core experience, ratings, dish/photo entry, dining context, and notes; the current canonical Save CTA is frozen.
- **Dish / Photo Manager:** all approved regions use the Legacy layout base while preserving current photo lifecycle and business semantics.
- **Public Profile / Social Hub:** Social Metrics, actions, content classification, Restaurant evidence, activity, public Lists and safety actions use the frozen Legacy base while preserving current Social, moderation, sharing, and data-isolation capability. The user-facing follower term is `粉丝`; primary content classification is `动态 / 食单`. Header machine choice is still blank and must not be auto-approved, even though a historical note says it was confirmed.
- **Lists / Public Lists:** all approved regions use the Legacy layout base while preserving current list models, visibility, sharing, and persistence.
- **Settings / Data:** the current native-density structure is approved and frozen.
- **Profile:** Header, Social Metrics, Main Statistics, Memories, Lists, Insights and Settings are frozen. The frozen composition has Add Friend and Settings at the two top corners, no extra `我的` navigation title, `关注 / 粉丝` under the identity, and `去过 / 想去 / 总消费` in one statistic group. Core Entries alone remain `NEEDS REDESIGN`; a later candidate may change only that region.
- **Analytics (Best Companion, Recommendation Source, Monthly, Annual):** no candidate is approved. All composition regions remain pending redesign; the approved Taste Profile infographic family is the governing reference.
- **Share Posters (five types):** no candidate is approved. All composition regions remain pending redesign; candidates must remain native 9:16 renderers with the canonical privacy/footer contract.
- **Premium Paywall:** all regions except the hamburger hero are frozen to the current FUSE composition. Only the hamburger hero remains pending redesign.

Candidate code, screenshots, recommendations, and approval-tool selections do not become formal product decisions until Lafayette explicitly approves the relevant region or page.

## Historical Mistakes — Do Not Regress

- Do not redesign product structure merely because another layout feels “more iOS.”
- Do not let Map and Discovery create separate filter systems.
- Do not use a GPS icon for a static city filter.
- Do not use Restaurant aggregate rating as Activity rating.
- Do not aggregate Restaurants into numeric or Food/Dining count clusters at any zoom.
- Do not force ordinary Marker offset, spiderfy, collision dispersion, or zoom separation merely to reveal every Restaurant.
- Do not let Marker overlap order drift from `selected → rating → visit count → stable Restaurant ID`.
- Do not maintain multiple Restaurant Detail bodies.
- Do not promote manual link pasting as Add Restaurant's main entry.
- Do not use city center, map camera center, or stale coordinates as Nearby GPS.
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
| Superseded | 1 | Default Marker offset/spiderfy/collision/zoom separation is replaced by natural overlap and explicit-user expansion only. |
| Conflicted with the current rule | 1 | The historical five-level Source of Truth order was replaced by the final seven-level order above. |

This reconciliation did not rerun Product UX Tasks 01–14, redesign pages, or authorize business-code changes. The active rules are the consolidated text above, not the historical attachment or its task-shaped implementation instructions.
