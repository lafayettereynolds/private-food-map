# P4-G Restaurant Roulette

This document records the native iOS product boundary, candidate identity, random selection, visual behavior, accessibility, offline behavior, and acceptance contract for P4-G. P4-G adds only “今天吃什么”. It does not add AI recommendations, weather, gamification, persistent roulette history, list roulette, or a new backend domain.

## Web baseline audit

| Capability | Formal Web source and behavior | Native state before P4-G | P4-G decision |
| --- | --- | --- | --- |
| Entry | `src/components/ProfilePage.tsx` opens `RestaurantRoulette.tsx`; several Web restaurant surfaces can add one candidate | No native roulette entry | Add one primary “我的” entry; do not scatter new entry points across native surfaces |
| Candidate source | User manually selects up to ten current-user Restaurant summaries; temporary text candidates are also possible | No candidate model | Use the user's real local Restaurant set so the default screen can spin immediately; the session manager provides explicit inclusion/exclusion without manufacturing string-only Restaurants |
| Status | All / visited / want-to-go filter | Native `RestaurantStatus` already authoritative | Preserve exactly these three source filters; no roulette-specific status |
| Search | Filters the Web candidate picker | Existing native MapKit Restaurant search | Empty state opens existing native Restaurant Search; selected results enter normal WantToGo/visited local storage rather than a parallel roulette database |
| Random | Uniform `Math.random` over selected candidate array | None | Uniform selection with injectable Swift `RandomNumberGenerator`; no rating/visit weighting |
| Repeat | Immediate repeats are possible | None | Exclude only the immediately previous result when at least two candidates exist; allow it again after another result |
| Animation | Approximately 4.2 seconds and an optional sound | None | Native SwiftUI multi-turn wheel, 3 seconds, haptics, no sound; Reduce Motion uses a short 0.28-second transition |
| List roulette | Not formally implemented in `RestaurantRoulette.tsx` | P4-F lists exist | Do not invent list roulette merely because native lists now exist |
| City/category/rating/price | Not formal Web roulette filters | Restaurant data has some fields | Add only the mandatory geographic scope needed to avoid cross-city results; do not add category, rating, price, distance, or AI filters |
| History | No durable roulette history | None | Keep only the current session's last result; no SwiftData model, sync entity, D1 field, or analytics claim |
| Sound | Web has a continuing sound/mute interaction | No native roulette sound | Do not migrate sound; use restrained haptics to avoid a game/casino feel |

The React/Web UI is reference-only and remains unchanged.

## Product invariants

- Roulette is a decision helper over Restaurants the user can already access, not a recommendation score, gambling mechanic, or state-changing action.
- A result never changes `RestaurantStatus`, creates a Visit, modifies a rating, or adds/removes a list item.
- WantToGo and visited remain the existing `RestaurantStatus` values. A visited Restaurant's displayed rating/count are computed only from active local Visits.
- Every eligible Restaurant has equal probability. Rating, Visit count, recency, list position, and display order do not alter probability.
- Tombstones, invalid names/coordinates, inaccessible rows, and duplicate Global Restaurant identities cannot enter the candidate pool.
- Candidate names may be abbreviated only on the wheel. Result and Restaurant Detail always use the source Restaurant name without mutation.
- The feature is completely local and remains usable without an authenticated session or network connection.

## Candidate and identity model

`RouletteCandidate` is a non-persistent projection containing the local Restaurant ID, Global Restaurant key, display fields, city, status, factual Visit summary, optional Photo ID, category display metadata, emoji, and update time.

`RouletteRestaurantRecord.capture` builds projections from active SwiftData `Restaurant`, `Visit`, and `PhotoAsset` rows. Global identity resolution follows this order:

1. primary `placeIdentities[]` identity from `RestaurantJSONContractV1`;
2. first contract identity when no primary is marked;
3. Apple Maps external identity;
4. stable Taste Map remote ID;
5. stable local Restaurant UUID as a manual fallback.

The normalized provider/external pair is used only for deduplication and cross-surface identity. It is not a new Restaurant ID. When duplicate projections are present, the newest `updatedAt` wins with local UUID as a deterministic tie-breaker. No `amapPoiId` is required.

## Default pool and filters

The default source is “全部”. The geographic scope prefers the active Profile city when that city exists in local candidates; otherwise it chooses the city represented by the most eligible local Restaurants with deterministic lexical tie-breaking. It never requests precise location merely to spin.

The only formal filters are:

- source: all, WantToGo, or visited;
- city: one of the cities already present in the user's candidate set;
- session inclusion: “管理候选” can temporarily exclude or re-include candidates.

