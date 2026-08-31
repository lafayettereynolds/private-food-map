# Taste Map Product Design Rules

This document is the canonical product and visual contract for Taste Map. A page is not parity-complete merely because a related feature exists or a SwiftUI screen opens.

## Source of Truth

When sources differ, use this priority order:

1. Lafayette's latest explicit design or product override.
2. The current production Web product and its confirmed mobile screenshots.
3. A previously approved TestFlight/history asset or implementation.
4. The current iOS implementation.

Before changing layout, establish the Web feature semantics, data source, entry point, states, and return path. Fix a semantic migration bug before restoring its presentation.

## Theme Boundaries

- `TasteMapCoreTheme` is the Core App system: cool white, low-saturation blue-grey, restrained borders and shadows, and native interaction behavior.
- `TasteMapAnalysisTheme` is reserved for Analytics and share posters: warm paper surfaces, a central Food Hero, callouts, receipt/tape details, and stronger food storytelling.
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
