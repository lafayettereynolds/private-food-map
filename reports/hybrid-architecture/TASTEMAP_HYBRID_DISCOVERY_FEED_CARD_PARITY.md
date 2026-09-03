# Taste Map Hybrid Discovery Feed Card Parity

Date: 2026-09-03
Scope: Batch 1 Discovery Closure — Activity / Recommendation Card composition only
Branch: `fix/hybrid-discovery-feed-card-parity`

## Result

The Hybrid Discovery card no longer uses the generic `large image → restaurant text → flat reason → equal pill actions` topology. Browser and Capacitor now use the same shared Activity Card frame and match the approved Legacy/Web composition at the structural level.

This report approves the **Card topology gate only**. It does not by itself declare every Discovery region or the whole Batch 1 visually approved.

## Root Cause

1. `TasteMapActivityCardFrame` encoded the wrong shared DOM order: header → media → Restaurant → rating → body → footer. The image therefore became the card's dominant top-level hero on every consumer.
2. `HybridDiscoveryPage.RecommendationCard` placed the recommender at the end of the body, flattened recommendation evidence into ordinary text/fact pills, separated Share as a text row, and rendered Restaurant actions as equal pills.
3. The Hybrid Discovery DTO transported the author's Visit rating but dropped the public Restaurant rating/sample summary already available in the native Discovery cache. Hybrid therefore could not preserve the reference card's two distinct rating semantics.
4. Activity and recommendation variants reused a component name, but did not actually preserve one topology and one action-group grammar across all five tabs.

## Implemented Composition

Recommendation variants now render:

`Restaurant identity + recommendation tag → public rating/sample + compact recommender/Visit context → horizontal Restaurant image → independent recommendation evidence block → social group (left) + circular Restaurant actions (right)`

Activity variants now render:

`author/time/visibility → Restaurant identity → specific Visit rating → horizontal Restaurant image → activity note when present → social group (left) + circular Restaurant actions (right)`

The five tabs `关注 / 为你推荐 / 同味之选 / 最新 / 趋势` use the same frame. Recommendation evidence is visible only on recommendation semantics; author headers and activity notes are visible only on activity semantics.

Current-only capabilities were retained inside the approved skeleton:

- source-user navigation and the source user's specific Visit rating;
- WantToGo state;
- Record Visit;
- Add to List;
- Roulette;
- Like / Comment / Share;
- city, sort, and Visit-rating filters;
- empty, omitted-optional, and missing-rating states.

## Rating Semantics

- `communityRating.valueOutOfFive` and `communityRating.sampleCount` are transported explicitly from the native Discovery cache.
- The public Restaurant rating is displayed on the 10-point visual scale used by the reference card.
- `activityRating` remains the source user's specific Visit rating on the 5-point scale.
- Missing Visit ratings remain `本次未评分`; they are never replaced by the public or aggregate Restaurant rating.

## Five-Tab Runtime Audit

| Tab | Shared frame | Restaurant before image | Social group | Restaurant action group | Semantic optional module |
| --- | --- | --- | --- | --- | --- |
| 关注 | PASS | PASS | PASS | PASS | author/time + activity context |
| 为你推荐 | PASS | PASS | PASS | PASS | recommendation evidence |
| 同味之选 | PASS | PASS | PASS | PASS | similarity evidence |
| 最新 | PASS | PASS | PASS | PASS | author/time + activity context |
| 趋势 | PASS | PASS | PASS | PASS | trend evidence |

## Visual Evidence

- Annotated three-way comparison: `screenshots/discovery-feed-card-parity/reference-vs-browser-vs-capacitor.png`
- Approved reference supplied by Lafayette: `screenshots/discovery-feed-card-parity/reference.png`
- Browser after: `screenshots/discovery-feed-card-parity/browser-after.png`
- Capacitor after: `screenshots/discovery-feed-card-parity/capacitor-after.png`
- Browser before: `screenshots/discovery-feed-card-parity/browser-before.png`

The comparison annotates structure, image position, rating position, action grouping, recommendation reason, user identity, and first-screen density.

## Verification

- `pnpm test -- --run`: 56 files, 392 tests passed.
- Focused Hybrid contract suite: 3 files, 39 tests passed.
- `pnpm run test:hybrid`: 15 TypeScript tests and 6 Swift bridge-package tests passed (the package emitted its existing unhandled-file warning).
- `pnpm run typecheck`: passed.
- `pnpm run hybrid:build:debug`: passed; Debug fixture and local-bundle verification passed.
- `pnpm run hybrid:stage:formal`: passed; Release Hybrid bundle verification and formal staging passed.
- `TasteMapUITests.testHybridDiscoverySharedProductAndVisualContract`: passed on the isolated `TasteMap Independent Audit` iPhone 17 Pro simulator. The test checks the five tabs, rating/source semantics, independent evidence block, Restaurant actions, WantToGo state, and social actions, then captures the Capacitor screenshot.
- Xcode Debug app/test build: passed as part of the focused UI test run.
- Xcode Release generic iOS Simulator build: passed.

## Design-System Compliance

- Core UI System: PASS for the shared Discovery card frame and existing tab/filter controls.
- Food & Dining Visual System: PASS; the canonical Hybrid Restaurant image renderer remains in use, including honest fallback when no lawful real image is available.
- Canonical Page Templates: PASS for the Activity Card topology gate.
- Duplicate/conflicting component count introduced: 0.
- Default-SwiftUI visual regression count introduced: 0; the Capacitor surface renders the shared Web card bundle.
- Remaining design-system gap in this scope: none.

## Integration Notes

1. The change reorders `TasteMapActivityCardFrame`, the Discovery/Community family's existing shared component. It is an in-scope family component, but Integration should resolve carefully if another branch independently changed the same frame or `CommunityPage`.
2. `TasteMapHybridDiscoveryItemDTO` and its Swift mirror gain the module-specific `communityRating` field. Integration must keep both TypeScript and Swift definitions, bridge mapping, and Debug fixtures together.
3. The staged Release Hybrid assets are generated from this branch and must be merged with the source changes; do not keep older hashed bundle files.
4. No Production endpoint, Worker, D1, R2, SyncEngine, Discovery API behavior, Profile, Map layout, or unrelated module was changed.
