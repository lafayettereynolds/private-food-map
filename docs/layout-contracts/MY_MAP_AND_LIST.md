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

## Map geometry

- The map is the dominant first-screen visual and begins immediately below the
  compact filters.
- `添加餐厅` is centered above the root tab bar and must not cover the location
  control or selected marker.
- User location is a circular avatar with a subtle halo.
- Restaurants remain independent markers at every zoom; no count cluster.
- Natural overlap is allowed. No default offset/spiderfy/collision dispersion.
- Deterministic z-order: selected → rating → visit count → stable ID.
- Selected state remains tappable and visually discernible without turning all
  markers into a wall.

## List geometry

- The same header/tabs/filters remain; search may enter the same horizontal
  filter row rather than create another large header tier.
- Context label/count precedes rows.
- Restaurant rows are dense: thumbnail, name, visit/rating line, address, then
  compact row actions when allowed.
- Images preserve the canonical renderer and a stable square/compact ratio.
- `添加餐厅` remains above the tab bar without obscuring row actions.

## States

Cover visited/want/recommended rich and empty states; filtered-to-zero; search
zero; selected marker; dense overlap; missing image; long Restaurant name;
location denied/reduced; offline; Light/Dark; small screen; Dynamic Type.

## Prohibited

No `适合你`, numeric/Food count cluster, top Map/List segmented control,
GPS icon for city, separate filter system, random z-order, or decorative image
over a lawful real Restaurant photo.
