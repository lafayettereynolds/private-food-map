# P4-A — Taste Profile analytics and share poster

## Scope and safety boundary

P4-A is a native iOS read-only analysis layer over the user's local SwiftData records. It does not add a server endpoint, change the sync contract, modify D1, access Production, or change P0/P1/P2/P3 persistence models. The Web app remains unchanged. The page and poster never create restaurants, visits, ratings, spend, companions, sources, photos, or inferred people.

## Web baseline audit

The Web implementation remains the product-logic reference:

- `src/services/tasteProfileCore.ts` ranks cuisine preference with average rating, high-rating share, visit frequency, repeat visits and restaurant breadth. P4-A adapts the same evidence types, reliability-weights ratings, and adds a bounded recency signal. This prevents one isolated five-star visit from dominating repeated behavior.
- `src/services/profileInsights.ts` filters deleted data and derives cuisine tags, price buckets, scenes, repeat behavior, rating style, recommendation sources, companions and keywords.
- The Web spend path may fall back to normalized spend/period totals. Native P4-A intentionally does **not** copy this fallback: spend uses `Visit.myActualSpend` only because the requested iOS contract defines that value as the user's actual spend.
- The Web repeat figure is based on repeat visit rows divided by all visit rows. Native P4-A defines the requested “回头率” as restaurants with two or more visits divided by distinct visited restaurants. The denominator is shown in the explanation so it cannot masquerade as a more precise measure.
- Web companion/source conclusions are useful product references, but P4-A only shows frequency summaries. Relationship profiling belongs to P4-B and source reliability / “最坑推荐来源” belongs to P4-C.

## Native data mapping

`TasteProfileInput.capture` snapshots active local models into Sendable value records, then the pure `TasteProfileAnalyzer` runs off the main actor.

| Analysis signal | SwiftData source | Null / deletion rule |
| --- | --- | --- |
| visited restaurants | `Restaurant`, `Visit` | `deletedAt != nil` is excluded; orphan visits are excluded |
| cuisine | `Restaurant.remoteRecordData` → `RestaurantJSONContractV1.tags` | no name-based cuisine guessing |
| rating style | `Visit.rating`, detailed ratings | `nil` is excluded, never zero |
| spend | `Visit.myActualSpend` | `nil` is excluded, never zero; Dish price is not substituted |
| scene | dining occasions, environment tags, noise level | empty values add no conclusion |
| companion | `companionIDs`, `companionNames`, `DiningCompanion` | no person is extracted from free-form notes |
| recommendation source | source ID/type/text and `RecommendationSource` | frequency only in P4-A |
| dish preference | `Dish`, `VisitDish` | tombstones and associations to deleted visits are excluded |
| representative photo | `PhotoAsset` | avatar/deleted photos excluded; existing local/cache/download pipeline is reused |

No new SwiftData entity or schema migration is required.

## Algorithms

### Cuisine ranking

For every structured cuisine tag:

1. collect distinct visit IDs, distinct restaurant IDs, non-null ratings and most recent visit;
2. compute a reliability-weighted rating component;
3. add logarithmic visit frequency, repeat-visit and restaurant-breadth components;
4. add a bounded recency component;
5. sort by score, visit count and stable normalized label.

Tags that clearly describe scenario, environment, value, service or location are excluded from cuisine ranking. Ties are deterministic.

### Spend

Non-negative `myActualSpend` values are sorted. The report exposes median, lower/upper quartiles, sample count and fixed price buckets. The UI always labels the sample size and never substitutes missing values.

### Rating style

Only non-null half-star ratings enter mean, median, standard deviation and high/low shares. Fewer than three ratings remains “正在形成”. Detailed value/environment/service averages are shown only when their samples exist.

### Repeat rate

`restaurantsWithAtLeastTwoVisits / allDistinctVisitedRestaurants`. Zero restaurants produces no percentage conclusion. The detail line always gives both counts.

### Dining time

The hour component uses the current device calendar. Existing Visit rows do not preserve the time zone used at entry, so the page explicitly states that historical cross-time-zone precision is unavailable.

### Representative restaurants

Candidates are generated for most visited, highest reliable average, most active in the recent 90-day window and strongest match to the top cuisine. They are deduplicated by Taste Map Restaurant UUID, then limited to four on the page and three on the poster. The image preference is Dish → Visit → restaurant marker, with stable sort order and updated time.

### Dynamic food hero

Real Dish/Visit photos are preferred when available. Cuisine and dish labels select Japanese, hotpot/grill, Chinese, Western or cafe themes; similarly strong themes create a mixed plate. When local/cached/remote photo resolution is unavailable, one of six bundled food illustrations is used. The asset is a fallback, not evidence and not a fake restaurant photo.

## Data sufficiency

Every dimension has an explicit `insufficient`, `emerging` or `established` state. The page displays a growth prompt for insufficient dimensions. It does not hide the whole page, invent a mature label, or present unavailable data as zero. The overall default thresholds are 0–2, 3–9 and 10+ visits, with dimension-specific thresholds where the sample unit differs.

## Page and poster

The in-app page is optimized for reading: title and provenance, center food with four surrounding callouts, ranked preference, narrative insight cards, keywords, receipt-like spend distribution, restaurant stories and data limitations.

The 1080 × 1920 poster is a separate fixed light-mode composition for sharing. It keeps the center food and four callouts, selects three to six concise conclusions, includes keywords and up to three representative restaurants, and uses explicit bounds/line limits for long content. It is rendered with SwiftUI `ImageRenderer`; it is not a screenshot of the page.

The save action requests Photos `.addOnly` authorization. The system-share action writes an atomic temporary PNG, shares the file URL and removes it after completion/dismissal. Tokens, secrets and private sync credentials are not part of the image or temporary filename.

## Offline and performance

The analysis itself is entirely local. Photo resolution calls the existing `PhotoTransferCoordinator`: cached/local images work offline and failed remote loads fall back to bundled artwork or a neutral missing-photo treatment. Analysis snapshots are Sendable and computed in a detached user-initiated task. Tests cover 200, 500 and 1,000 visits.

## Reusable P4 foundation

The following are intentionally reusable by P4-B through P4-E:

- analysis report kind, sufficiency, tone, image reference and shared tokens;
- food glyphs, tag flow, connector web, receipt shape and restaurant evidence image;
- separate page/poster data flow;
- ImageRenderer, PhotoTransferCoordinator image resolver, add-only saver, temporary-file share lifecycle;
- 9:16 export dimensions and explicit light-mode poster behavior.

Future modules should define their own report DTO and layout hierarchy. They should reuse the visual/service foundation without forcing a monthly review, companion report or source report into the Taste Profile layout.

## Protected visual branch audit

The protected `codex/taste-analysis-visuals` branch predates later P1–P3 work. A whole-branch merge would remove or regress a large part of the current app, so it was not merged.

Selectively adapted:

- warm-white food-poster direction;
- center food plus four connected callouts;
- receipt, food glyph, tag and representative restaurant story ideas;
- six `FoodHero*.imageset` fallback illustrations;
- independent SwiftUI poster and `ImageRenderer` approach.

Deliberately not copied:

- old Restaurant/Visit-only builder and its stale claim that native companion/source models do not exist;
- direct `URLSession` image loading and remote merchant-image assumptions;
- old 1080 × 1440 poster ratio;
- obsolete model APIs, preview-only conclusions and branch-wide project changes;
- App Icon changes;
- any deletion/regression of current P0–P3 code.
