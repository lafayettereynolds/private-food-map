# My Map and My List Layout Contract

References: canonical Web Map/List topology plus Lafayette's later title,
filter, image, and marker decisions.

## Shared top structure

From top to content:

1. safe-area breathing room;
2. centered `我的地图 + map icon` or `我的列表 + list icon` group;
3. equal `去过 / 想吃 / 推荐` primary tabs;
4. one horizontally scrolling compact FilterBar;
5. Map or List content.

The title and icon form one centered HStack. The icon is the only Map/List
switch, has a 44 pt target, and announces the destination. No second segmented
row or floating Map/List control exists. Switching preserves scope, query,
city, filters, and sort.

Each primary scope owns its own filters/search/sort: a first visit to `想吃` or
`推荐` does not inherit `去过` conditions, and returning restores that scope's
query. Scope switches keep the same viewport and mounted map; only an explicit
filter/search edit may fit its accepted result, never an obsolete async result.

## Map geometry

- The map is the dominant first-screen visual and begins immediately below the
  compact filters.
- `添加餐厅` is centered above the root tab bar and must not cover the location
  control or selected marker.
- User location is a circular avatar with a subtle halo.
- Map markers show Restaurant imagery, never quantity numbers, count circles,
  or numeric stack badges. City-scale density remains natural overlap between
  distinct Restaurants at their real coordinates.
- Browser and iOS Restaurant markers keep their circle centers on the exact map
  projection of a real source Restaurant coordinate. Native MapKit keeps its
  annotation/hit frame fixed at `44 × 44pt`; only the centered unselected inner
  visual scales continuously from 28 pt nearby to 24 pt far
  away. Including the existing 2 pt white ring on each side, the visible outer
  circle is 28–32 pt; Native selection adds only 2–4 pt to the inner diameter.
  Browser uses shared overall sizes of 32 px normal / 36 px selected on mobile
  and desktop, without continuous diameter scaling. The whole normal circle,
  not merely its central image, must remain within roughly twice ordinary POIs'
  visual size. The rating/dashed ring and hairline remain; the shadow is weaker.
- At city and street scales (`≤0.8°` latitude span), every distinct Restaurant
  coordinate retains its own centered image marker; overlapping circles are
  not hidden or displaced. Only exact latitude/longitude matches may share a
  stack/list, without a numeric badge. Proximity is not a same-location identity.
- Above `0.8°`, wider-area grouping progressively increases its collision
  radius to the full value at `2.4°`. It shows the highest-priority real member's
  own Restaurant image at that member's coordinate, never a quantity number.
  Tap zooms toward its members; exact-coordinate stacks open the real complete
  member list using `此处` wording. These are scale controls, not detection of
  administrative boundaries or a shared mall.
- Exact-coordinate stacks show up to three actual member visuals: the
  highest-priority Restaurant in front and up to two real member-image/fallback
  layers behind, not empty outline plates or copies of the leader. Front-circle
  center remains the exact geographic anchor. Back layers use fixed local
  offsets `(-10, -8)` and `(8, -10)` inside the composite only; no stored coordinate
  or independent marker moves. All members remain accessible in the list.
- Every group retains all original member IDs and coordinates and uses a stable
  real source-coordinate anchor. Higher scores appear in front: personal
  ordering uses rating, then visit count, then stable ID; recommendations use
  their shared rank only to break equal-rating ties. This
  ordering chooses the actual Restaurant shown at wider-area scale.
  Zooming in and out reversibly splits and aggregates the same records.
- No collision-avoidance offset, free slot, root-frame resizing or bottom anchor
  may move a Restaurant circle as it grows, shrinks or becomes selected.
- A pure pan preserves marker IDs, image contents, groups and layer order; it
  does not requery by viewport, clear loaded images or reshuffle the arrangement.
  Zoom updates grouping progressively on both engines; Native MapKit additionally
  scales circle size continuously. Neither changes the geographic center of a
  visible Restaurant circle.
- Deterministic z-order: selected → rating → visit count → stable ID.
- Selected state remains tappable and visually discernible without turning all
  markers into a wall.

## List geometry

### Latest far-distance sizing override (2026-09-05)

The near/regional sizes above remain unchanged through `2.4°` latitude span.
Beyond that, logarithmic progress to `80°` shrinks Native inner diameter 24→10 pt
(outer 28→14 pt) and Browser CSS border-box 32→14 px. Pending and selected
emphasis taper to 1 pt. The 44-point anchor remains fixed; zooming back restores
the baseline. Visual shrinking does not change the independent grouping radius.
The rejected nearby five-image flower layout must not return: no 35 m / 24 px
proximity substitution or fixed slots for different geographic coordinates.

### Shared list composition

- The same header/tabs/filters remain; search may enter the same horizontal
  filter row rather than create another large header tier.
- Context label/count precedes rows.
- Restaurant rows remain compact but information-rich: a prominent square Restaurant image, name and detail disclosure, 10-point rating, Visit/status context, optional real per-person spend, address, optional latest Visit date, up to three real Restaurant tags, and an optional personal impression or recommendation reason. Missing fields collapse instead of being fabricated; compact row actions follow only when the calling surface can execute them truthfully.
- Images preserve the canonical renderer and a stable square/compact ratio.
- `添加餐厅` remains above the tab bar without obscuring row actions.

## States

Cover visited/want/recommended rich and empty states; filtered-to-zero; search
zero; selected marker; dense overlap; missing image; long Restaurant name;
location denied/reduced; offline; Light/Dark; small screen; Dynamic Type.

## Prohibited

No `适合你`, fabricated/decorative aggregate, top Map/List segmented control,
GPS icon for city, separate filter system, random z-order, artificial marker
displacement, circle bottom anchoring, or decorative image over a lawful real
Restaurant photo. Verify the actual visible circle's projection error and outer
diameter during and after zoom/pan; unchanged stored coordinates or a fixed
44-point root frame alone do not establish visible-circle anchoring.
