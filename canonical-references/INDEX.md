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
