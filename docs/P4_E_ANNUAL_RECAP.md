# P4-E Annual Recap and Taste Journey

This document records the native iOS product, time-boundary, analysis, privacy, and performance contract for P4-E. The feature is a read-only, local-first analysis over the existing SwiftData domain. It adds no database field, sync entity, Worker route, D1 migration, authentication change, signing change, or Production dependency.

## Web baseline audit

| Annual item | Web source and current rule | Web fields | Native iOS data | P4-E decision | Insufficient-data behavior |
| --- | --- | --- | --- | --- | --- |
| Year grouping | `src/services/reviewService.ts` groups review dates by natural year | review date | `Visit.visitedAt` instant | One `AnnualPeriod` and one half-open year interval for every module | Empty years are not listed except the current year |
| Visit / Restaurant / new-store counts | `reviewService.ts` counts reviews and referenced restaurants, and compares first reviews | review ID/date/restaurant reference | Complete Visit UUID and Global Restaurant UUID | Active Visit count; distinct Global Restaurant UUID; earliest active Visit across all history determines “new” | Empty year gets one compact empty state |
| Spend | `reviewService.ts` sums recorded actual spend | actual spend | `Visit.myActualSpend` | Sum/median/coverage/month distribution from non-nil values only | Low coverage is explicitly “已记录”, never a complete-spend claim |
| Favorite / most visited | Web annual favorite can be dominated by one highest-rated memory; most visited is count-based | rating/date/restaurant | Visit ratings, detailed ratings, Dish ratings | Restaurant-level deterministic evidence score; separate count-first most-visited ranking | Favorite omitted without rating evidence |
| Companion | Web derives yearly names from review companion data | companion text/association | Stable P2-F Companion identity and Visit associations | Formal Visit associations only; current display name is presentation | Omitted when none exists |
| Recommendation source | Web groups source type/text and reports yearly source outcomes | source type/text/rating | Stable P2-F source identities | Distinct-Restaurant attribution with P4-C confidence thresholds | No best/worst verdict before qualification |
| Taste trajectory | Web exposes year distribution and mostly static tag comparison | category/tag/date | Cuisine/tags, Dish, context, rating, spend, repeat/new signals | Deterministic monthly or quarterly milestones plus factual half-year change rules | No complex trajectory for sparse years |
| Keywords | Web derives broad tags | category/context | Complete | 3–6 deterministic labels with semantic-category dedupe | Fewer honest labels are allowed |
| Representative Restaurants / photos | Web annual cards select key memories | restaurant/photo/rating | Restaurant, Visit, Dish and PhotoAsset | Role-based 3–6 Restaurant selection and year-relevant photo priority | Sparse years show fewer cards; missing bytes use the controlled fallback |
| Annual share | `src/services/analysisShare.ts` produces Web share output | yearly projection | P4 native renderer/share stack | Independent fixed 1080×1920 SwiftUI poster | Empty years cannot create a poster |

The Web implementation remains unchanged and is used only as product/data reference. P4-E deliberately strengthens Global Restaurant identity, Restaurant-level ranking, stable provider-independent source identity, confidence gating, and taste-trajectory evidence where the Web implementation is looser.

## `AnnualPeriod`, Calendar, and timezone

`AnnualPeriod` stores `year` and a Calendar whose timezone is the user's current timezone. Its bounds are:

```text
start = local Calendar start of January 1
end   = local Calendar start of January 1 in the next year
start <= visitedAt < end
```

Every annual component—counts, spend, Companion, source, journey, month highlights, keywords, and photo relevance—uses the same interval. Current-year copy and poster labels are partial by design, for example `2026 · 截至 8 月 28 日`; past years use complete-year wording such as `2025 年度回顾`.

P1-C stores `Visit.visitedAt` as an absolute instant but does not preserve the timezone of original entry. A later device-timezone change can therefore move a visit close to midnight across a natural-year boundary. P4-E applies one current Calendar/timezone consistently and documents this existing data-model limitation instead of mixing UTC and local boundaries.

The year switcher includes the current year and only historical years that contain an active Visit. It does not manufacture a long list of empty years.

## Metric definitions and stable rankings

