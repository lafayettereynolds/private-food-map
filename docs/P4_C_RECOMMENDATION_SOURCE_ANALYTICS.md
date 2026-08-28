# P4-C Recommendation Source Analytics

This document records the product and algorithm contract implemented by the native iOS P4-C feature. P4-C is a read-only, local-first analysis over the user's existing SwiftData records. It adds no database column, sync entity, Worker route or Production dependency.

## Web baseline audit

| Analysis item | Web source and current rule | Native iOS P4-C rule | Decision |
| --- | --- | --- | --- |
| Source identity | `RecommendationSource` plus Visit source projections | Stable `RecommendationSource.id`/`remoteID`; display name remains presentation text | Reuse the P2-F identity contract; never merge by platform name. |
| Source attribution | `src/services/recommendationSourceInsights.ts` chooses the earliest source-bearing Visit per Restaurant | Earliest active Visit whose formal source identity resolves | Reuse the discovery-source meaning and count a Restaurant once. |
| Usage | Distinct attributed Restaurants | Distinct active Taste Map Restaurant UUIDs | Reuse. Repeat Visits do not inflate usage. |
| Source rating | Average rating at Restaurant level | Mean of all active, non-nil Visit overall ratings for that Restaurant, then one sample per Restaurant | Reuse the Restaurant-level weighting; native ratings stay on the 0.5–5 scale. |
| High-rating hit | Web rating at least 8/10 | Restaurant average at least 4.0/5 | Equivalent threshold. |
| Low-rating result | Web rating at most 5/10 | Restaurant average at most 2.5/5 | Equivalent threshold. |
| Repeat result | At least two active Visits to the Restaurant | Same | Reuse as an auxiliary signal, never as a substitute for a low rating. |
| Reliability / pitfall | Web has confidence-aware deterministic scores | Native retains the evidence types, formalizes centralized thresholds and explanations | Deterministic native adaptation for SwiftData. |
| Profile presentation | `src/components/ProfileAnalyticsPanels.tsx` | Native overview and source detail views | Implemented only in the current SwiftUI target. |
| Share payload | `src/services/analysisShare.ts` | Independent `RecommendationSourcePosterView` rendered through the P4 renderer | Reuses the native P4-A save/share pipeline. |
| D1 / Worker | Existing recommendation-source storage/sync | No P4-C schema or API change | Analysis remains offline and private. |

The Web implementation remains unchanged and acts only as the product-logic reference for this native feature.

## Formal source semantics

`RecommendationSource` represents how the user discovered a Restaurant. The formal association is stored on a Visit as a stable `recommendationSourceID` plus source type/text snapshots. For analysis:

1. Ignore tombstoned Sources, Restaurants and Visits.
2. Sort a Restaurant's active Visits by `visitedAt`, then stable Visit UUID.
3. Choose the earliest Visit whose formal source ID resolves to one active RecommendationSource.
4. Attribute that Restaurant to the resolved source once, even when the Restaurant has many Visits.
5. If a Visit has a non-empty source ID that no longer resolves, do not silently reassign it by name.
6. For legacy records without an ID, allow exact normalized-name fallback only when exactly one active source owns that name.
7. Two sources such as “小红书” and “小红书 @ABC” remain separate entities. P4-C never performs fuzzy merging.

The latest `RecommendationSource.displayName` is always shown, so renaming the same stable entity preserves its history. Source type remains secondary metadata and never replaces the user's own name. Want-to-go records do not currently carry the formal P2-F source association, so they are excluded rather than guessed.

## Metric definitions

- **Source usage / Restaurant count**: distinct attributed active Restaurant UUIDs. Both values are currently equal because the formal source meaning is Restaurant discovery.
- **Rated Restaurant count**: attributed Restaurants whose active Visits produce at least one non-nil overall rating.
- **Restaurant rating**: average of that user's active, non-nil Visit overall ratings for one Restaurant. Every Restaurant then contributes one rating sample to its source.
- **Average rating**: mean of the Restaurant-level samples. Community ratings are never used.
- **High-rating hit rate**: rated Restaurants with an average at least `4.0`, divided by rated Restaurants.
- **Low-rating rate**: rated Restaurants with an average at most `2.5`, divided by rated Restaurants.
- **Repeat Restaurant rate**: attributed Restaurants with at least two active Visits, divided by all attributed Restaurants.
- **Rating stability**: population standard deviation of Restaurant-level ratings. Fewer than three samples is insufficient; deviation at most `0.5` is stable, at least `1.0` is volatile, and the middle range is still forming.
- **Latest usage**: most recent acquisition date among the source's attributed Restaurants.
- **Trend**: compares distinct acquired Restaurants from the most recent 90 days with the preceding 90 days. It reports new, rising, steady, cooling or inactive and never predicts future behavior.
- **New discovery count**: the source-bearing Visit is also the Restaurant's first active Visit. This is factual supporting evidence, not part of the best/worst rank.

Unrated Restaurants count toward usage and repeat evidence, but never enter an average or high/low-rate denominator. Detailed value/environment/service ratings are shown only as supporting source-detail averages and do not alter the main ranking.

