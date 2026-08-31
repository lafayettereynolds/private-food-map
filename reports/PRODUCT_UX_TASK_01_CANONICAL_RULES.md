# Product UX Correction — Task 01 Acceptance

## Status

PASS — the canonical product rules and shared component contracts are now explicit and compile in both Debug and Release.

## Baseline

- Branch: `fix/product-ux-correction-8-tasks`
- Base: `main@7e67c65258e1b4db9ee2ab45def242b072b0c1f6`
- Source priority and prohibited regressions are recorded in `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md`.
- The original main worktree's modified `project.pbxproj`, reports, `pnpm-workspace.yaml`, and stash were not touched.

## Shared component result

- Added canonical `TasteMapFilterSemantic` symbols, including a non-GPS static City symbol.
- Added `TasteMapFilterChip` with a 34-point visible pill, 44-point hit target, selected/count/accessibility semantics, and pressed feedback.
- Added one horizontal `TasteMapFilterBar` container.
- Added `TasteMapPrimaryTabBar` for equal My Map and Discovery primary navigation.
- Extended `TasteMapEmptyState` to accept decorative Food/Dining artwork without claiming a data meaning.
- Kept `RestaurantDetailStandardBody` as the single Restaurant body contract.
- Kept `DiscoveryRestaurantQuickActions` as the current shared Restaurant action row pending the Task 02 activity-card integration.
- Changed the default Food/Dining palette from uniform brand blue to restrained, category-stable natural accents; explicit per-call colors remain supported.

## Visual evidence

The screenshot below freezes the pre-adoption baseline. It honestly shows the old separate Map/List segmented row and the old `适合你` scope that Task 02 must remove; Task 01 did not falsely claim those screen-level changes were already complete.

- [Canonical baseline before](product-ux-correction-assets/task-01-canonical-baseline-before.png)

Task 02 will provide the corresponding screen-level after evidence when Map and Discovery adopt the shared components.

## Tests and builds

- `ProductDesignRulesTests`: PASS (3/3)
  - complete filter semantics
  - static City icon contract
  - stable decorative Food/Dining selection
- Debug Simulator build: PASS
- Release Simulator build: PASS
- Existing unrelated Swift concurrency and StoreKit deprecation warnings were observed but not changed.

## Scope safety

- SwiftData schema: unchanged
- Worker/D1/API: unchanged
- Signing/Team/Capabilities: unchanged
- Production: not accessed
- App Icon: unchanged
