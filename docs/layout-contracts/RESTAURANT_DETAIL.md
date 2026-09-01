# Canonical Restaurant Detail Layout Contract

All Map, List, Search, Nearby, Discovery, Community, public profile, Lists,
Roulette, Analytics, On This Day, and public-share entries resolve to the same
`RestaurantDetailStandardBody`. `entrySource` affects navigation/analytics/
permission only.

## Canonical section order

1. Restaurant hero/cover.
2. City and visited/want-to-go status.
3. Restaurant name.
4. Address.
5. Compact action row.
6. Reference spend.
7. Phone.
8. Opening hours.
9. Compact directions row.
10. Rating reference.
11. My rating.
12. All-user rating.
13. Friend rating.
14. Similar-taste rating.
15. User photos.
16. My visit overview.
17. Visit history.
18. Dishes and detailed ratings/downstream content.

## Geometry

- Hero is full content width with a stable media ratio and rounded corners.
- Identity is left-aligned and dense; status is a compact trailing value.
- Actions are one scrollable row of consistent 44 pt circular targets, not a
  two-row wall of equally weighted cards.
- Business facts are compact rows/cards; directions does not reserve a static
  map hero.
- Rating circles stay a coherent horizontal/reference group. Large circle =
  score; small circle = sample count. Missing values are omitted, never zero.
- User photos appear before personal visit history.
- A repeat-visit action clears bottom safe area without covering content.

## States

Real image, missing image, long name/address, missing phone/hours/price,
one/four/no rating references, many photos, no photos, no visits, many visits,
read-only remote, candidate preview, deleted/missing entity, Light/Dark, Dynamic
Type, and small screen.

## Prohibited

No entry-specific Detail body; no image resolver fork; no reordered upper body;
no aggregate score in place of a missing reference; no duplicate full-width
CTA wall.