Filters are deterministic and stable. They do not persist or sync because they are a lightweight current-session decision, not user domain data. Clearing conditions restores all sources, the default city, and all candidates.

## Random selection and repeat policy

The engine uses `randomElement(using:)` over the complete filtered array and supports an injected RNG for deterministic tests. When more than one Restaurant is eligible, the immediately previous Global key is removed for the next selection only. This prevents an obviously frustrating back-to-back repeat without creating hidden long-term weighting. Once a different Restaurant is selected, the earlier Restaurant is eligible again.

Candidate sorting is a stable presentation concern only: localized Restaurant name followed by Global key. Random selection does not use the sorted index as a weight.

## Wheel geometry and large pools

For 2–30 candidates, each candidate has an exact visual segment. The target rotation includes at least five full turns and places the selected segment center under the fixed top pointer. The engine exposes target-angle and pointer-index functions so 2, 3, 8, 12, 30, 100, and 1,000-candidate mappings are directly testable.

Above 30 candidates, all candidates remain in the random pool but the wheel renders twelve abstract pastel segments. The selected candidate maps deterministically to one of those twelve visual positions for the final animation. The UI explicitly says that the full pool participates while the wheel is simplified, so visual compression is not misrepresented as candidate removal.

## Native UI

- The “我的” page has one Style-A card labeled “今天吃什么 / 帮我挑一家”.
- Header, condition card, wheel, and result use the existing brand blue, warm off-white canvas, restrained food accents, white cards, and factual copy.
- The wheel uses soft blue, green, cream, red, purple, and neutral segments. It has no jackpot language, flashing light, coin, score, confetti, streak, or reward mechanic.
- Two or more candidates show the interactive wheel. One candidate skips fake randomness and says “今天就它了”. Zero candidates show a clear state with existing Restaurant Search.
- The result card reuses a valid local Photo when one exists, otherwise a food-themed gradient and the Restaurant emoji. It shows name, city/address, existing status, own average rating only when present, and Visit count only from active records.
- “查看餐厅” opens the existing `RestaurantDetailView`. Returning preserves the session result. “再来一次” follows the immediate-repeat policy.
- Haptics provide a soft start and success stop. Sound is deliberately absent.

## Accessibility and motion

- The screen, count, filters, spin button, result, actions, empty/single states, and fixture flows expose accessibility labels or identifiers.
- VoiceOver hears candidate count, a descriptive spin action, and a completion announcement naming the selected Restaurant.
- Dynamic Type uses flexible text and allows the stage width to contract for accessibility sizes.
- System Reduce Motion or the dedicated Preview presentation replaces the long five-turn animation with a short one-turn, 0.28-second ease-out transition.
- Secondary copy uses an explicit contrast-safe muted token instead of inheriting an environment-dependent hierarchical color.

## Offline, sync, privacy, and backend boundary

The engine reads existing SwiftData rows and performs all filtering, deduplication, random selection, and animation on device. It does not call `APIClient`, `SyncEngine`, Worker, D1, or R2. Restaurant/Visit/Photo changes made elsewhere continue through the existing local-first and Sync V1 systems; the roulette reacts to `@Query` updates without creating its own mutation.

No auth token, provider secret, precise current location, private Visit note, spend, companion, or recommendation source is copied into roulette persistence because no roulette persistence exists. P4-G adds no migration and does not access Development or Production databases.

## Acceptance coverage

- Eighteen Previews cover empty, 1, 2, 6, 12, 30, 120, WantToGo, visited, mixed, Photo, no Photo, result, long name, filtered-empty, small-screen, large-type, and Reduce Motion presentations.
- Engine tests cover empty/single/multiple pools, validity/tombstones, Global identity dedupe, status/city/session filters, deterministic ordering/default city, immediate repeat, eventual repeat, injectable random coverage, large-pool behavior, exact wheel geometry, active Visit summaries, Photos, tags, and Apple/manual identity fallbacks.
- Native UI E2E covers the Profile entry, candidate count, WantToGo filter, wheel/result, Restaurant Detail and back, result preservation, reroll without immediate repeat, offline persistent relaunch, empty, single, and 120-candidate states. XCTest screenshots are retained for result and large-pool visual review.

## Known boundaries

- List roulette is not implemented because the audited Web roulette does not formally support it.
- Category/cuisine, rating, price, distance, time, weather, and AI filters are not implemented.
- Session exclusions and the last result are intentionally not persisted or synchronized.
- The engine is uniform, not weighted. Future personalization must be a separately reviewed product decision and must not silently alter the meaning of the wheel.
- No true-device-only product dependency exists. Simulator covers the core logic and interaction; real-device animation, touch, haptic, and Reduce Motion remain an optional manual smoke check.
