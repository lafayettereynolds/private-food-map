# Taste Map Product Design Rules

This document is the canonical, long-lived product and visual contract for Taste Map. A page is not parity-complete merely because a related feature exists or a SwiftUI screen opens. All UI/UX work must read this file before implementation and keep it synchronized when Lafayette confirms a new durable decision.

## Source of Truth

When sources differ, use this priority order:

1. Lafayette's latest explicit design or product override.
2. This document.
3. The confirmed production Web or previously approved historical/TestFlight design.
4. The current production Web feature semantics and data behavior.
5. The current iOS implementation.

Before changing layout, establish the Web feature semantics, data source, entry point, states, permissions, and return path. Fix a semantic migration bug before restoring its presentation. The current iOS implementation may supply working code, but it does not become the layout source of truth merely because it is native SwiftUI.

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

This is the brand layer that makes Taste Map recognizably about food, restaurants, dining memories, and social meals. Use the shared `FoodDiningVisualLibrary` (or its formal successor), never page-specific unrelated art styles.

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

### Layer 3 — Canonical Page Templates

Templates define information architecture, section order, control and image placement, interaction hierarchy, content density, and component composition. Core components are not permission to freely rearrange an already approved product page.

#### 1. My Map / My List Template

- top breathing space;
- centered `我的地图` / `我的列表` plus the adjacent clickable view-switch icon as one group;
- `去过 / 想吃 / 推荐` using the shared primary tab bar;
- shared compact horizontal FilterBar;
- Map or List content backed by the same query/filter/sort state;
- independent Restaurant markers at every zoom, with overlap handling rather than numeric clusters;
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

## Food & Dining Visual Language

Use `FoodDiningVisualLibrary` and `FoodDiningVisualIcon` for a consistent dining vocabulary: food, drinks, tableware, receipts, menus, takeaway, and shared meals.

- Default use is `decorative`; it adds character without claiming a preference.
- `dataLinked` is allowed only when a real cuisine, spend, companion, time, or other value selects the visual.
- Formal UI never renders system emoji as the product artwork.
- Food/Dining artwork may use restrained natural food colors and must not be uniformly dyed brand blue.
- Stable scenes use a stable seed so decorative choices do not jump on every render.
- The approved historical Premium hamburger is separate and must not be replaced by this library.

## Shared Components

Shared implementations are the default. Maintain or converge on repository-wide equivalents of `TasteMapTopBar`, `TasteMapFilterBar`, `TasteMapFilterChip`, `TasteMapIconActionRow`, `TasteMapRestaurantImage`, `TasteMapRatingReference`, `TasteMapInfoGroup`, `TasteMapEmptyState`, `TasteMapActivityCard`, and `RestaurantDetailStandardBody`.

Changing one of these patterns requires checking every consumer. Map and Discovery do not get separate filter languages; activity surfaces do not get separate cards; entry sources do not get separate Restaurant Details; Restaurant image fallback policy does not diverge by page.

### Filters

All compact product filters use `TasteMapFilterBar`, `TasteMapFilterChip`, and `TasteMapFilterSemantic`.

- One horizontal scrolling row, 8-point spacing, 34-point visible pills, minimum 44-point hit targets.
- Every primary chip has a semantic icon plus short text/value.
- Active state, count badge, press feedback, Dark/Light behavior, and VoiceOver behavior are shared.
- A dimension chip opens only its own control. Rating opens rating; price opens price; visit count opens visit count; companion opens companion; city opens city.
- Only the leading Filters/More chip may open the complete filter sheet.

### Primary Tabs

My Map's three scopes and Discovery's five scopes use `TasteMapPrimaryTabBar`: equal distribution, the same typography, a two-point selected indicator, and a 44-point hit target.

### Activity and Discovery Cards

One card language must preserve: author/avatar/time, Restaurant image/name/address, the author's Visit/Activity rating, social actions, Restaurant actions, and separate sharing. Restaurant aggregate rating must never substitute for a missing Activity rating.

### Restaurant Actions

Restaurant action rows are compact and semantic. Record, Want to Go, add to list, roulette, directions, phone, and share do not become a wall of equal-weight pills or large cards.

### Empty States

Use `TasteMapEmptyState`. A relevant Food/Dining visual may be supplied as decorative artwork; its message and action still describe the actual state. Loading, empty, insufficient sample, authentication, permission, and network failure are distinct states.

### Restaurant Detail

`RestaurantDetailView` and `RestaurantDetailStandardBody` are the only Restaurant Detail body. Entry source may change dismissal, analytics, and permissions, never the core information architecture.

## My Map

- Centered `我的地图` or `我的列表` title with the adjacent view-switch icon.
- Primary scopes are `去过 / 想吃 / 推荐`.
- No separate Map/List segmented row.
- Map/List switching preserves scope, filters, sort, city, and search.
- Filters use the shared components.
- Every Restaurant remains an independent marker at every zoom; no numeric clusters.
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

Use the previously approved historical hamburger asset everywhere Premium identity appears. Do not replace it, use fake prices, or use emoji food rows in the formal Premium hero.

## Historical Mistakes — Do Not Regress

- Do not redesign product structure merely because another layout feels “more iOS.”
- Do not let Map and Discovery create separate filter systems.
- Do not use a GPS icon for a static city filter.
- Do not use Restaurant aggregate rating as Activity rating.
- Do not maintain multiple Restaurant Detail bodies.
- Do not promote manual link pasting as Add Restaurant's main entry.
- Do not use city center, map camera center, or stale coordinates as Nearby GPS.
- Do not render system emoji as formal Food/Dining artwork.
- Do not replace the approved Premium hamburger.
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

Acceptance checks information architecture, section order, control position and visual weight, image placement, horizontal/vertical relationships, spacing, information density, accessibility, and shared-component reuse. When a Web or approved historical reference exists, compare it directly to the iOS result; structural disagreement is not PASS.
