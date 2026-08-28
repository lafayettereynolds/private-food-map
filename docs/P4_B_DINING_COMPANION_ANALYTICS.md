# P4-B Dining Companion Analytics

This document records the product contract implemented by the native iOS P4-B feature. It is intentionally local-first and does not introduce a new server schema or production dependency.

## Web baseline audit

| Web capability | Web source | iOS P4-B mapping | Notes |
| --- | --- | --- | --- |
| Companion overview | `src/services/companionInsights.ts` | `DiningCompanionOverviewView` | Count descending, then latest shared Visit, then stable ID. |
| Shared-visit aggregation | `src/services/companionInsights.ts` | `DiningCompanionAnalyzer.groupVisitsByCompanion` | One Visit counts once for each explicitly selected companion. |
| Distinct restaurants and repeat behavior | `src/services/companionInsights.ts` | `DiningCompanionAnalyzer` | Restaurant UUID is the de-duplication identity. |
| Food/cuisine ranking | `src/services/companionInsights.ts` | `rankFoods` / `rankCuisines` | Native iOS prefers Dish evidence and only falls back to structured Restaurant tags. |
| Rating, spending and dining contexts | `src/services/companionInsights.ts` | companion rating/spend/context summaries | `nil` values are excluded; spend means only `myActualSpend`. |
| Representative memories | `src/services/companionInsights.ts` | `representativeRestaurants` | Uses facts from the current user's records; note presence can affect ranking, but note text never leaves the private record. |
| Share payload | `src/services/analysisShare.ts` | `DiningCompanionPosterView` | iOS renders an independent 1080×1920 poster and shares a temporary PNG. |
| Web tests | `src/services/companionInsights.test.ts` | `P4BDiningCompanionTests.swift` | Keeps the existing 0–2 / 3–5 / 6+ sufficiency tiers. |

## Data boundary

The analyzer captures active local SwiftData records into a Sendable presentation input and performs calculation away from the SwiftUI view. It reads:

- `DiningCompanion`: the user's private companion directory and optional linked Taste Map identity.
- `Visit`: companion IDs/names, date, rating dimensions, `myActualSpend`, structured dining context, Restaurant link and tombstone state.
- `Restaurant`: Taste Map UUID, status, city, preference and structured tag contract.
- `Dish` and `VisitDish`: shared dish evidence with Restaurant-link validation.
- `PhotoAsset`: local photo metadata for the user's own Restaurant/Visit/Dish evidence.
- `UserProfile`: the current user's display name and city.
- `CachedSocialProfile` and `CachedFriendship`: a linked avatar preset only when the cached relationship is currently `friends`.

It does not read another user's Visit history, precise movement history, private profile data, community feed, Production D1, or any network endpoint. A linked Taste Map user ID never becomes the companion analytics identity and is never emitted by the report/poster.

## Definitions

- **一起吃次数**: count of active local Visit records that resolve to the companion. Duplicate IDs/names inside one Visit still count once. A Visit with several companions counts once for each selected companion.
- **Restaurant 数**: distinct active Taste Map Restaurant UUIDs among those Visits.
- **最近一起吃**: latest `visitedAt` among active shared Visits.
- **最常一起吃什么**: repeated Dish evidence first; if no Dish reaches repeated evidence, use structured cuisine tags. With fewer than two Visits, do not claim a top food.
- **回头率**: number of shared Restaurants with at least two shared Visits divided by distinct shared Restaurant count. It is not Visit-row repetition rate.
- **稳定画像**: 0–2 shared Visits is `insufficient`, 3–5 is `emerging`, and 6+ is `established`.
- **共同回忆餐厅**: deterministic score from shared Visit count, the current user's rating, photo availability, private-note presence, structured occasion and recency. Only the existence of a note contributes; its text is never displayed or exported.
- **评分**: only the current user's non-nil ratings. Comparison against baseline requires enough rated records and never represents the companion's opinion.
- **消费**: only non-nil, non-negative `myActualSpend`, reported as a median and sample count. It is omitted from the share poster.

