# Taste Map Full App Visual Layout Audit

> Task A — audit only
>
> Baseline: `fix/product-ux-correction-8-tasks@e7201e70acd88329d4334b2e1e9909136879b362`
>
> Fixed Simulator: iPhone 17 Pro, iOS 26.5,
> `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

## 1. Executive result

This audit did not change user-visible business layout. It decomposed the
available approved Web/history evidence, the active written design rules, the
current SwiftUI hierarchy, and the newest tracked screenshots into canonical
layout contracts.

- Audited surface/state groups: **36**.
- Reliable screenshot references: **9** reference entries covering **7 page
  families plus Roulette management and the Premium identity asset**.
- Written-contract-only surfaces without a separately approved pixel reference:
  **21**.
- Confirmed structural/section-order regressions in the currently audited rich
  primary screens: **0**.
- Confirmed global shared-component regressions: **1 pattern** across **38
  production `ContentUnavailableView` call sites in 18 files**.
- Confirmed current-only capabilities to preserve: **14 groups**.
- Decisions that still require Lafayette visual approval rather than automatic
  redesign: **9**.

The audit therefore does **not** infer that every screen is visually approved.
It says the primary rich templates are structurally aligned with the active
contracts, one unambiguous global state-component drift remains, and surfaces
without approved references must remain `VISUAL REVIEW REQUIRED` until Task C.

## 2. Method

Every page was evaluated in two steps:

1. **Product semantics** — data source, identity, state, actions, entry and
   return path were checked against the current code and active rules.
2. **Visual/layout contract** — safe area, top inset, header, section order,
   row/column topology, media ratio, CTA weight, spacing/density, overlays, and
   state layout were compared to reliable evidence.

Three independent verdicts are used:

- **Engineering PASS**: implementation compiles and the relevant automated
  contract exists.
- **Product PASS**: data and interaction semantics are correct.
- **Visual PASS**: Product PASS plus reliable reference/contract conformance and
  sufficient state screenshots.

An earlier automated PASS never upgrades a screen to Visual PASS by itself.

## 3. Canonical references and contracts

- Reference index: [`canonical-references/INDEX.md`](../../canonical-references/INDEX.md)
- Layout contract index: [`docs/layout-contracts/README.md`](../../docs/layout-contracts/README.md)
- Current baseline screenshots: [`audit-screenshots/INDEX.md`](audit-screenshots/INDEX.md)

Reliable references exist for My Map, My List, Discovery hierarchy, Profile
dashboard topology, Add Restaurant hierarchy, Restaurant Detail upper body,
Roulette, and the Premium hamburger. They are interpreted through later written
decisions; for example the old floating Map/List switch is superseded by the
centered title-icon switch, and old Profile statistics are fused with current
`去过 / 想去 / 总消费` semantics.

## 4. Full surface matrix

| # | Surface | Product semantics | Current layout vs contract | Reference | Audit category | Task B action |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | Root tabs / app shell | PASS | Three root tabs and floating add CTA preserved | written | PERMITTED_IOS_ADAPTATION | none |
| 2 | Navigation bars / sheets | PASS | Native navigation and sheets do not reorder product IA | written | PERMITTED_IOS_ADAPTATION | none |
| 3 | Primary tabs | PASS | Map and root Discovery use `TasteMapPrimaryTabBar` | written + Map/Discovery | CLOSED | none |
| 4 | Compact filters | PASS | Shared icon/value chips, 34/44 pt contract | written | CLOSED | none |
| 5 | Empty/auth/error states | PASS semantics | 38 production sites bypass canonical state component | written | **SHARED_COMPONENT_REGRESSION** | global shared-state closure |
| 6 | My Map — visited | PASS | centered title group → scopes → filters → dominant map | Web + written | CLOSED | verify only |
| 7 | My Map — want to go | PASS | same state/query topology | written | VISUAL REVIEW REQUIRED | capture Task C |
| 8 | My Map — recommendations | PASS; no fake local recommendation | same scope/filter state | written | VISUAL REVIEW REQUIRED | capture Task C |
| 9 | My Map — dense markers | PASS | independent natural overlap, no cluster | LF01 + written | CLOSED | preserve |
| 10 | My Map — selected/user location | PASS | deterministic selected layer and avatar marker | LF01 + written | CLOSED | preserve |
| 11 | My List | PASS | title switch/state preserved; dense rows | Web + written | CLOSED | verify only |
| 12 | Discovery shell | PASS | centered title and five equal tabs | Web + written | CLOSED | verify only |
| 13 | Following | PASS Community source | card language aligned; state component drifts | written | SHARED_COMPONENT_REGRESSION | state only |
| 14 | For You | PASS Discovery API | rich recommendation cards and shared filter | written | VISUAL REVIEW REQUIRED | capture Task C |
| 15 | Similar Taste | PASS Premium/auth/source | rich/insufficient/auth states exist; state renderer drifts | written | SHARED_COMPONENT_REGRESSION | state only |
| 16 | Latest | PASS Community source | activity card and concrete Visit rating | written | VISUAL REVIEW REQUIRED | capture Task C |
| 17 | Trending | PASS Discovery API/window | trend evidence and filter semantics | written | VISUAL REVIEW REQUIRED | capture Task C |
| 18 | Community / interactions | PASS | shared ActivityCard; like/comment/share/safety retained | written | CURRENT_ONLY_FEATURE_TO_PRESERVE | state only |
| 19 | Add Restaurant — Search | PASS provider search | first-class search and candidate preview | Web + written | CLOSED | verify only |
| 20 | Add Restaurant — Nearby | PASS fresh GPS | second content group; real distances | Web + written | CLOSED | verify only |
| 21 | Add Restaurant — Share/manual | PASS | current-only Share preserved; one manual card | written | CURRENT_ONLY_FEATURE_TO_PRESERVE | none |
| 22 | Restaurant Detail | PASS single body | canonical 18-section order and compact action row | Web + written | CLOSED | preserve |
| 23 | Visit editor | PASS optional/local-first | complete form; no approved pixel reference | written | REFERENCE_MISSING | Lafayette review |
| 24 | Dish / Photo | PASS | real media/state semantics; no approved pixel reference | written | REFERENCE_MISSING | Lafayette review |
| 25 | My Profile | PASS | compact dashboard topology and current social stats | Web + written | FUSE / VISUAL REVIEW REQUIRED | no automatic redesign |
| 26 | Public Profile | PASS privacy/source | current-only public/social/safety content | written | CURRENT_ONLY_FEATURE_TO_PRESERVE | capture Task C |
| 27 | Social search/follow/friend | PASS | current-only flows; no approved pixel reference | written | REFERENCE_MISSING | Lafayette review |
| 28 | Lists / public Lists | PASS | complete list product and canonical images | written | CURRENT_ONLY_FEATURE_TO_PRESERVE | state only |
| 29 | Roulette | PASS | approved wheel, pool, pointer, empty slots | approved Web | CLOSED | verify only |
| 30 | My Taste Profile | PASS data semantics | central hero/callouts and poster CTA | written | VISUAL REVIEW REQUIRED | capture Task C |
| 31 | Best Companion | PASS data semantics | Analysis family; no separately approved pixel reference | written | REFERENCE_MISSING | Lafayette review |
| 32 | Who Recommends Best | PASS data semantics | Analysis family; `最坑推荐来源` retained | written | REFERENCE_MISSING | Lafayette review |
| 33 | Monthly Recap | PASS data semantics | Analysis family; period navigation retained | written | REFERENCE_MISSING | Lafayette review |
| 34 | Annual Recap | PASS data semantics | Analysis family; trajectory retained | written | REFERENCE_MISSING | Lafayette review |
| 35 | Five 9:16 posters | PASS independent renderer | shared footer/hero/callouts; real image policy | written | VISUAL REVIEW REQUIRED | atlas + Lafayette review |
| 36 | Premium / Settings / Backup / Sync | PASS architecture | approved badge; utility IA uses native adaptation | badge + written | REFERENCE_MISSING | state closure + capture |

## 5. Reference decomposition

### My Map / My List

- **Viewport/safe area:** content begins below the status safe area and reserves
  the root tab bar/home indicator.
- **Header:** one centered title-icon group; the complete group, not text alone,
  owns centerX.
- **Vertical order:** title → primary scope → filters → content.
- **Anchors:** add action centered above tab bar; location control trailing;
  markers live below controls.
- **Density:** no extra view-mode tier; Map stays dominant; List rows stay dense.
- **Current result:** conforms. LF01/LF02 must not regress during state cleanup.

### Discovery

- **Header:** centered title and one concise line.
- **Navigation:** five same-level equal tabs, no intermediate hub selector.
- **Filter:** same compact language as Map.
- **Content:** Restaurant/activity media leads the story; author/evidence/rating
  and actions remain subordinate but visible.
- **Current result:** rich structure conforms. Empty/auth/error states bypass
  the canonical state component.

### Profile

- **Topology:** identity → relationships → horizontal stats → paired primary
  actions → Memories → Lists → Insights → footprints → settings.
- **Current-only preservation:** following/followers, Premium, public sharing,
  Analytics, Lists, safety and settings cannot be removed to mimic old Web.
- **Current result:** topology conforms. Exact header density and long-name
  wrapping remain a Lafayette visual-review item because the historical Web
  reference and later current-only additions cannot define one exact height.

### Add Restaurant and Restaurant Detail

- Search/Nearby/manual grouping and standard candidate Detail are correct.
- The global Detail body and canonical image renderer are single-source.
- Direct screenshot evidence confirms hero-first order and compact actions.
- Physical GPS ordering and external Share handoff remain device gates, not
  layout regressions.

### Roulette

- Candidate panel, wheel geometry, pointer, pool/segment identity, honest empty
  slots, and result flow match the approved historical evidence.
- No unambiguous visual correction is justified in Task B.

### Analytics and posters

- The current Taste Profile evidence demonstrates the required central Hero,
  four surrounding callouts, connecting lines, Restaurant evidence, and
  independent 9:16 poster.
- The other four families have written contracts and generated evidence but no
  separately approved pixel reference. They stay visual-review candidates.

## 6. Global-pattern audit

| Shared pattern | Definition count | Production consumers/evidence | Result |
| --- | ---: | --- | --- |
| `TasteMapDesignTokens` | 1 | core shared components | PASS |
| `TasteMapPrimaryTabBar` | 1 | Map + root Discovery | PASS |
| `TasteMapFilterBar/Chip` | 1 each | Map + Discovery | PASS |
| `TasteMapActivityCard` | 1 | Discovery + Community | PASS |
| `TasteMapActivityRatingBadge` | 1 | Discovery + Community | PASS |
| `RestaurantDetailStandardBody` | 1 | every formal entry source | PASS |
| `TasteMapRestaurantImage` / policy | 1 renderer/policy | all Restaurant-facing surfaces | PASS (LF02 closed) |
| `TasteMapEmptyState` | 1 | only one current product use; 38 bypasses | **FAIL** |
| `FoodDiningVisualLibrary` | 1 | decorative/data-linked adapters | PASS |
| `SharePosterBrandFooter` | 1 | five poster families | PASS |

## 7. Top findings

1. **P2 — SHARED_COMPONENT_REGRESSION:** 38 runtime
   `ContentUnavailableView` sites in 18 production files bypass the locked
   Taste Map state layout. Fix globally in Task B without changing state
   semantics.
2. **P2 — REFERENCE_MISSING:** Visit/Dish/Photo lack a separately approved
   pixel reference; preserve their correct semantics and request visual review.
3. **P2 — REFERENCE_MISSING:** Public Profile and the social hub are current-only
   capabilities; Legacy cannot define their final geometry.
4. **P2 — VISUAL REVIEW REQUIRED:** Profile has correct topology, but the exact
   compact header height with current social/Premium additions needs a human eye.
5. **P2 — VISUAL REVIEW REQUIRED:** the five posters satisfy the written family
   contract but are not Lafayette-approved canonical screenshots yet.
6. **P2 — STATE COVERAGE:** rich screenshots exist for primary pages; the final
   atlas must still capture empty, error, offline, long-text, missing-photo,
   Free, Premium, and Dark states.
7. **P2 — DEVICE GATE:** GPS freshness/Reduced Accuracy/Nearby physical ordering
   cannot be visually certified by deterministic Simulator fixtures.
8. **P2 — DEVICE GATE:** poster save/share and Apple Maps handoff need physical
   device acceptance.
9. **P2 — EXTERNAL GATE:** official public share URL/App Icon configuration is
   absent; no fake QR or App Icon may be invented.
10. **P2 — VISUAL REVIEW REQUIRED:** Settings has correct IA but no approved
    screenshot reference.
11. My Map rich topology matches the current title/scope/filter contract.
12. LF01 marker natural overlap and z-order are closed and protected.
13. LF02 Restaurant image rendering is closed and protected.
14. Discovery's five-section product hierarchy is correct at the root shell.
15. Activity rating correctly uses the concrete Visit rating.
16. Restaurant Detail remains one shared body across entry sources.
17. Add Restaurant preserves current-only Share ingestion and exact GPS logic.
18. Roulette matches the approved wheel/pool geometry.
19. Analytics retains a separate Analysis theme; it has not leaked into Core UI.
20. No evidence supports deleting any current-only Social, Premium, sharing,
    Analytics, sync, backup/import, or safety capability.

## 8. Current-only capability groups to preserve

1. Taste Map UUID and provider-neutral identities.
2. Local-first sync, tombstones, account isolation, and auth.
3. external Share ingestion.
4. public profile and social graph.
5. Community like/comment/share/report/block safety.
6. Same Taste and versioned Discovery.
7. Lists/public Lists.
8. Premium/StoreKit architecture.
9. five Analytics/poster families.
10. On This Day.
11. Backup/Import and exact-duplicate protection.
12. Settings/permissions/storage/sync presentation.
13. canonical Restaurant image renderer.
14. natural-overlap marker z-order and current-user avatar.

## 9. Lafayette approval queue created by Task A

The following are intentionally not auto-fixed:

1. exact compact Profile header density with long names and current social data;
2. Visit editor final pixel composition;
3. Dish/Photo manager final pixel composition;
4. public profile/social hub final pixel composition;
5. Lists/public Lists final pixel composition;
6. the four non-Taste-Profile Analysis page compositions;
7. all five poster compositions as canonical final art;
8. Premium paywall geometry beyond the approved hamburger;
9. Settings/Data utility geometry beyond the locked information architecture.

Task C will provide a screenshot atlas and an exact option/recommendation queue.

## 10. Task B authorized scope

Task B may automatically fix exactly one proven global pattern:

- replace production `ContentUnavailableView` bypasses with the shared
  `TasteMapEmptyState` system, extending the shared component only as needed for
  a secondary action and compact embedding;
- preserve every state title, explanation, action, identifier, and business
  branch;
- do not alter LF01 markers, LF02 images, page section order, backend, schema,
  auth, sync, import, Premium entitlement, or current-only capability.

No other page redesign is authorized by this audit.

## 11. Task A acceptance

- User-facing business code changed: **NO**.
- SwiftData / Worker / D1 / Production changed: **NO**.
- Canonical references indexed: **YES**.
- Major layout contracts created: **YES**.
- Current screenshot evidence indexed: **YES**.
- Unambiguous Task B scope identified: **YES**.
- `ProductDesignRulesTests`: **5/5 PASS**.
- Debug iPhone 17 Pro Simulator build: **PASS**.
- Release generic iPhone Simulator build: **PASS**.
