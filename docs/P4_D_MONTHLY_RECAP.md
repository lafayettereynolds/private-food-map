# P4-D Monthly Recap

This document records the product, time-boundary, analysis and privacy contract implemented by the native iOS P4-D feature. P4-D is a read-only, local-first analysis over existing SwiftData records. It adds no database column, sync entity, Worker route, signing change or Production dependency.

## Web baseline audit

| Monthly item | Web source and current rule | Fields used by Web | Native iOS data | P4-D decision | Insufficient-data behavior |
| --- | --- | --- | --- | --- | --- |
| Month grouping | `src/services/reviewService.ts` filters review dates using the selected natural month | review date | `Visit.visitedAt` is an instant; original entry timezone is not stored | Use one `MonthlyPeriod` with the user's current Calendar/timezone and a half-open `[start, end)` interval | Empty month is a natural empty state, not a zero-filled dashboard |
| Visit count | `reviewService.ts` counts month reviews | review ID/date | Complete | Count active, distinct Visit UUIDs | Zero when the month is empty |
| Restaurant count | `reviewService.ts` deduplicates restaurant references | restaurant ID | Complete Global Restaurant UUID | Count active Restaurant UUIDs referenced by active month Visits | Zero when empty |
| New Restaurant | Web compares the Restaurant's earliest review with the selected month | all review dates + restaurant ID | Complete | Earliest active Visit across all history must fall inside the target month | Show zero naturally; never reinterpret “first this month” as new |
| Spend | `reviewService.ts` sums recorded spend and reports coverage | actual spend | `Visit.myActualSpend` complete | Nil is excluded, never converted to zero; total, median and coverage are computed | Low coverage is explicitly “已记录”; the poster omits a weak spend claim |
| Favorite Restaurant | Web emphasizes a high-rated review and can over-weight one visit | rating, review date | Overall + detailed ratings and Dish ratings complete | Deterministic Restaurant-level evidence score combines average rating, repeated Visits and Dish-rating support | No favorite when there is no rating evidence |
| Most visited | Web groups reviews by restaurant | review count/rating/date | Complete | Visit count, then average rating, latest Visit and stable UUID | Omitted when empty |
| New Restaurant highlights | Web lists restaurants whose first review is in the month | first review, rating, photo | Complete | Up to three ranked new Restaurants | A compact “0 家新店” explanation replaces fake cards |
| Companion | Web profile monthly panels derive companion names from review records | companion name | Stable P2-F Companion IDs and Visit associations complete | Only formal active Visit associations count; multi-companion Visits count for each linked companion | Block is omitted when no association exists |
| Recommendation source | Web profile monthly panels use review source information | source type/text | Stable P2-F RecommendationSource identity complete | Attribute each distinct Restaurant to its earliest source-bearing Visit in the month; unresolved IDs do not fall back by text | Block is omitted when no formal source resolves |
| Taste change | Web compares broad monthly distributions but has loose thresholds | categories, tags, visits | Cuisine/tags/Dish/context complete | Compare only the immediately preceding natural month; require 3 Visits and 2 Restaurants on both sides and a material 20-point distribution/behavior shift | Show a gentle “记录更多后…” state and use factual keywords on the poster |
| Keywords | Web derives recap labels from categories/contexts | category, context | Complete | Deterministic frequency/order rules produce 2–5 cuisine, Dish, occasion and explore/repeat labels | No random or AI-generated filler |
| Representative Restaurants | Web recap selects highlighted cards | restaurant, photo, note | Restaurant/Visit/Dish/Photo complete | Deduplicated roles: favorite, most visited, new Restaurant and highlight, maximum four | Fewer real Restaurants means fewer cards |
| Monthly highlight | Web favors a high-rated item | rating/photo/date | Complete | Deterministic evidence order prefers rating, repeated evidence, relevant photo/recency and stable UUID | Omitted when no month Restaurant exists |
| Monthly share | `src/services/analysisShare.ts` and `analysisPosterRenderer.ts` render Web share output | recap projection | Native P4 renderer and share pipeline complete | Independent fixed 1080×1920 SwiftUI poster; never capture the reading page | Sparse layout removes unavailable blocks rather than inventing content |

The React/Web implementation remains unchanged and is a product-logic reference only. The native implementation deliberately corrects Restaurant-level favorite weighting, formal source identity and comparison sufficiency where the older Web implementation is weaker.

## `MonthlyPeriod` and timezone contract

`MonthlyPeriod` stores a year, month and Calendar. Its Calendar carries the user's current timezone. `start` is the Calendar start of day for day 1, and `end` is the start of the following month. Every monthly filter uses the same half-open interval:

```text
start <= visitedAt < end
```

The previous comparison period is always the immediately preceding natural month in the same Calendar/timezone. The implementation never silently crosses a missing month and still claims “比上个月”. Current-month copy says “截至今天” and the poster uses an explicit date such as “2026 年 8 月 · 截至 8 月 28 日”; completed historical months are labeled as historical/complete months.

P1-C currently stores `Visit.visitedAt` as an absolute instant and does not preserve the timezone in which the Visit was originally entered. Consequently, changing the device timezone can move a Visit close to midnight across a month boundary. P4-D applies the user's current Calendar/timezone consistently and documents this known model limit instead of mixing UTC and local rules.

## Metric and ranking definitions