## Identity and name handling

The stable analytics key is `DiningCompanion.id`. `displayName` is presentation text only. Remote/local companion identifiers may resolve a Visit to that stable UUID. A normalized name is used only as a legacy fallback when exactly one active companion owns that name. Two active companions with the same name are never merged automatically.

The name written by the user remains the visible name. A linked social profile cannot replace it. A friend-level linked cached profile may provide an avatar preset; unlinked or unauthorized identities use a deterministic initial avatar.

## Keywords and behavioral portrait

Keywords are rules over observable shared-meal behavior and are capped at four. Examples include familiar-restaurant repetition, exploration, repeated Dish/cuisine, weekend timing, late meals and consistently high scores from the current user. The analyzer does not infer intimacy, personality, relationship quality or emotion. It shows fewer or no keywords when evidence is insufficient.

## Next-meal recommendation

P4-B uses only the current user's local Restaurant collection; it does not add a new network recommendation source.

1. Establish geographic scope from the most frequent shared-Visit city, falling back to the user's profile city.
2. If no reliable city exists, return no recommendation instead of making a cross-city guess.
3. Keep only active, accessible, same-city, non-`avoid` Restaurants.
4. Exclude Restaurants whose available local average rating is below 3.0.
5. Prefer want-to-go Restaurants, Restaurants not yet shared with the companion, repeated cuisine matches, stable local ratings and explicit `favorite`/`like` preference.
6. A previously shared Restaurant is eligible only when the pair exhibits a familiar-restaurant pattern. Very recent repeated Restaurants are suppressed unless the repeat pattern and rating evidence are exceptionally strong.
7. Sort by score, want-to-go status, localized name and stable ID for deterministic offline results.

Restaurant coordinates are not present in the analytics contract, so P4-B makes no fabricated distance claim. A future recommendation service may add explicit radius filtering while retaining this privacy and determinism contract.

## Photo policy

Photo selection is scoped to the same Restaurant and shared evidence. Priority is Dish photo, shared-Visit photo, then Restaurant marker photo. Tombstoned/avatar photos are ignored. A photo linked to a shared Visit but a different Restaurant cannot appear on the card. When no valid photo exists, the reusable food hero illustration remains visible.

The user explicitly initiates poster generation. The independent poster may include the user's own selected food/Restaurant photos, but excludes private note text, spend, internal IDs, linked user IDs and exact address history.

## Native page and poster architecture

- `DiningCompanionAnalysisScreen` captures one SwiftData snapshot and refreshes when relevant record counts or update/tombstone timestamps change.
- `DiningCompanionAnalyzer` is pure, deterministic and network-free.
- `DiningCompanionOverviewView` and `DiningCompanionDetailView` are reading/navigation layouts.
- `DiningCompanionPosterView` is a fixed 1080×1920 social artifact with a shared-table hero; it is not a screenshot of the page.
- `AnalysisPosterRenderer`, `AnalysisPosterImageResolver`, `AnalysisPosterExportSheet`, save permission handling and temporary-file cleanup are reused from P4-A.
- P4-A design tokens, food hero/media, callout cards and Restaurant story cards remain the common P4 visual language.

## Offline and performance

No HTTP call is part of analysis or poster generation. Local edits are visible after SwiftData saves because the screen recomputes from a captured revision. The analyzer groups Visits once and operates on dictionaries/sets to avoid per-card SwiftData fetches and view-level N+1 work. The regression suite includes 200 companions and 3,000 Visits with a two-second upper bound on the simulator test environment.

## Future boundary

P4-C should implement recommendation-source analysis as a separate report using the same analysis data sufficiency, poster export and privacy infrastructure. P4-B does not add recommendation-source conclusions, monthly/annual reviews, community publishing, new sync records or any Production migration.
