# Taste Map — Final Full App Visual Acceptance

Date: 2026-09-01

Branch: `fix/product-ux-correction-8-tasks`

Fixed Simulator: iPhone 17 Pro / iOS 26.5 /
`E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

## Executive Summary

Task A audited **36 user-facing surface/state groups**. Task B closed the one
unambiguous global state-renderer regression. Task C produced a **76-image**
final atlas, re-ran the combined unit/integration and critical UI paths, and
separated objective closure from unresolved human art-direction decisions.

| Acceptance measure | Final result |
| --- | ---: |
| User-facing surface/state groups audited | 36 |
| CLOSED surface/state groups | 27 |
| PENDING LAFAYETTE VISUAL APPROVAL decisions | 9 |
| EXTERNAL / DEVICE GATE items | 6 |
| Remaining objective layout regressions | **1** (target 0) |
| Global Pattern Regressions | **0** |
| Duplicate active layout components | **0** |
| Raw/default SwiftUI visual regressions | **0** |
| Current-only feature loss | **0** |

The remaining objective regression is not hidden in the Lafayette decision
queue: at actual `accessibility-extra-extra-large`, compact high-density
Profile/Discovery/Roulette chrome remains operable and scrollable but loses
visible values through truncation and over-scaling. It requires a focused
adaptive-layout correction before accessibility closure; it is not a subjective
design choice and is not a Production or device gate.

The images Lafayette should inspect first are:

1. [standard My Map](final-atlas/task-04-map-after.png) and
   [actual Accessibility Extra Extra Large Map](final-atlas/task09-rich-map-accessibility.png);
2. [Profile Premium dashboard](final-atlas/final-atlas-profile-premium-analytics.png),
   [long-name Profile](final-atlas/final-atlas-visual-qa-long-text-profile.png),
   and [actual Accessibility Extra Extra Large Profile](final-atlas/task09-rich-profile-premium.png);
3. [Discovery rich state](final-atlas/task09-rich-discovery-accessibility.png),
   [actual Dark](final-atlas/core-parity-discovery-dark.png), and
   [error/retry](final-atlas/final-atlas-visual-qa-discovery-error.png);
4. the [approved Roulette composition](final-atlas/p4-g-large-candidate-pool.png),
   [actual Dark](final-atlas/final-atlas-roulette-dark.png), and
   [actual Accessibility Extra Extra Large](final-atlas/final-atlas-roulette-large-text.png);
5. the five 9:16 posters beginning with
   [My Taste Profile](final-atlas/p4-a-9x16-poster.png).

The fixed Simulator's final handoff state is captured in
[`final-fixed-simulator-rich-premium.png`](final-atlas/final-fixed-simulator-rich-premium.png):
logged in, deterministic Rich Demo data, Premium Active, Light appearance, and
the standard content-size category.

## 1. Final evidence set

- Full atlas: [`final-atlas/INDEX.md`](final-atlas/INDEX.md)
- Lafayette-only decisions:
  [`TASTEMAP_LAFAYETTE_VISUAL_APPROVAL_QUEUE.md`](TASTEMAP_LAFAYETTE_VISUAL_APPROVAL_QUEUE.md)
- Task A audit: [`TASTEMAP_FULL_APP_LAYOUT_AUDIT.md`](TASTEMAP_FULL_APP_LAYOUT_AUDIT.md)
- Task B closure: [`TASTEMAP_FULL_APP_LAYOUT_CLOSURE.md`](TASTEMAP_FULL_APP_LAYOUT_CLOSURE.md)
- Canonical reference registry: [`../../canonical-references/INDEX.md`](../../canonical-references/INDEX.md)
- Layout contracts: [`../../docs/layout-contracts/README.md`](../../docs/layout-contracts/README.md)

Every final screenshot remains `CANDIDATE_CANONICAL`. This task does not claim
Lafayette approval that has not happened.

## 2. Reference versus final Simulator

| Surface | Reference | Final evidence | Composition/hierarchy conclusion | Status |
| --- | --- | --- | --- | --- |
| My Map | [`web-map-before.jpg`](../full-product-parity-assets/web-map-before.jpg) + later title/marker rules | [`task-04-map-after.png`](final-atlas/task-04-map-after.png) | later centered title-icon switch, three scopes, compact chips, map-first viewport and bottom CTA preserved | CLOSED |
| My List | [`web-list-before.jpg`](../full-product-parity-assets/web-list-before.jpg) + later title-switch rule | [`task-04-list-after.png`](final-atlas/task-04-list-after.png) | dense Restaurant rows, shared query state and bottom CTA preserved without a second view-mode row | CLOSED |
| Discovery | [`web-discovery-before.jpg`](../full-product-parity-assets/web-discovery-before.jpg) | [`final-atlas-discovery-for-you.png`](final-atlas/final-atlas-discovery-for-you.png) | centered title, five equal-level sections, compact filters, media-led content and concrete Visit rating preserved | CLOSED for topology; exact non-reference states remain candidates |
| Profile | [`web-profile-before.jpg`](../full-product-parity-assets/web-profile-before.jpg) | [`final-atlas-profile-premium-analytics.png`](final-atlas/final-atlas-profile-premium-analytics.png) | identity → relationships → `去过/想去/总消费` → paired actions → Memories → Lists → Insights preserved with current-only Social/Premium | PENDING LAFAYETTE VISUAL APPROVAL for exact header density |
| Add Restaurant | [`web-add-restaurant-before.jpg`](../full-product-parity-assets/web-add-restaurant-before.jpg) | [`full-parity-add-restaurant-nearby-after.png`](final-atlas/full-parity-add-restaurant-nearby-after.png) | Search/Nearby/manual order retained; current Share ingestion and explicit candidate confirmation fused without duplicate flow | CLOSED; real GPS remains DEVICE GATE |
| Restaurant Detail | [`web-restaurant-detail-before.jpg`](../full-product-parity-assets/web-restaurant-detail-before.jpg) | [`task-04-restaurant-detail-after.png`](final-atlas/task-04-restaurant-detail-after.png), [`global-restaurant-detail-local-after.png`](final-atlas/global-restaurant-detail-local-after.png) | one hero-first body, rating references, photos, overview and history reused across local and remote entries | CLOSED |
| Roulette | approved Web top/manager references | [`p4-g-large-candidate-pool.png`](final-atlas/p4-g-large-candidate-pool.png) | candidate panel, max-ten pool, pointer, one-to-one segments and result remain aligned | CLOSED at normal size; accessibility layout follow-up remains |
| Premium identity | approved hamburger asset | [`core-parity-approved-premium-hamburger.png`](final-atlas/core-parity-approved-premium-hamburger.png) | the approved historical asset remains unchanged | CLOSED |

## 3. CLOSED product/layout groups

The following are closed for Engineering + Product + applicable visual
contract at normal supported layouts:

1. Root tabs and app shell.
2. Native navigation/sheet adaptation.
3. Shared primary-tab renderer.
4. Shared compact FilterBar and semantic icons.
5. Canonical empty/auth/error state renderer.
6. My Map visited topology.
7. My Map want-to-go state/query preservation.
8. My Map recommendation state/query preservation.
9. Independent natural-overlap Restaurant markers.
10. Deterministic selected/rating/visit-count/stable-ID marker ordering.
11. My List and canonical Restaurant rows.
12. Discovery shell and five peer sections.
13. Following activity source and concrete Visit rating.
14. For You source/actions/reasons.
15. Same Taste source and honest insufficient/auth states.
16. Latest activity source.
17. Trending window/source.
18. Community interactions and safety actions.
19. Add Restaurant Search.
20. Add Restaurant Nearby layout and honest state handling.
21. Add Restaurant Share/manual/current-only acquisition flows.
22. Global canonical Restaurant Detail body.
23. Canonical Restaurant image priority/renderer across all consumers.
24. Approved Roulette wheel/pool geometry at normal text sizes.
25. On This Day entry and Restaurant navigation.
26. Premium approved hamburger identity and honest Free state.
27. Canonical state component use across Settings/Data and feature surfaces.

`CLOSED` does not erase the separate device/external checks below and does not
promote the nine subjective candidates to approved canonicals.

## 4. PENDING LAFAYETTE VISUAL APPROVAL

Nine decisions remain, all documented with two concrete options and a
recommendation in the dedicated approval queue:

1. Profile compact identity density.
2. Visit editor final pixel composition.
3. Dish/Photo manager final composition.
4. Public Profile/social hub geometry.
5. Lists/public Lists final density.
6. Four non-Taste-Profile Analysis compositions.
7. Five posters as final social campaign art.
8. Premium Paywall geometry beyond the approved hamburger.
9. Settings/Data utility geometry.

No objective bug has been delegated to Lafayette in that queue.

## 5. EXTERNAL / DEVICE GATES

1. Physical GPS freshness, Reduced Accuracy, foreground refresh, and real
   Nearby ordering.
2. Real iPhone safe areas, home indicator, keyboard, haptics, and rotation
   behavior.
3. Photo-library limited/full/denied behavior and poster Save authorization.
4. System Share Sheet, Apple Maps/AMap handoff, and Share Extension ingestion
   from real third-party apps.
5. Production public URL, AASA, QR destination, revoked/deleted public links.
6. StoreKit Sandbox/TestFlight products, purchase, restore, refund/revocation,
   and final Paywall product facts.

None was bypassed with fake Production configuration.

## 6. Objective accessibility layout follow-up

The Task C harness initially passed tests by sending an ineffective app launch
argument. Task C corrected the evidence procedure by changing the fixed
Simulator's actual system appearance and actual preferred content size, then
restoring both settings.

At true `accessibility-extra-extra-large`:

- primary navigation remains reachable and the shared tab bar becomes
  horizontally scrollable;
- page ScrollViews and core actions remain reachable;
- however high-density Profile values and some compact chrome are visually
  truncated or oversized;
- the root Add Restaurant CTA and bottom navigation consume too much vertical
  attention relative to content.

Severity: **P1 accessibility layout regression**. It does not change business
data or create a security issue, but this report does not claim a complete
Dynamic Type Visual PASS. A focused adaptive-layout task should address it
without globally disabling Dynamic Type or merely capping all text sizes.

## 7. State coverage

The final evidence covers:

- rich, normal, empty, missing-photo, error/retry, offline cache;
- Free and Premium;
- long names/text;
- actual Light and Dark system appearances;
- actual Accessibility Extra Extra Large content size;
- local and remote Restaurant Detail entry sources;
- five Analytics pages and five independent 9:16 posters;
- Backup privacy, Import preflight/blocking/plan, Sync pending, Permissions,
  and About.

Loading is a transient state guarded by the state contract and automated
behavior. It is not promoted to a canonical still from a timing race.

## 8. Component consistency

| Contract | Result |
| --- | --- |
| `TasteMapPrimaryTabBar` | one active implementation; Map + Discovery |
| `TasteMapFilterBar` / `TasteMapFilterChip` | one active visual language; semantic icon/value strategy |
| `TasteMapActivityCard` / rating badge | shared Discovery + Community; concrete Visit rating only |
| `TasteMapEmptyState` | one canonical renderer; raw production `ContentUnavailableView` = 0 |
| `TasteMapRestaurantImage` / priority policy | one canonical renderer/policy across Restaurant-facing UI |
| `RestaurantDetailStandardBody` | one canonical Detail body across entry sources |
| `FoodDiningVisualLibrary` | decorative/honest fallback only; never covers lawful real imagery |
| `SharePosterBrandFooter` | shared by all five poster families |

Duplicate active layout components: **0**.

## 9. Automated verification

| Check | Final result |
| --- | --- |
| Full iOS unit/integration target | PASS — **629 tests / 64 suites** |
| Main critical UI atlas selection | PASS after focused reliability reruns — 31 paths |
| Visual QA state atlas | PASS — empty, long text, missing photo, error, Dark |
| Supplemental UI paths | PASS — 7 paths |
| Actual system Dark evidence | PASS — Map, Discovery/Profile, Roulette |
| Actual Accessibility Extra Extra Large evidence | PASS as evidence capture; visual issue documented above |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Generic iOS Device Release build, unsigned | PASS |
| Release purity scan | PASS — DEBUG Visual QA/login/Premium fixture strings absent |
| Production `ContentUnavailableView` source scan | PASS — 0 |
| `git diff --check` | PASS |

The two first-pass UI failures were test-harness issues, not accepted product
failures: one asserted accessibility state against `label` rather than `value`;
the other did not scroll a lazy Visit section into the accessibility tree. Both
were corrected and passed focused reruns. No production filter or Visit logic
was changed for those reruns.

## 10. Release safety and scope

Task C changed no SwiftData schema, API, Worker, D1/R2, Production environment,
authentication, sync, import/backup semantics, StoreKit entitlement, signing,
capability, Bundle Identifier, App Icon, or current-only product capability.

The only app-source adjustment is inside existing `#if DEBUG` Visual QA fixture
handling so deterministic `.error` and `.offline` states can be captured while
remaining authenticated. Release compilation and the release binary scan prove
that this harness does not enter the Release app.

## 11. Final conclusion

- Objective normal-layout regressions found by Task A/B: **CLOSED**.
- Global shared-component regression: **CLOSED**.
- Lafayette-only design choices: **9 pending** with exact evidence/options.
- External/device gates: **6**.
- Current-only feature loss: **0**.
- Newly exposed objective accessibility layout issue: **1 P1 follow-up**.

This Task C report completes the evidence and decision closure requested by the
ZIP. It deliberately stops automatic visual modification after documenting the
true large-text result. The fixed Simulator is left running a Rich Demo,
logged-in, Premium Active state for Lafayette's review.
