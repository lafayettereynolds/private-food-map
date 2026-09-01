# Discovery and Community Layout Contract

## Discovery shell

1. centered `发现` title;
2. concise centered explanation;
3. equal primary tabs: `关注 / 为你推荐 / 同味之选 / 最新 / 趋势`;
4. one compact horizontal FilterBar;
5. content feed.

There is no extra `发现餐厅 / 社区动态` tier. `关注` and `最新` may render
Community-backed activities inside this single five-tab shell; the underlying
source does not create a second product navigation hierarchy.

## Filters

Use the same `TasteMapFilterBar`, `TasteMapFilterChip`, icons, heights, active
states, and hit targets as My Map. City is a compact building-labelled value.
Mode-specific filters appear only when meaningful; a missing dimension does not
reserve blank space.

## Activity/recommendation card

The shared card preserves:

- author/avatar/time/visibility when an activity has an author;
- Restaurant media, name, city/address, and recommendation/activity context;
- the author's concrete Visit rating, or `未评分`;
- recommendation reasons/similarity/trend evidence when available;
- social actions for Community content;
- compact Restaurant actions;
- a separate share action.

Restaurant aggregate rating never substitutes for an Activity rating. Rich
image media has stable ratio; missing media uses the canonical fallback.

## States

Each of the five tabs covers loading, content, empty, error, offline cache, and
long text. Similar Taste additionally covers authentication, entitlement,
insufficient sample, and content. Community covers deleted/private/blocked and
comment/like failure without exposing inaccessible content.

## Permitted adaptation

Native pull-to-refresh, contextual safety actions, and sheet navigation are
allowed. They do not alter the five-tab hierarchy or card information order.