- **Visit count:** active, deduplicated Visit UUIDs inside the selected period.
- **Restaurant count:** distinct active Taste Map Restaurant UUIDs referenced by those Visits.
- **New Restaurant:** the Restaurant's earliest active Visit across all available history is inside the selected period. A tombstoned earlier Visit does not block a later first valid Visit.
- **Recorded spend:** sum and median of non-nil `myActualSpend`. Coverage is the number of month Visits with spend divided by all month Visits. A 60% threshold controls prominence; partial data always retains “已记录” wording.
- **Favorite Restaurant:** among Restaurants with rating evidence, rank by `average Visit rating × 0.72 + bounded repeat evidence × 0.55 + repeat bonus × 0.30 + bounded Dish-rating support × 0.15`; ties use average rating, Visit count, latest Visit and stable UUID. Thus four 4.5-star Visits can outrank one isolated 5-star Visit.
- **Most visited Restaurant:** Visit count, average rating, latest Visit and stable UUID, in that order.
- **Top companion:** linked Visit count, distinct Restaurant count, latest shared Visit and stable Companion UUID. The current user-written display name is presentation text, not identity.
- **Recommendation story:** one Restaurant counts once for the first formal source-bearing Visit within the month. Source IDs are authoritative; an explicit unresolved identity is not reassigned by matching text. A high result is a Restaurant whose monthly average is at least 4.0/5.
- **Taste change:** both current and previous periods require at least 3 active Visits and 2 distinct Restaurants. A cuisine/tag distribution delta or exploration/repeat-ratio delta must be at least 20 percentage points. The strongest deterministic signal is shown.
- **Keywords:** deterministic counts from Restaurant cuisine/tags, Dish names, dining occasions and explore/repeat behavior; stable lexical/identity tie-breaks produce 2–5 items.
- **Highlight:** highest deterministic Restaurant evidence using rating, Visit count, newness, relevant Photo/note evidence, recency and stable UUID.
- **Representative Restaurants:** favorite, most visited, representative new Restaurant and highlight, in role order, deduplicated by Global Restaurant UUID and capped at four.

All thresholds live in `MonthlyRecapAnalyzer.Policy`; SwiftUI contains no ranking or aggregation code.

## Photo selection

P4-D only uses active, user-owned local analytics data. For each representative Restaurant, Photo priority is:

1. active Dish Photo linked to a Dish/Visit in the selected month;
2. active Visit Photo linked to a Visit in the selected month;
3. active Restaurant marker Photo;
4. the shared P4 food placeholder.

Within a tier, display order, recency and stable UUID provide deterministic ordering. Avatar Photos and unrelated/private friend Photos are excluded. The page uses a monthly collage when multiple valid references exist. The poster receives resolved local/cached image data through the existing P4 image resolver; a remote-only uncached image falls back while offline.

## Architecture, UI and poster

- `MonthlyRecapInput` captures Sendable snapshots of Restaurant, Visit, Dish, VisitDish, PhotoAsset, DiningCompanion and RecommendationSource records.
- `MonthlyRecapAnalyzer` performs all filtering, earliest-Visit grouping, rankings, comparisons and representative selection in memory.
- `MonthlyRecapAnalysisScreen` observes relevant SwiftData collections and rebuilds the report after local inserts, edits, deletes or tombstones. No report is permanently cached.
- `MonthlyRecapAnalysisView` provides the current/history month selector, food-diary hero, conditional statistic/story sections, Restaurant Detail navigation, privacy copy and explicit share entry.
- An empty selected month renders a concise empty state and month navigation, not a complete all-zero report.
- `MonthlyRecapPosterView` is an independent 1080×1920 light-theme social composition. It shares P4 tokens, data and image references with the reading page but has a distinct poster layout.
- `AnalysisPosterRenderer`, `AnalysisPosterExportSheet`, temporary PNG lifecycle, Photos permission handling and the system share sheet are reused without creating another renderer.
- Sparse posters omit low-confidence spend, absent companion/source and unsupported taste-change blocks. Keywords or another real story fills the available hierarchy.

The Profile entry and page are private own-profile analytics. P4-D adds nothing to Public Profile, Community or Discovery. A poster is exported only after the user taps Share. It excludes private Visit notes, exact addresses, coordinates, stable entity IDs, auth identifiers and backend metadata. Companion and RecommendationSource are included only as the small aggregate story the user explicitly chose to share.

## Offline and performance

All analysis uses local SwiftData snapshots; opening a month and rendering a poster performs no HTTP request. Local/cached Photos continue to work offline, and missing remote bytes use a controlled placeholder. P4-D does not access Development or Production services.

The analyzer filters and groups each input collection once and uses dictionaries/sets for Restaurant and association lookups. Earliest historical Visit is computed in one pass, not one query per Restaurant. The performance fixture covers 500 Restaurants, 5,000 Visits and 2,000 Dishes; the analyzer completes in a fraction of a second on the test host.

## Verification boundary

The P4-D unit suite covers the requested month/timezone, identity, tombstone, new-Restaurant, spend, favorite/most-visited, companion, source, taste-change, representative/photo, poster-content, fixed-size rendering, light-theme and performance contracts. The Simulator UI test covers Profile → current recap → Restaurant Detail → poster → system share → previous month → current month → new Visit → automatic refresh.

P4-D does not change any SwiftData schema, JSON contract, Sync API, Worker, D1 migration, AuthenticationServices code, Team, Bundle Identifier, signing configuration, capability, App Icon or Web UI. It does not begin P4-E.
