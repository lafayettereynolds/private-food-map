# Taste Map Layout Contracts

These contracts translate approved product evidence into implementation-ready
geometry and hierarchy. They do not replace
`docs/TASTEMAP_PRODUCT_DESIGN_RULES.md`; they make its page templates auditable.

Each contract separates:

- **Semantics** — what data and action the surface represents.
- **Structure** — order, grouping, row/column relationships, and anchors.
- **Geometry** — insets, control sizes, ratios, safe-area behavior, and density.
- **States** — normal, rich, empty, loading, error, offline, long text, and Dark.
- **Permitted iOS adaptation** — system behavior that may differ without moving
  product hierarchy.
- **Prohibited regressions** — known wrong structures.

## Contract index

1. [`GLOBAL_SHELL_AND_STATES.md`](GLOBAL_SHELL_AND_STATES.md)
2. [`MY_MAP_AND_LIST.md`](MY_MAP_AND_LIST.md)
3. [`DISCOVERY_AND_COMMUNITY.md`](DISCOVERY_AND_COMMUNITY.md)
4. [`RESTAURANT_ACQUISITION.md`](RESTAURANT_ACQUISITION.md)
5. [`RESTAURANT_DETAIL.md`](RESTAURANT_DETAIL.md)
6. [`VISIT_DISH_AND_PHOTO.md`](VISIT_DISH_AND_PHOTO.md)
7. [`PROFILE_SOCIAL_AND_LISTS.md`](PROFILE_SOCIAL_AND_LISTS.md)
8. [`ROULETTE.md`](ROULETTE.md)
9. [`ANALYTICS_AND_POSTERS.md`](ANALYTICS_AND_POSTERS.md)
10. [`PREMIUM_SETTINGS_AND_DATA.md`](PREMIUM_SETTINGS_AND_DATA.md)

## Acceptance rule

An Engineering PASS proves build/runtime correctness. A Product PASS proves
semantics and entry paths. A Visual PASS additionally requires conformance to
the applicable contract and a reliable reference or Lafayette approval.