- **Visit count:** active, distinct Visit UUIDs inside the target year. Twenty visits to one Restaurant count as twenty Visits.
- **Restaurant count:** distinct active Taste Map Global Restaurant UUIDs referenced by those Visits. Apple Maps, Community, Discovery, and legacy provider identities do not create additional Restaurant counts.
- **New Restaurant:** the earliest active Visit for that Restaurant across all available history falls in the target year. Tombstoned historical Visits do not prevent a later first valid Visit from being new.
- **Exploration rate:** annual new distinct Restaurants divided by annual distinct Restaurants. It is supporting evidence, not a mandatory score claim.
- **Recorded spend:** sum, median, number of recorded Visits, coverage, and a 12-month distribution using only non-nil `myActualSpend`. Dish price is never substituted. Coverage below 60% keeps the explicit “已记录消费” framing and reduces poster prominence.
- **Favorite Restaurant:** among Restaurants with rating evidence, rank by `average Visit rating × 0.72 + bounded repeat evidence (up to six Visits) × 0.70 + repeat bonus × 0.35 + bounded Dish-rating support × 0.15`. Ties use average rating, Visit count, latest Visit, then stable UUID. This makes repeated 4.5-star evidence capable of outranking one isolated 5-star Visit.
- **Most visited Restaurant:** annual Visit count, average rating, latest Visit, and stable UUID, in that order.
- **Top Restaurants:** favorite, most visited, strong new-store evidence, and journey/highlight representatives are combined in role order and deduplicated by Global Restaurant UUID.
- **Top Companion:** linked annual Visit count, distinct Restaurant count, latest shared Visit, and stable Companion UUID. A multi-companion Visit counts once for each formal association. Friend relationships alone never imply dining together.
- **Recommendation attribution:** each distinct Restaurant is attributed to its earliest formal source-bearing Visit in the target year. An explicit unresolved source identity does not silently fall back to matching display text. Renaming a source does not change identity.
- **Recommendation qualification:** an individual source needs six rated distinct Restaurants; best/worst verdicts additionally require at least two eligible sources. P4-C confidence-aware reliability/pitfall scoring is reused. The formal phrase `年度最坑推荐来源` appears only after those gates pass.

All thresholds and ordering rules live in `AnnualRecapAnalyzer`; SwiftUI contains no aggregate or ranking business logic.

## Taste Journey, changes, highlights, and keywords

The Taste Journey is not twelve monthly totals pasted together. The analyzer groups the selected year's Visits once, then derives a consistent granularity:

- **monthly:** at least 12 annual Visits and at least 4 active months;
- **quarterly:** otherwise, at least 6 annual Visits and at least 2 active quarters;
- **insufficient:** less evidence than the quarterly rule.

The journey emits 3–5 deterministic milestones from the active periods. A milestone can use cuisine/category, Dish theme, exploration/repeat behavior, dining context, or a representative Restaurant, but only when present in the local data. Missing months remain gaps; the analyzer never synthesizes activity.

Change summaries compare the first and second half of the year only when both halves contain at least four Visits and two Restaurants. A signal must move by at least 20 percentage points. Up to three concise factual changes are emitted; literary or causal claims are prohibited.

Monthly highlights are selected from distinct months and capped at three: busiest month, most new Restaurants, highest average rating with at least two rated Visits, or highest recorded spend with at least 60% coverage. Stable kind/month ordering makes repeated analysis identical.

Keywords are derived from cuisine/tags, Dish names and taste descriptors, exploration/repeat behavior, dining context, and the formal top Companion. A semantic-category gate prevents synonymous cuisine, exploration, repeat, Companion, and context labels from repeating the same idea. Rich years produce 3–6 labels; sparse years may honestly produce fewer.

## Representative Restaurants and annual photo story

P4-E selects up to six distinct Restaurants from the favorite, most visited, strongest new-store evidence, Taste Journey milestones, and monthly highlights. A sparse year displays only real candidates.

Photo selection is deterministic and year-scoped:

1. active Dish Photo linked to a Dish/Visit in the target year;
2. active Visit Photo linked to a Visit in the target year;
3. active Restaurant marker Photo;
4. the shared P4 food fallback.

Within a tier, display order, recency, and stable UUID decide selection. Avatar Photos and unrelated records are excluded. The annual hero uses a modern food collage and the poster uses three representative Restaurant photo cards. Preview fixtures substitute real bundled P4 food assets to verify the rich-photo state; the Simulator E2E intentionally also exercises the no-photo fallback.

