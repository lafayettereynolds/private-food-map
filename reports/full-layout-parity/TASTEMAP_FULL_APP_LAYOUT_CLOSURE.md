# Taste Map — Full App Layout Parity Closure (Task B)

Date: 2026-09-01  
Branch: `fix/product-ux-correction-8-tasks`  
Task B baseline: `4722f5e` (`Audit full app layout parity`)  
Fixed Simulator: iPhone 17 Pro / iOS 26.5 / `E4F3EED9-89D8-405C-B4CB-7CA816CE3405`

## 1. Scope and decision boundary

Task A separated engineering correctness, product semantics, and visual
approval. It found one unambiguous, repository-wide layout-system regression
that could be closed without inventing a new product decision:

- production screens bypassed the canonical Taste Map state renderer through
  38 direct `ContentUnavailableView` call sites in 18 app files;
- two Preview fixtures repeated the same bypass;
- this contradicted the active canonical-template rule requiring product empty,
  unavailable, and recoverable error states to use the shared Taste Map state
  language.

No ambiguous spacing, density, content-order, or reference-dependent decision
was changed in Task B. Those decisions remain in the Lafayette visual approval
queue produced by Task C.

## 2. Closed regression

### Before

State presentation varied by feature. Raw system `ContentUnavailableView`
implementations independently chose icon size, spacing, action style, and state
container behavior in Discovery, Community, Lists, Map/List, Premium, Profile,
Restaurant Detail/Search, Roulette, Visit/Dish, analysis poster errors, and
public sharing.

### After

All app-target and Preview call sites now use `TasteMapEmptyState`.

The shared component gained only the capabilities needed to preserve the
existing product semantics while removing duplicated presentation:

- `.card` and `.embedded` presentation modes;
- optional primary and secondary actions;
- action accessibility identifiers;
- state accessibility identifier;
- existing Food & Dining visual kind support remains the decorative/fallback
  layer and does not create data claims.

Each migrated state keeps its original:

- title and explanatory copy;
- retry, sign-in, search, manage, clear, dismiss, or navigation action;
- action availability and feature gate;
- accessibility/UI-test identifier where one already existed;
- surrounding navigation, data source, and business state.

No feature was deleted, no empty state was hidden, and no error was converted to
fake success content.

## 3. Global coverage

The migration covers these product surfaces:

- companion and recommendation-source pickers;
- public Restaurant/Profile/List sharing;
- analysis poster generation errors;
- Discovery and Community loading/error/empty/login states;
- Community comments and interaction states;
- Restaurant Lists and list-editor states;
- My Map/My List filtered-zero state;
- browse/search/nearby empty and error states;
- Premium product/configuration states;
- Profile logged-out state;
- public profile/social collaboration states;
- Restaurant Detail public photo state;
- Roulette empty states;
- Dish manager and taste-footprint states.

A design governance regression test scans the production Swift source and fails
if a future feature directly reintroduces `ContentUnavailableView`.

## 4. Visual evidence and two-pass review

Evidence index: [`closure-screenshots/INDEX.md`](closure-screenshots/INDEX.md)

### Round 1

Map, List, Discovery, and Profile were relaunched from deterministic fixtures
and captured after the shared-state migration. Result: **PASS**.

- canonical page order and navigation remained unchanged;
- Map/List title switch, scopes, filters, and Add Restaurant CTA remained in
  their established layers;
- Discovery retained five equal-priority primary tabs and compact filters;
- Profile retained compact dashboard hierarchy;
- no safe-area or Tab Bar overlap was introduced.

### Round 2

The same deterministic UI path was rebuilt, relaunched, and captured again.
Result: **PASS**.

- output was stable across launches;
- no state-dependent shift appeared in the four key pages;
- the Roulette empty fixture displayed the shared Food & Dining state, retained
  its real Search Restaurant action, and remained scroll-safe.

The audit baseline screenshots are retained beside both rounds. They are not
presented as a newly approved visual reference; they are regression evidence
that Task B did not disturb already-established page topology.

## 5. Accessibility

- Primary and secondary actions remain real `Button` controls.
- Existing explicit UI-test/accessibility identifiers are preserved through the
  shared component.
- The shared visual remains hidden from VoiceOver as decorative content while
  title, message, and actions remain readable.
- Dynamic Type continues to drive text layout; no fixed-height state container
  was introduced.

## 6. Automated verification

| Check | Result |
| --- | --- |
| `ProductDesignRulesTests` | PASS — 6 tests, including canonical state renderer scan |
| `testP4GRouletteEmptyState` | PASS — action and empty semantics retained |
| Core Map/List/Discovery/Profile visual path — round 1 | PASS |
| Core Map/List/Discovery/Profile visual path — round 2 | PASS |
| Debug Simulator build | PASS |
| Release Simulator build | PASS |
| Swift source search for `ContentUnavailableView` in app target | PASS — 0 occurrences |
| `git diff --check` | PASS |

The pre-existing Xcode resource-manifest/location simulator messages remain
outside this change and did not fail build or tests.

## 7. Safety and non-goals

Task B changed no:

- SwiftData schema or business model;
- authentication, sync, import, backup, or account-deletion behavior;
- Worker, D1, R2, or Production environment;
- signing, capability, Bundle Identifier, or App Icon;
- Restaurant image priority or canonical image renderer;
- map marker ordering/overlap behavior;
- product navigation hierarchy.

## 8. Closure result

The only Task A finding that was both global and unambiguous is **CLOSED**.
Reference-dependent visual choices were deliberately not guessed. They advance
to Task C as explicit Lafayette approval items rather than being mislabeled as
automatic failures or automatic passes.

