# Taste Map Canonical Visual References

This directory is the index for visual references that are reliable enough to
constrain implementation. It intentionally links to the original tracked
evidence instead of duplicating images. A screenshot is not canonical merely
because it exists in `reports/`.

## Reference authority

1. Lafayette's latest explicit decision.
2. `docs/TASTEMAP_PRODUCT_DESIGN_RULES.md`.
3. A user-approved Web or historical screenshot listed below.
4. A current screenshot only as evidence of the implementation under audit.

When a screenshot conflicts with a later written decision, the written decision
wins. When no reliable screenshot exists, the surface is `REFERENCE_MISSING` and
must not be freely redesigned.

## Approved or reliable references

| Surface | Reference | What it constrains | Status |
| --- | --- | --- | --- |
| My Map | [`web-map-before.jpg`](../reports/full-product-parity-assets/web-map-before.jpg) | map-first topology, bottom add action, compact scope hierarchy | RELIABLE HISTORICAL; later title/filter/marker rules supersede individual controls |
| My List | [`web-list-before.jpg`](../reports/full-product-parity-assets/web-list-before.jpg) | dense list, Restaurant row hierarchy, bottom add action | RELIABLE HISTORICAL; later title-switch rule supersedes floating view switch |
| Discovery | [`web-discovery-before.jpg`](../reports/full-product-parity-assets/web-discovery-before.jpg) | header, five primary sections, city/filter hierarchy | RELIABLE HISTORICAL; content error state is not a card-layout reference |
| Profile / My | [`web-profile-before.jpg`](../reports/full-product-parity-assets/web-profile-before.jpg) | compact dashboard grouping and section order | RELIABLE HISTORICAL; current-only social/Premium/stat semantics must be fused |
| Add Restaurant | [`web-add-restaurant-before.jpg`](../reports/full-product-parity-assets/web-add-restaurant-before.jpg) | Search/Nearby/manual hierarchy | RELIABLE HISTORICAL; current Share ingestion and candidate confirmation are preserved |
| Restaurant Detail | [`web-restaurant-detail-before.jpg`](../reports/full-product-parity-assets/web-restaurant-detail-before.jpg) | hero-first information density, four rating references, upper-section order | RELIABLE HISTORICAL; current-only actions and downstream modules are preserved |
| Roulette | [`web-roulette-reference-top-module-6.png`](../reports/full-product-parity-assets/web-roulette-reference-top-module-6.png) | header and wheel geometry | APPROVED HISTORICAL |
| Roulette candidate management | [`web-roulette-reference-module-6.png`](../reports/full-product-parity-assets/web-roulette-reference-module-6.png) | candidate manager hierarchy and max-ten behavior | APPROVED HISTORICAL |
| Premium identity | [`premium-approved-hamburger.png`](../reports/product-ux-correction-assets/task-05-profile-lists-premium/premium-approved-hamburger.png) | hamburger badge only | APPROVED HISTORICAL ASSET |

## Written-contract canonical surfaces

The following surfaces have a locked written layout contract but no separately
approved pixel reference. Current screenshots are audit evidence, not a new
canonical source:

- Map/List final title-switch and natural-overlap marker behavior.
- Activity Card and Community rich-state composition.
- public profile and social safety controls.
- Lists and public-list layouts.
- Visit, Dish, and Photo editing.
- the five Analytics pages and five 9:16 posters.
- Settings, Backup, Sync, permissions, and storage.
- Premium paywall beyond the approved hamburger.

These surfaces require Lafayette visual approval if a choice is not completely
determined by the written contract.

## Current implementation evidence

Current-baseline screenshots for this audit are indexed at
[`reports/full-layout-parity/audit-screenshots/INDEX.md`](../reports/full-layout-parity/audit-screenshots/INDEX.md).
They are not promoted to canonical merely by being captured.

## Task C candidate registry

The final implementation atlas is indexed at
[`reports/full-layout-parity/final-atlas/INDEX.md`](../reports/full-layout-parity/final-atlas/INDEX.md).
Every item in this table is implementation evidence only. Its status is
**CANDIDATE_CANONICAL — pending Lafayette confirmation**; this registry does
not turn an automated PASS into visual approval.

| Surface family | Candidate evidence | Status |
| --- | --- | --- |
| My Map / My List / Filters | [`task-04-map-after.png`](../reports/full-layout-parity/final-atlas/task-04-map-after.png), [`task-04-list-after.png`](../reports/full-layout-parity/final-atlas/task-04-list-after.png), [`final-atlas-map-filter-sheet.png`](../reports/full-layout-parity/final-atlas/final-atlas-map-filter-sheet.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Discovery / Community | [`final-atlas-discovery-for-you.png`](../reports/full-layout-parity/final-atlas/final-atlas-discovery-for-you.png), [`p3-d-community-feed.png`](../reports/full-layout-parity/final-atlas/p3-d-community-feed.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Add Restaurant | [`full-parity-add-restaurant-nearby-after.png`](../reports/full-layout-parity/final-atlas/full-parity-add-restaurant-nearby-after.png), [`product-ux-manual-restaurant-preview.png`](../reports/full-layout-parity/final-atlas/product-ux-manual-restaurant-preview.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Restaurant Detail | [`task-04-restaurant-detail-after.png`](../reports/full-layout-parity/final-atlas/task-04-restaurant-detail-after.png), [`global-restaurant-detail-remote-after.png`](../reports/full-layout-parity/final-atlas/global-restaurant-detail-remote-after.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Visit / Dish / Photo | [`final-atlas-visit-core-form.png`](../reports/full-layout-parity/final-atlas/final-atlas-visit-core-form.png), [`final-atlas-visit-rich-photo-dish-context.png`](../reports/full-layout-parity/final-atlas/final-atlas-visit-rich-photo-dish-context.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Profile / public Profile / Lists | [`final-fixed-simulator-rich-premium.png`](../reports/full-layout-parity/final-atlas/final-fixed-simulator-rich-premium.png), [`core-parity-public-profile-after.png`](../reports/full-layout-parity/final-atlas/core-parity-public-profile-after.png), [`p4-f-own-public-ranking.png`](../reports/full-layout-parity/final-atlas/p4-f-own-public-ranking.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Roulette | [`p4-g-large-candidate-pool.png`](../reports/full-layout-parity/final-atlas/p4-g-large-candidate-pool.png), [`final-atlas-roulette-dark.png`](../reports/full-layout-parity/final-atlas/final-atlas-roulette-dark.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Analytics and five posters | [`p4-a-taste-profile.png`](../reports/full-layout-parity/final-atlas/p4-a-taste-profile.png), [`p4-a-9x16-poster.png`](../reports/full-layout-parity/final-atlas/p4-a-9x16-poster.png) and the remaining families in the atlas index | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Premium / Settings / Data | [`p4-h-free-paywall.png`](../reports/full-layout-parity/final-atlas/p4-h-free-paywall.png), [`final-atlas-settings-root.png`](../reports/full-layout-parity/final-atlas/final-atlas-settings-root.png), [`final-atlas-import-preflight.png`](../reports/full-layout-parity/final-atlas/final-atlas-import-preflight.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
| Dark / large text / state variants | [`task-04-map-dark-after.png`](../reports/full-layout-parity/final-atlas/task-04-map-dark-after.png), [`task09-rich-profile-premium.png`](../reports/full-layout-parity/final-atlas/task09-rich-profile-premium.png), [`final-atlas-visual-qa-discovery-error.png`](../reports/full-layout-parity/final-atlas/final-atlas-visual-qa-discovery-error.png) | CANDIDATE_CANONICAL — pending Lafayette confirmation |