## Sufficiency policy

All thresholds are centralized in `RecommendationSourceAnalyzer`:

- Average-rating highlight: at least 2 rated Restaurants.
- Best/worst eligibility: at least 6 rated Restaurants per source.
- Relative best/worst result: at least 2 eligible sources.
- Stable sample confidence: 10 rated Restaurants.

With no source, the page explains how source data is created. With one source or too few comparable samples, it can still show usage and factual metrics but must not invent “最靠谱推荐来源” or “最坑推荐来源”. The poster uses the same conclusion model and explicitly shows the insufficient state.

## Deterministic ranking

Internal scores are bounded evidence-combination values. They are never displayed as false-precision user percentages.

### Most used

Sort by Restaurant count descending, rated Restaurant count descending, latest usage descending, then stable source UUID ascending.

### Highest average

Among sources with at least two rated Restaurants, sort by Restaurant-level average descending, rated sample count descending, then stable source UUID.

### Most reliable source

For eligible sources:

```
0.30 × normalized average rating
+ 0.27 × high-rating hit rate
+ 0.16 × repeat Restaurant rate
+ 0.10 × rating stability
+ 0.10 × performance relative to the user's all-source average
+ 0.07 × bounded sample confidence
```

Sort score descending, then rated sample count descending, then stable source UUID. The user-facing explanation states rated Restaurant count, high-rating count, comparison with the user's all-source average and repeat Restaurant share.

### 最坑推荐来源

For eligible sources:

```
0.34 × low-rating rate
+ 0.22 × inverse high-rating hit rate
+ 0.10 × inverse repeat Restaurant rate
+ 0.22 × normalized low average rating
+ 0.05 × rating instability
+ 0.07 × bounded sample confidence
```

Sort score descending, then rated sample count descending, then stable source UUID. This prevents one isolated bad Restaurant from being declared “最坑推荐来源”. The user-facing explanation names the rated sample count, low-rating count, actual average and repeat Restaurant share; it does not expose the internal score or generate insulting copy.

## Representative Restaurant policy

The overview deduplicates Restaurant UUIDs across up to three deterministic roles:

- latest Restaurant from the most-used source;
- highest-rated qualifying Restaurant from the most reliable source;
- lowest-rated qualifying Restaurant from the “最坑推荐来源”.

The source detail lists all attributed Restaurants in stable evidence order and can open the existing Restaurant Detail. Best/worst examples require a real high/low rating; a nil-rated Restaurant is never labeled as a rating success or failure.

Image priority is the existing local Photo pipeline: Dish photo, Visit photo, Restaurant marker photo, then the shared P4 food placeholder. Tombstoned/avatar photos are excluded. P4-C does not add an image loader or upload path.

## Native page and poster architecture

- `RecommendationSourceInput` captures one Sendable snapshot of the relevant SwiftData data.
- `RecommendationSourceAnalyzer` performs all grouping, metrics, ranking and evidence selection outside SwiftUI.
- `RecommendationSourceAnalysisScreen` refreshes the snapshot when relevant local records change.
- `RecommendationSourceAnalysisView` presents the source-trail hero, conclusion hierarchy, receipt-like metrics, representative Restaurant stories and the complete source list.
- `RecommendationSourceDetailView` presents one source's actual display name, type, metrics, stability, trend, detailed-rating support and Restaurant evidence.
- `RecommendationSourcePosterView` is an independent fixed 1080×1920 social artifact; it is not a screenshot of the reading page.
- `AnalysisPosterRenderer`, image resolution, temporary PNG lifecycle, Photos permission handling and system Share Sheet are reused from P4-A/P4-B.
- Existing P4 design tokens, typography, callouts, image references and Restaurant story language remain the shared visual system. P4-C adds a source-ticket-to-food-table hero without third-party platform logos.

The page contains 17 state previews (including empty, single source, insufficient comparison, best/worst, stable/volatile/low sources, want-to-go, photo/no-photo, long strings, small screen and accessibility text) plus rich and insufficient poster previews.

## Offline, privacy and invalidation

P4-C performs no HTTP request. The page, poster and fallback images work from local SwiftData/cache when offline. A saved local change updates the report input revision and the analyzer recomputes; there is no persisted stale analysis snapshot.

The report is available only from the current user's own Profile. The poster is created only after an explicit share action and may contain the user's own source names, aggregate rating evidence and Restaurant names/photos. It excludes internal source IDs, backend metadata, user/auth IDs, private Visit notes, companion identities, exact addresses and precise location history. P4-C adds nothing to Public Profile, Community or Discovery.

## Performance and test boundary

The analyzer filters and groups each collection once, then calculates per-source results from dictionaries/sets. SwiftUI does not query or aggregate Visits inside card bodies. The unit suite covers the complete requested 1–53 matrix and a 100-source / 1,000-Restaurant / 3,000-Visit performance fixture.

P4-C does not access Development or Production services, migrate D1, change sync/auth, change signing/capabilities, modify App Icon, or begin P4-D.