## Architecture, page, and independent poster

- `AnnualRecapInput` reuses the P4-D `MonthlyRecapInput` Sendable snapshot contract, so Restaurant, Visit, Dish, VisitDish, PhotoAsset, Companion, source, and profile records are captured once from SwiftData.
- `AnnualRecapAnalyzer` filters/groups the selected year, builds one all-history earliest-Visit map, and derives all annual results in memory. It does not perform twelve store queries and does not merely concatenate twelve monthly reports.
- `AnnualRecapAnalysisScreen` observes the existing SwiftData entities. Count/maximum-update revision tracking invalidates analysis after local insert, edit, delete, or tombstone. Work runs in a detached user-initiated task after one main-actor snapshot capture.
- `AnnualRecapAnalysisView` implements Header/Year Selector → food-collage Hero → core metrics → favorite/most visited → Taste Journey → month highlights → Companion/source → keywords → representative Restaurant/photo story → Share/privacy. Restaurant stories navigate into the existing Restaurant Detail.
- An empty selected year renders one natural empty state and no Share action or zero-filled report.
- `AnnualRecapPosterView` is an independent 1080×1920 light-theme composition, not a screen capture. It selects a brand/year header, food collage, receipt metrics, 3–5 journey nodes, three Restaurant/photo cards, one Companion/source story, and keywords.
- Current and past years retain distinct poster semantics. Sparse data removes unsupported blocks. Low spend coverage uses another real story/metric rather than implying complete spending.
- `AnalysisPosterRenderer`, `ImageRenderer`, `AnalysisPosterExportSheet`, Photos permission handling, temporary PNG cleanup, save, and system share are reused from P4-A.

Everything is local-first. The page and poster open offline; cached/local photos work offline and unavailable remote bytes fall back safely. P4-E performs no network request.

## Data sufficiency, privacy, and performance

Sufficiency is assessed independently for the annual overview, favorite, Companion, source, Taste Journey, changes, keywords, and photo story. A year with three Visits can still show its real counts and Restaurant cards, but it does not receive a complex behavioral trajectory. An empty year cannot generate a poster.

Annual Recap is own-profile private analytics. It is not added to Public Profile, Community, or Discovery. Only an explicit Share action exports the curated aggregate poster. The page/poster exclude private Visit notes, exact addresses, coordinates, internal entity IDs, auth identity, storage keys, raw Companion relationships, and backend metadata. The poster may include the user-entered top Companion display name and a qualified aggregate source conclusion because the user explicitly initiates export.

The analyzer is linear over the provided collections plus stable sorting of small candidate groups. It builds the earliest Visit map once, groups the year once, and never performs an N+1 fetch. The performance fixture covers 1,000 Restaurants, 10,000 Visits, and 5,000 Dishes; the measured analyzer run on the test host is approximately 1.23 seconds and remains below the two-second regression ceiling, off the main actor.

## Verification boundary

The dedicated P4-E XCTest suite has 20 test functions covering the 84 requested contracts: year/current/past/timezone bounds; active counts, tombstones and Global identity; new Restaurant and exploration; recorded spend/median/month distribution/coverage; favorite and most-visited ranking/ties; Companion associations; source identity, thresholds and annual best/worst; monthly/quarterly journey, gaps and insufficiency; deterministic keywords and highlights; representative Restaurant/photo priority; current/past/sparse/long-name poster content, fixed 1080×1920 rendering and light theme; and large-input performance.

The Simulator UI E2E covers Profile → Annual Recap → current-year overview → Restaurant Detail → Taste Journey → independent poster → system Share Sheet → previous year → current year → insert Visit → automatic annual count refresh. Twenty-three SwiftUI previews cover the requested rich, partial, historical, sparse, empty, explore/repeat, cuisine, Companion, source, spend, photo, long-text, poster, small-screen, and accessibility-text states.

P4-E does not change SwiftData schema, JSON contracts, Sync API, Worker, D1, AuthenticationServices, Keychain, Team, Bundle Identifier, signing, capabilities, App Icon, Web UI, or the protected `codex/taste-analysis-visuals` branch. It does not access Development or Production services and does not begin P4-F.
